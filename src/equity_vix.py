"""Python port of the equity-VIX portfolio construction in the official replication code
(Tables/Table 1&2/Table1&2.sas), variable names kept close to the SAS code.

For every formation date `date` (3rd Friday, previous session if holiday) and underlying:
  * options = next-month standard expiration (exdate), held to exdate_trade (its last trading day);
  * OTM puts (K <= Forward) and OTM calls (K > Forward); Simpson weights; stock/bond legs;
  * static payoff at exdate_trade + model-free corridor daily hedge  ->  Dynamic_VIX_Return_Corridor.

Two samples, exactly as in the SAS code:
  sample="hold": open_interest>0 (if OI available), delta available, bid>0, bid<=ask   (simpson_return)
  sample="sort": delta available, bid<=ask                                           (simpson_return_0_oi_bid)

Data substitutions (PROXY): OPRA consolidated NBBO at 15:59 ET instead of OptionMetrics closing
best bid/offer; Black-Scholes IV/delta availability instead of OptionMetrics' binomial IV;
DoltHub raw closes instead of CRSP; FRED T-bill CMT curve instead of OptionMetrics zero curve.
"""
import os, sys, datetime as dt
import numpy as np, pandas as pd
from scipy.stats import norm

sys.path.insert(0, os.path.dirname(__file__))
from calendar_utils import third_friday, prev_session_on_or_before

DATA = os.environ.get("SOM_DATA", "/home/user/data")


# --------------------------------------------------------------------------- rates
class RateCurve:
    """Continuously-compounded annual rate (in %, like OptionMetrics linear_rate) for a date and
    horizon in calendar days, linearly interpolated between the 1M and 3M T-bill CMT yields."""

    def __init__(self):
        r1 = pd.read_csv(os.path.join(DATA, "rates", "DGS1MO.csv"), na_values=".")
        r3 = pd.read_csv(os.path.join(DATA, "rates", "DGS3MO.csv"), na_values=".")
        r = r1.merge(r3, on="observation_date", how="outer")
        r["date"] = pd.to_datetime(r["observation_date"])
        r = r.set_index("date")[["DGS1MO", "DGS3MO"]].sort_index().ffill()
        full = pd.date_range(r.index.min(), pd.Timestamp("2027-01-01"))
        self.r = r.reindex(full).ffill()

    def linear_rate(self, date, days):
        row = self.r.loc[pd.Timestamp(date)]
        y1, y3 = row["DGS1MO"], row["DGS3MO"]
        days = np.asarray(days, dtype=float)
        w = np.clip((days - 30.0) / (91.0 - 30.0), 0.0, 1.0)
        y = (1 - w) * y1 + w * y3  # bond-equivalent %, convert to continuous
        d = np.maximum(days, 1.0)
        return 100.0 * np.log1p(y / 100.0 * d / 365.0) * 365.0 / d


# --------------------------------------------------------------------------- BS helpers
def bs_price(S, K, T, r, sig, cp):
    sq = sig * np.sqrt(T)
    d1 = (np.log(S / K) + (r + 0.5 * sig * sig) * T) / sq
    d2 = d1 - sq
    call = S * norm.cdf(d1) - K * np.exp(-r * T) * norm.cdf(d2)
    put = K * np.exp(-r * T) * norm.cdf(-d2) - S * norm.cdf(-d1)
    return np.where(cp == "C", call, put)


def implied_vol(price, S, K, T, r, cp, lo=1e-4, hi=8.0, n_iter=60):
    """Vectorised bisection; NaN where no solution (mirrors OptionMetrics missing IV/delta)."""
    price = np.asarray(price, float)
    disc = K * np.exp(-r * T)
    lower = np.where(cp == "C", np.maximum(S - disc, 0.0), np.maximum(disc - S, 0.0))
    upper = np.where(cp == "C", S, disc)
    ok = (price > lower + 1e-12) & (price < upper) & (T > 0)
    a = np.full(price.shape, lo)
    b = np.full(price.shape, hi)
    for _ in range(n_iter):
        m = 0.5 * (a + b)
        pm = bs_price(S, K, T, r, m, cp)
        high = pm > price
        b = np.where(high, m, b)
        a = np.where(high, a, m)
    iv = 0.5 * (a + b)
    iv = np.where(ok & (iv < hi * 0.999), iv, np.nan)
    return iv


def bs_delta(S, K, T, r, sig, cp):
    d1 = (np.log(S / K) + (r + 0.5 * sig * sig) * T) / (sig * np.sqrt(T))
    return np.where(cp == "C", norm.cdf(d1), norm.cdf(d1) - 1.0)


# --------------------------------------------------------------------------- expirations
def next_standard_expiry(date: dt.date):
    """Next month's standard monthly expiration (3rd Friday) and its last trading day."""
    y, m = (date.year + (date.month // 12), date.month % 12 + 1)
    tf = third_friday(y, m)
    return tf, prev_session_on_or_before(tf)


def normalize_root(x: pd.Series) -> pd.Series:
    return x.str.replace(".", "", regex=False).str.replace(" ", "", regex=False).str.replace("/", "", regex=False)


# --------------------------------------------------------------------------- core
def select_chain(snap: pd.DataFrame, date: dt.date):
    """Options on `date` whose expiration is next month's standard expiration.
    OSI dates: Friday (post-2015), Saturday (pre-2015), Thursday (holiday Friday)."""
    tf, exdate_trade = next_standard_expiry(date)
    ok_exp = {pd.Timestamp(tf), pd.Timestamp(tf + dt.timedelta(days=1))}
    if exdate_trade != tf:  # holiday Friday: series expire on the preceding Thursday
        ok_exp.add(pd.Timestamp(exdate_trade))
    ch = snap[snap["expiration"].isin(ok_exp)].copy()
    for c in ("root", "cp", "symbol"):
        ch[c] = ch[c].astype(str)
    ch = ch[~ch["root"].str.contains(r"\d", regex=True)]  # adjusted / non-standard deliverables
    ch["exdate"] = pd.Timestamp(tf)
    ch["exdate_trade"] = pd.Timestamp(exdate_trade)
    return ch


def build_firm_months(date: dt.date, chain: pd.DataFrame, stk: "StockData", rates: RateCurve,
                      sample: str = "hold", oi: pd.DataFrame = None, spot_check: pd.DataFrame = None, tol=0.05,
                      x_quotes: pd.Series = None, tol_end=0.03, spot_check_end: pd.Series = None,
                      x_coverage: float = 1.0):
    """Return per-(root,date) DataFrame with VIX_Prc, Dynamic_VIX_Return_Corridor, etc.
    PROXY data hygiene (replaces CRSP PERMNO linking; uses quotes only, never returns):
      spot_check: option-implied spot at formation; drop if |S_impl/St_start - 1| > tol.
      x_quotes:   bid/ask of the held series on the expiration day (15:59); for the K0 put and K1 call the
                  intrinsic value at DoltHub's St_end must lie within [bid, ask] +/- tol_end*St_end,
                  otherwise the firm-month is dropped (renamed/adjusted contracts, ticker reuse, bad prints).
      spot_check_end: option-implied spot on the expiration day from the NEXT-month chain; used only when
                  neither held leg is quoted on the expiration day.
      x_coverage: market-wide share of the formation chain's series present on the expiration-day snapshot.
                  >= 0.9 (feed lists unquoted series, pre-2025): both held legs missing => contracts were
                  renamed/adjusted => drop.  < 0.9 (2025+ feed omits unquoted expiring series): drop only if
                  both legs missing AND (|S_impl_end/St_end-1| > tol OR a one-day |log return| > ln 2 in the
                  holding window, i.e. a ticker splice)."""
    date_ts = pd.Timestamp(date)
    o = chain.copy()
    o = o.rename(columns={"bid": "best_bid", "ask": "best_offer", "strike": "strike_price", "cp": "cp_flag"})
    if sample == "sort":  # spec P22: undefined bid with a defined ask = zero bid (kept in sorting sample)
        o.loc[o["best_bid"].isna() & o["best_offer"].notna(), "best_bid"] = 0.0
    o = o[o["best_bid"].notna() & o["best_offer"].notna()]
    if sample == "hold":
        if oi is not None:
            o = o.merge(oi[["symbol", "open_interest"]], on="symbol", how="left")
            o = o[o["open_interest"] > 0]
        o = o[o["best_bid"] != 0]
    o = o[~(o["best_bid"] > o["best_offer"])]
    o["Mid_quote"] = (o["best_offer"] + o["best_bid"]) / 2.0
    o["days_expire"] = (o["exdate_trade"] - o["date"]).dt.days
    o = o.drop_duplicates(["root", "strike_price", "cp_flag"])

    # ---- firm-month filters: dividends / splits in (date, exdate_trade], $5, common shares
    o["ticker"] = stk.root_to_ticker(o["root"])
    o = o[o["ticker"].notna()]
    exdt = o["exdate_trade"].iloc[0] if len(o) else None
    if exdt is None:
        return pd.DataFrame()
    bad = stk.event_tickers(date_ts, exdt)
    o = o[~o["ticker"].isin(bad)]
    st = stk.close_on(date_ts)
    o["St_start"] = o["ticker"].map(st)
    o = o[o["St_start"] >= 5]
    o = o[o["ticker"].map(stk.common).fillna(stk.unknown_common_default) == 1]

    # ---- delta availability (IV solvable) - OptionMetrics proxy
    T = o["days_expire"].values / 365.0
    lin = rates.linear_rate(date_ts, o["days_expire"].values)
    rcc = lin / 100.0
    iv = implied_vol(o["Mid_quote"].values, o["St_start"].values, o["strike_price"].values, T, rcc, o["cp_flag"].values)
    o["impl_volatility"] = iv
    o["delta"] = bs_delta(o["St_start"].values, o["strike_price"].values, T, rcc, np.where(np.isnan(iv), 0.3, iv),
                          o["cp_flag"].values)
    o.loc[np.isnan(iv), "delta"] = np.nan
    o = o[o["delta"].notna()]
    o["linear_rate"] = rates.linear_rate(date_ts, o["days_expire"].values)

    # ---- forward, OTM selection, arbitrage bounds
    o["Forward"] = o["St_start"] * np.exp(o["linear_rate"] / 100 * o["days_expire"] / 365)
    o = o[~((o["cp_flag"] == "P") & (o["strike_price"] > o["Forward"]))]
    o = o[~((o["cp_flag"] == "C") & (o["strike_price"] <= o["Forward"]))]
    K, S = o["strike_price"], o["St_start"]
    arb = ((o["cp_flag"] == "P") & (K < o["best_bid"])) | \
          ((o["cp_flag"] == "P") & (o["best_offer"] < np.maximum(0, K - S))) | \
          ((o["cp_flag"] == "C") & (S < o["best_bid"])) | \
          ((o["cp_flag"] == "C") & (o["best_offer"] < np.maximum(0, S - K)))
    o = o[~arb]
    if o.empty:
        return pd.DataFrame()

    # ---- K0 (strike immediately below/at forward), K1 (immediately above/at forward)
    below = o[o["Forward"] - o["strike_price"] >= 0].groupby("root")["strike_price"].max().rename("K0")
    above = o[o["strike_price"] - o["Forward"] >= 0].groupby("root")["strike_price"].min().rename("K1")
    o = o.join(below, on="root").join(above, on="root")
    o = o[o["K0"].notna() & o["K1"].notna()]

    # ---- counts
    num_put = o[o["cp_flag"] == "P"].groupby("root").size().rename("num_put")
    num_call = o[o["cp_flag"] == "C"].groupby("root").size().rename("num_call")

    # ---- Simpson weights (sort by strike, descending cp_flag -> P before C at equal strike)
    o = o.sort_values(["root", "strike_price", "cp_flag"], ascending=[True, True, False]).reset_index(drop=True)
    g = o.groupby("root")["strike_price"]
    lagK = g.shift(1)
    leadK = g.shift(-1)
    first = o["root"] != o["root"].shift(1)
    last = o["root"] != o["root"].shift(-1)
    dK = (leadK - lagK) / 2.0
    dK = np.where(first, leadK - o["strike_price"], dK)
    dK = np.where(last, o["strike_price"] - lagK, dK)
    o["delta_K"] = dK
    w = 2 * o["delta_K"] / o["strike_price"] ** 2
    atK0 = o["strike_price"] == o["K0"]
    atK1 = o["strike_price"] == o["K1"]
    w = np.where(atK0, w + (o["K1"] - o["K0"] - o["delta_K"]) / 3 / o["K0"] ** 2, w)
    w = np.where(atK1, w + (o["K1"] - o["K0"] - o["delta_K"]) / 3 / o["K1"] ** 2, w)
    o["Weight_eachoption"] = w
    o["wp"] = w * o["Mid_quote"]
    o["wp_bid"] = w * o["best_bid"]
    o["wp_ask"] = w * o["best_offer"]
    o["wdelta"] = w * o["delta"]
    o["wtick"] = w * np.where(o["Mid_quote"] < 3, 0.01, 0.05)  # COST4: one tick per option

    # ---- strike interval (corridor) info
    si = o.groupby("root").agg(strike_min=("strike_price", "min"), strike_max=("strike_price", "max"),
                               IV_avg=("impl_volatility", "mean"))
    dmin = o[o["strike_price"] == o["root"].map(si["strike_min"])].groupby("root")["delta_K"].first().rename("delta_min")
    dmax = o[o["strike_price"] == o["root"].map(si["strike_max"])].groupby("root")["delta_K"].last().rename("delta_max")

    # ---- terminal payoff
    exdt = o["exdate_trade"].iloc[0]
    st_end = stk.close_on(exdt)
    o["St_end"] = o["ticker"].map(st_end)
    pay = np.where(o["cp_flag"] == "C", np.maximum(o["St_end"] - o["strike_price"], 0),
                   np.maximum(o["strike_price"] - o["St_end"], 0))
    o["Option_TerminalPayoff"] = o["Weight_eachoption"] * pay

    fm = o.groupby("root").agg(ticker=("ticker", "first"), sigma2=("wp", "sum"), sigma2_bid=("wp_bid", "sum"),
                               sigma2_ask=("wp_ask", "sum"), Initial_delta=("wdelta", "sum"),
                               sigma2_tick=("wtick", "sum"),
                               Forward=("Forward", "first"), K0=("K0", "first"), K1=("K1", "first"),
                               days_expire=("days_expire", "first"), linear_rate=("linear_rate", "first"),
                               St_start=("St_start", "first"), St_end=("St_end", "first"),
                               Option_TerminalPayoff=("Option_TerminalPayoff", "sum"),
                               exdate=("exdate", "first"), exdate_trade=("exdate_trade", "first"),
                               n_opt=("strike_price", "size"))
    # SAS: Option_TerminalPayoff computed only where stock_prc_end is not missing
    fm = fm.join(si).join(dmin).join(dmax).join(num_put).join(num_call)
    fm = fm[fm["St_end"].notna()]
    if spot_check is not None:
        dev0 = np.abs(spot_check["S_impl_start"].reindex(fm.index) / fm["St_start"] - 1)
        fm = fm[~(dev0 > tol).fillna(False).astype(bool)]  # NaN (parity not computable) is kept
    fm["Rf"] = np.exp(fm["linear_rate"] / 100 * fm["days_expire"] / 365)
    A = (fm.K1 - fm.K0) / 3 * (1 / fm.K0 ** 2 - 1 / fm.K1 ** 2) + (2 / fm.Forward - 1 / fm.K0 - 1 / fm.K1)
    B = (fm.K1 - fm.K0) / 3 * (1 / fm.K1 - 1 / fm.K0) + (np.log(fm.Forward / fm.K0) + np.log(fm.Forward / fm.K1))
    fm["Static_VIX_Payoff"] = fm.Option_TerminalPayoff + A * fm.St_end + B
    fm["VIX_Prc"] = fm.sigma2 + A * fm.St_start + B / fm.Rf
    fm["VIX_Prc_bid"] = fm.sigma2_bid + A * fm.St_start + B / fm.Rf
    fm["VIX_Prc_ask"] = fm.sigma2_ask + A * fm.St_start + B / fm.Rf
    fm["Static_VIX_Return"] = fm.Static_VIX_Payoff / fm.VIX_Prc - 1
    fm["VIX_BA_percent"] = (fm.VIX_Prc_ask - fm.VIX_Prc_bid) / fm.VIX_Prc
    fm = fm[fm["VIX_Prc_bid"] > 0]

    # ---- corridor model-free daily hedge
    L = fm.strike_min - fm.delta_min / 2
    U = fm.strike_max + fm.delta_max / 2
    daily = stk.window(fm["ticker"], date_ts, fm["exdate"].iloc[0])  # rows: ticker,date,close,ret
    daily = daily.merge(fm[["ticker", "linear_rate", "exdate_trade"]].reset_index(), on="ticker")
    daily = daily.merge(pd.DataFrame({"root": fm.index, "L": L.values, "U": U.values}), on="root")
    daily = daily.sort_values(["root", "date"])
    Rf_daily = np.exp(daily["linear_rate"] / 100 / 365)
    tt = (daily["exdate_trade"] - daily["date"]).dt.days
    daily["Forward_daily"] = daily["close"] * np.exp(daily["linear_rate"] / 100 * tt / 365)
    daily["FDC"] = daily["Forward_daily"].clip(lower=daily["L"], upper=daily["U"])
    gd = daily.groupby("root")
    lagFDC = gd["FDC"].shift(1)
    lagS = gd["close"].shift(1)
    lagD = gd["date"].shift(1)
    gap = (daily["date"] - lagD).dt.days
    daily["Delta_Hedge_Corridor"] = 2 / lagFDC * lagS * (1 + daily["ret"] - Rf_daily ** gap) * Rf_daily ** tt
    daily["Delta_Hedge_Reinvt"] = 2 / (Rf_daily ** (daily["exdate_trade"] - lagD).dt.days) * \
        (1 + daily["ret"] - Rf_daily ** gap) * Rf_daily ** tt
    daily["DHC_Theory"] = 2 * (daily["Forward_daily"] / daily["FDC"]) * (daily["FDC"] / lagFDC - 1)
    daily["ret2"] = daily["ret"] ** 2
    daily["alr"] = np.log1p(daily["ret"]).abs()
    Amap = A.reindex(fm.index)
    stat = Amap - 2 / (fm.St_start * fm.Rf)
    daily["n_sh"] = daily["root"].map(stat) + 2 / daily["FDC"]
    n_prev = daily["root"].map(stat) + 2 / lagFDC
    daily["dn_dollar"] = (daily["n_sh"] - n_prev).abs() * daily["close"]
    first_row = daily["date"] == date_ts
    daily.loc[first_row, "dn_dollar"] = (daily.loc[first_row, "n_sh"]).abs() * daily.loc[first_row, "close"]
    lastd = daily.groupby("root")["date"].transform("max") == daily["date"]
    daily["close_out"] = np.where(lastd, daily["n_sh"].abs() * daily["close"], 0.0)
    to = daily.groupby("root").agg(hedge_turnover=("dn_dollar", "sum"), hedge_close=("close_out", "sum"))
    daily = daily[daily["date"] != date_ts]  # SAS: if date_daily=date then delete
    hp = daily.groupby("root").agg(Delta_Hedge_payoff_Corridor=("Delta_Hedge_Corridor", "sum"),
                                   Delta_Hedge_payoff=("Delta_Hedge_Reinvt", "sum"),
                                   Delta_Hedge_Corridor_Theory=("DHC_Theory", "sum"),
                                   Monthly_RV=("ret2", "sum"), n_days=("date", "size"), max_abs_logret=("alr", "max"))
    fm = fm.join(hp).join(to)
    fm["hedge_turnover"] = fm["hedge_turnover"] + fm["hedge_close"]  # $ stock traded per unit of VIX portfolio
    if x_quotes is not None:
        k0 = o[(o["strike_price"] == o["K0"]) & (o["cp_flag"] == "P")].groupby("root")["symbol"].first()
        k1 = o[(o["strike_price"] == o["K1"]) & (o["cp_flag"] == "C")].groupby("root")["symbol"].first()
        def dist(sym, intr):  # distance of intrinsic value outside the expiration-day [bid, ask]
            b = sym.map(x_quotes["bid"]).reindex(fm.index)
            a = sym.map(x_quotes["ask"]).reindex(fm.index)
            return np.maximum(np.maximum(b - intr, intr - a), 0.0)
        e0 = dist(k0, np.maximum(fm["K0"] - fm["St_end"], 0))
        e1 = dist(k1, np.maximum(fm["St_end"] - fm["K1"], 0))
        err = pd.concat([e0, e1], axis=1).max(axis=1)  # max over the available legs (NaN if both missing)
        fm["end_check_err"] = err / fm["St_end"]
        bad = (fm["end_check_err"] > tol_end).fillna(False).astype(bool)
        both_missing = fm["end_check_err"].isna()
        if x_coverage >= 0.9:
            bad = bad | both_missing
        else:
            dev1 = (spot_check_end.reindex(fm.index) / fm["St_end"] - 1).abs() if spot_check_end is not None \
                else pd.Series(np.nan, index=fm.index)
            jump = fm["max_abs_logret"] > np.log(2)
            bad = bad | (both_missing & ((dev1 > tol).fillna(False).astype(bool) | jump.fillna(False).astype(bool)))
        fm = fm[~bad]
    fm["Dynamic_VIX_Payoff_Corridor"] = fm.Static_VIX_Payoff - 2 * (fm.St_end / fm.St_start / fm.Rf - 1) + \
        fm.Delta_Hedge_payoff_Corridor
    fm["Dynamic_VIX_Return_Corridor"] = fm.Dynamic_VIX_Payoff_Corridor / fm.VIX_Prc - 1
    fm["Dynamic_VIX_Return"] = (fm.Static_VIX_Payoff - 2 * (fm.St_end / fm.St_start / fm.Rf - 1) +
                                fm.Delta_Hedge_payoff) / fm.VIX_Prc - 1
    fm["VSR"] = fm.Monthly_RV / fm.VIX_Prc - 1
    fwd_start_c = fm.Forward.clip(lower=L, upper=U)
    fwd_end_c = fm.St_end.clip(lower=L, upper=U)
    fm["RV_Corridor"] = -2 * np.log(fwd_end_c / fwd_start_c) + fm.Delta_Hedge_Corridor_Theory
    fm["VSR_Corridor"] = fm.RV_Corridor / fm.VIX_Prc - 1

    fm["num_put"] = fm["num_put"].fillna(0)
    fm["num_call"] = fm["num_call"].fillna(0)
    fm["num_strikes"] = fm["num_put"] + fm["num_call"]
    fm = fm[fm["num_strikes"] > 2]
    fm["rf"] = fm["Rf"] - 1
    fm["date"] = date_ts
    fm["sample"] = sample
    return fm.reset_index()


# --------------------------------------------------------------------------- stock data access
class StockData:
    def __init__(self, unknown_common_default=1):
        from stock_panel import load_ohlcv, load_dividends, load_splits, load_symbols, detect_price_splits
        self.px = load_ohlcv()
        self.px_idx = self.px.set_index(["date", "act_symbol"])["close"]
        self.by_date = {d: g.set_index("act_symbol")["close"] for d, g in self.px.groupby("date")}
        self.div = load_dividends()
        spl = load_splits()
        auto = detect_price_splits(self.px)
        auto = auto[auto["ex_date"] < pd.Timestamp("2014-04-01")]
        self.splits = pd.concat([spl[["act_symbol", "ex_date"]], auto], ignore_index=True)
        sym = load_symbols()
        self.common = sym["common"]
        self.unknown_common_default = unknown_common_default
        tick = pd.Index(self.px["act_symbol"].unique())
        self._norm = pd.Series(tick, index=normalize_root(pd.Series(tick)).values)
        self._norm = self._norm[~self._norm.index.duplicated()]

    def root_to_ticker(self, roots: pd.Series) -> pd.Series:
        return roots.map(self._norm)

    def close_on(self, d):
        return self.by_date.get(pd.Timestamp(d), pd.Series(dtype=float))

    def event_tickers(self, start, end):
        d = self.div[(self.div.ex_date > start) & (self.div.ex_date <= end)]["act_symbol"]
        s = self.splits[(self.splits.ex_date > start) & (self.splits.ex_date <= end)]["act_symbol"]
        return set(d) | set(s)

    def window(self, tickers, start, end):
        t = set(tickers)
        x = self.px[(self.px["date"] >= start) & (self.px["date"] <= end) & self.px["act_symbol"].isin(t)]
        return x.rename(columns={"act_symbol": "ticker"})[["ticker", "date", "close", "ret"]]


def implied_spots(chain: pd.DataFrame, date, rates: "RateCurve", ref_spot: pd.Series = None):
    """Robust option-implied spot per root at formation from the traded next-month chain:
    median over strikes within +/-15% of the reference spot of K + e^{rT}(C - P), discounted, using
    only strikes where both C and P have bid > 0 and relative spread < 50%. Roots with fewer than two
    usable strikes get NaN (no check). Vectorised."""
    ch = chain[(chain["bid"] > 0) & (chain["ask"] > 0)].copy()
    if ch.empty:
        return pd.DataFrame(columns=["S_impl_start", "n_parity"])
    ch["mid"] = (ch["bid"] + ch["ask"]) / 2
    ch = ch[(ch["ask"] - ch["bid"]) / ch["mid"] < 0.5]
    days = (ch["exdate_trade"].iloc[0] - pd.Timestamp(date)).days
    r = float(rates.linear_rate(pd.Timestamp(date), [days])[0]) / 100
    T = days / 365
    pv = ch.pivot_table(index=["root", "strike"], columns="cp", values="mid", aggfunc="first").dropna()
    if pv.empty or "C" not in pv or "P" not in pv:
        return pd.DataFrame(columns=["S_impl_start", "n_parity"])
    pv = pv.reset_index()
    pv["S_k"] = (pv["strike"] + np.exp(r * T) * (pv["C"] - pv["P"])) * np.exp(-r * T)
    if ref_spot is not None:
        ref = pv["root"].map(ref_spot)
        pv = pv[(pv["strike"] / ref - 1).abs() <= 0.15]
    g = pv.groupby("root")["S_k"]
    out = pd.DataFrame({"S_impl_start": g.median(), "n_parity": g.size()})
    out.loc[out["n_parity"] < 2, "S_impl_start"] = np.nan
    return out
