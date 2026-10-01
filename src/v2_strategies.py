"""RETAIL V2 — Phases B, C, D, E on the V2 leg table (RETAIL_V2_CHARTER.md §6, ledger row 2).

Structures
  * A structure is a list of legs (expiry, tag, signed quantity q, optional per-root ratio column). Its "L"
    direction holds the legs as specified; its "S" direction is the exact reverse.
  * Option P&L is split into GROSS mid-to-mid P&L ("opt") and execution cost ("cost": e*half-spread at entry and
    exit + $0.70/contract/side). A long contract whose exit bid is 0 is abandoned at 0 (no exit commission).
  * Hedging is computed on the structure's NET delta: H1 entry-only, H2 daily (net entry/exit delta + summed daily
    delta changes; exact for same-sign-gamma structures, an upper bound otherwise), H3 threshold (25 sh/unit,
    straddles only). Stock fees: max($1 x orders, $0.005/share) + 2 bps of notional; 0.25%/yr borrow on short
    stock. Hedge P&L is zeroed when the X-date spot validation fails (costs kept).
  * Premium financing at rf on net premium paid ("fin").
  * Delisted names (no DoltHub close at X) whose exit quotes are missing: pure-long structures lose 100% of mid
    premium + entry costs; anything with short legs is dropped and counted. Non-delisted units with a missing exit
    leg (BACK, unquoted) are dropped and counted.
Levels: GROSS (mid, no commissions, no hedge fees), MID (mid + commissions + fees), C25, C50 (primary), C100.
Returns are per $ of long premium at mid, equal premium per long position, unless a family says otherwise.
FORWARD (exit months >= 2024-01) is not computed before a candidate is frozen (HIDE_FWD).
"""
import os, sys, glob, json
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(__file__))
from paper_core import newey_west_t
import v2_universe

DATA = os.environ.get("SOM_DATA", "/home/user/data")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "results", "v2")
COMM = 0.70
STOCK_FEE, MIN_ORDER, SLIP, BORROW = 0.005, 1.0, 0.0002, 0.0025
E = {"GROSS": 0.0, "MID": 0.0, "C25": 0.25, "C50": 0.5, "C100": 1.0}
LEVELS = tuple(E)
HEDGES = ("H0", "H1", "H2", "H3")
COMP = ("opt", "cost", "hedge", "hcost", "fin", "tot")
WIN = {"DISC": ("2014-02-01", "2020-12-31"), "VAL": ("2021-01-01", "2023-12-31"), "FWD": ("2024-01-01", "2026-12-31")}
SECTOR_ETFS = ["XLB", "XLE", "XLF", "XLI", "XLK", "XLP", "XLU", "XLV", "XLY", "XLRE", "XLC"]
HIDE_FWD = True
STRADDLE = lambda exp: [(exp, "ATM_C", 1.0, None), (exp, "ATM_P", 1.0, None)]
LEG_COLS = ["F", "X", "root", "exp", "tag", "strike", "bid", "ask", "vega", "gamma", "x_bid", "x_ask", "D0", "D_last",
            "S_hedge0", "S_hedge_exit", "h1_pnl", "h2_pnl", "chg_sh", "chg_turn", "n_marks"]


# ----------------------------------------------------------------------------------------------- loading
def load_legs(keys=None):
    parts = []
    for f in sorted(glob.glob(os.path.join(DATA, "v2", "legs", "*.parquet"))):
        x = pd.read_parquet(f, columns=LEG_COLS)
        if HIDE_FWD and len(x) and x["X"].iloc[0] > pd.Timestamp("2023-12-31"):
            continue
        parts.append(x)
    L = pd.concat(parts, ignore_index=True)
    if keys is not None:
        L = L.merge(keys[["F", "root"]].drop_duplicates(), on=["F", "root"])
    L["mid"] = (L["bid"] + L["ask"]) / 2
    L["x_mid"] = (L["x_bid"] + L["x_ask"]) / 2
    return L


def load_roots():
    R = v2_universe.load_roots()
    return R[R["X"] <= pd.Timestamp("2023-12-31")] if HIDE_FWD else R


# ----------------------------------------------------------------------------------------------- structures
def struct_base(L, R, spec, ratio=None, spread_mult=1.0, comm=COMM):
    """Per-unit table for one structure: geometry, gross option P&L, cost per level for both directions,
    and the net-delta hedge inputs. spec = [(exp, tag, q, ratio_col_or_None), ...]."""
    parts = []
    for exp, tag, q, rc in spec:
        s = L[(L["exp"] == exp) & (L["tag"] == tag)].copy()
        s["q"] = q
        if rc is not None:
            s = s.merge(ratio[["F", "X", "root", rc]], on=["F", "X", "root"])
            s["q"] = q * s[rc]
        s["leg"] = f"{exp}:{tag}"
        parts.append(s)
    S = pd.concat(parts, ignore_index=True)
    S = S[np.isfinite(S["q"]) & (S["q"] != 0)]
    aq, pos = S["q"].abs(), S["q"] > 0
    hs_in = (S["ask"] - S["bid"]) / 2 * spread_mult
    hs_out = (S["x_ask"] - S["x_bid"]) / 2 * spread_mult
    move = 100 * (S["x_mid"] - S["mid"])
    S["opt"] = S["q"] * move
    abandon = (S["x_bid"] <= 0).values
    for lv in LEVELS:
        if lv == "GROSS":
            S[f"cL_{lv}"] = S[f"cS_{lv}"] = S[f"cIn_{lv}"] = 0.0
            continue
        e = E[lv]
        buy_in, sell_in = S["mid"] + e * hs_in, (S["mid"] - e * hs_in).clip(lower=0)
        sell_out = np.where(abandon, 0.0, (S["x_mid"] - e * hs_out).clip(lower=0))
        buy_out = S["x_mid"] + e * hs_out
        c_long = move - (100 * (sell_out - buy_in) - comm * (1 + (~abandon).astype(float)))
        c_short = -move - (100 * (sell_in - buy_out) - 2 * comm)
        S[f"cL_{lv}"] = np.where(pos, aq * c_long, aq * c_short)
        S[f"cS_{lv}"] = np.where(pos, aq * c_short, aq * c_long)
        S[f"cIn_{lv}"] = aq * (100 * e * hs_in + comm)
    S["prem_L"] = np.where(pos, 100 * aq * S["mid"], 0.0)
    S["prem_S"] = np.where(~pos, 100 * aq * S["mid"], 0.0)
    S["vega_q"] = 100 * S["q"] * S["vega"]
    S["dg_q"] = 100 * S["q"] * S["gamma"] * S["S_hedge0"] ** 2 / 100.0
    S["hs_q"] = 100 * aq * (S["ask"] - S["bid"]) / 2
    for c in ("D0", "D_last", "h1_pnl", "h2_pnl"):
        S[c + "_q"] = S["q"] * S[c]
    S["chg_sh_q"], S["chg_turn_q"] = aq * S["chg_sh"], aq * S["chg_turn"]
    S["miss"] = S["x_mid"].isna()
    agg = {"nleg": ("leg", "nunique"), "miss": ("miss", "max"), "opt": ("opt", "sum"), "prem_L": ("prem_L", "sum"),
           "prem_S": ("prem_S", "sum"), "vega": ("vega_q", "sum"), "dgamma": ("dg_q", "sum"),
           "half_spread": ("hs_q", "sum"), "D0": ("D0_q", "sum"), "Dl": ("D_last_q", "sum"), "h1": ("h1_pnl_q", "sum"),
           "h2": ("h2_pnl_q", "sum"), "chg_sh": ("chg_sh_q", "sum"), "chg_turn": ("chg_turn_q", "sum"),
           "S0h": ("S_hedge0", "first"), "Sx": ("S_hedge_exit", "first"), "n_marks": ("n_marks", "max")}
    for lv in LEVELS:
        for p in ("cL", "cS", "cIn"):
            agg[f"{p}_{lv}"] = (f"{p}_{lv}", "sum")
    B = S.groupby(["F", "X", "root"]).agg(**agg)
    B = B[B["nleg"] == len(spec)].reset_index()
    rcols = ["F", "X", "root", "delisted", "x_flag", "rf_hold"]
    exps = {s[0] for s in spec}
    is_straddle = (len(spec) == 2 and len(exps) == 1 and {s[1] for s in spec} == {"ATM_C", "ATM_P"}
                   and all(s[2] == 1.0 and s[3] is None for s in spec))
    if is_straddle:
        ex = next(iter(exps))
        rcols += [f"{ex}_straddle_h3_pnl", f"{ex}_straddle_h3_sh", f"{ex}_straddle_h3_orders"]
    B = B.merge(R[[c for c in rcols if c in R.columns]], on=["F", "X", "root"], how="left")
    if is_straddle:
        B = B.rename(columns={f"{ex}_straddle_h3_pnl": "h3", f"{ex}_straddle_h3_sh": "h3_sh",
                              f"{ex}_straddle_h3_orders": "h3_orders"})
    else:
        B["h3"] = B["h3_sh"] = B["h3_orders"] = np.nan
    B["delisted"] = B["delisted"].fillna(False).astype(bool)
    B["x_flag"] = B["x_flag"].fillna(False).astype(bool)
    B["hold_days"] = (B["X"] - B["F"]).dt.days
    pure_long = B["prem_S"] == 0
    B["dead_long"] = B["miss"] & B["delisted"] & pure_long      # valued at -100% of premium (long direction)
    B["drop_L"] = B["miss"] & ~B["dead_long"]
    B["drop_S"] = B["miss"]
    B["prem"] = B["prem_L"] + B["prem_S"]
    return B


def view(B, lv, pol, stk_mult=1.0):
    """Component P&L of both directions at cost level lv and hedge policy pol."""
    V = B[["F", "X", "root", "prem", "prem_L", "prem_S", "vega", "dgamma", "half_spread", "D0", "S0h",
           "delisted", "dead_long", "drop_L", "drop_S"]].copy()
    if pol == "H0":
        hp = sh = orders = notional = pd.Series(0.0, index=B.index)
    elif pol == "H1":
        hp, sh = B["h1"], 2 * B["D0"].abs()
        orders = 2.0 * (B["D0"].abs() >= 0.5)
        notional = B["D0"].abs() * (B["S0h"] + B["Sx"])
    elif pol == "H2":
        hp, sh = B["h2"], B["D0"].abs() + B["chg_sh"] + B["Dl"].abs()
        orders = B["n_marks"].astype(float) + 1
        notional = B["D0"].abs() * B["S0h"] + B["chg_turn"] + B["Dl"].abs() * B["Sx"]
    elif pol == "H3":
        hp, sh, orders = B["h3"], B["h3_sh"], B["h3_orders"].astype(float)
        notional = sh * B["S0h"]
    hp = hp.where(~B["x_flag"], 0.0)
    if lv == "GROSS":
        fee = pd.Series(0.0, index=B.index)
        bor_L = bor_S = fee
    else:
        fee = stk_mult * (np.maximum(orders * MIN_ORDER, STOCK_FEE * sh) + SLIP * notional)
        held = 0.0 if pol == "H0" else 1.0
        bor_L = held * BORROW * B["D0"].clip(lower=0) * B["S0h"] * B["hold_days"] / 365
        bor_S = held * BORROW * (-B["D0"]).clip(lower=0) * B["S0h"] * B["hold_days"] / 365
    net_prem = B["prem_L"] - B["prem_S"]
    for d, sgn, c, bor in (("L", 1.0, B[f"cL_{lv}"], bor_L), ("S", -1.0, B[f"cS_{lv}"], bor_S)):
        V[f"{d}_opt"] = sgn * B["opt"]
        V[f"{d}_cost"] = c
        V[f"{d}_hedge"] = sgn * hp
        V[f"{d}_hcost"] = fee + bor
        V[f"{d}_fin"] = B["rf_hold"] * (sgn * net_prem).clip(lower=0)
    # delisted pure-long units with missing exit quotes: long loses all premium; short side undefined
    dl = B["dead_long"]
    V.loc[dl, "L_opt"] = -B.loc[dl, "prem_L"]
    V.loc[dl, "L_cost"] = B.loc[dl, f"cIn_{lv}"]
    for c in COMP[:-1]:
        V.loc[B["drop_L"], f"L_{c}"] = np.nan
        V.loc[B["drop_S"], f"S_{c}"] = np.nan
    for d in ("L", "S"):
        V[f"{d}_tot"] = V[f"{d}_opt"] - V[f"{d}_cost"] + V[f"{d}_hedge"] - V[f"{d}_hcost"] - V[f"{d}_fin"]
    if pol == "H3" and B["h3"].isna().all():
        for d in ("L", "S"):
            V[[f"{d}_{c}" for c in COMP]] = np.nan
    return V


class Book:
    """Caches struct_base tables and their views."""

    def __init__(self, L, R, spread_mult=1.0, comm=COMM, stk_mult=1.0):
        self.L, self.R, self.sm, self.comm, self.stk = L, R, spread_mult, comm, stk_mult
        self.base, self.views = {}, {}

    def get(self, name, spec, lv, pol, ratio=None):
        if name not in self.base:
            self.base[name] = struct_base(self.L, self.R, spec, ratio, self.sm, self.comm)
        k = (name, lv, pol)
        if k not in self.views:
            self.views[k] = view(self.base[name], lv, pol, self.stk)
        return self.views[k]

    def drops(self, name):
        B = self.base[name]
        return {"units": int(len(B)), "drop_L": int(B["drop_L"].sum()), "drop_S": int(B["drop_S"].sum()),
                "dead_long": int(B["dead_long"].sum())}


# ----------------------------------------------------------------------------------------------- portfolio algebra
def agg(df, d, w):
    """Per-X weighted component sums for direction d ('L' or 'S') with weights w (Series aligned to df)."""
    M = df[[f"{d}_{c}" for c in COMP]].mul(np.asarray(w, dtype=float), axis=0)
    M.columns = list(COMP)
    M["X"] = df["X"].values
    return M.groupby("X").sum(min_count=1)


def ew_long(df, d="L", prem_col="prem_L"):
    """Equal-premium long book: per-X components per $ of long premium, plus position count."""
    df = df.dropna(subset=[f"{d}_tot"])
    if df.empty:
        return pd.DataFrame()
    out = agg(df, d, 1.0 / df[prem_col])
    n = df.groupby("X").size()
    return out.div(n, axis=0).assign(n=n)


def hedged(longs, shorts, size, d_long="L", d_short="S"):
    """Long book (equal premium, w=1/prem) + a pooled short book scaled per X by `size`:
    'vega' / 'gamma' neutral, 'premium' (equal $ premium), 'eqrisk' (short premium = half long premium).
    Components per $ of long premium."""
    longs = longs.dropna(subset=[f"{d_long}_tot"]).assign(w=lambda z: 1 / z["prem_L"])
    shorts = shorts.dropna(subset=[f"{d_short}_tot"]).assign(w0=lambda z: 1 / z["prem"])
    if longs.empty or shorts.empty:
        return pd.DataFrame()
    gl = longs.groupby("X").apply(lambda g: pd.Series({"N": len(g), "V": (g["vega"] * g["w"]).sum(),
                                                       "G": (g["dgamma"] * g["w"]).sum()}))
    gs = shorts.groupby("X").apply(lambda g: pd.Series({"Ns": g["w0"].mul(g["prem"]).sum(),
                                                        "Vs": (g["vega"] * g["w0"]).sum(),
                                                        "Gs": (g["dgamma"] * g["w0"]).sum()}))
    j = gl.join(gs, how="inner")
    ratio = {"vega": j["V"] / j["Vs"], "gamma": j["G"] / j["Gs"], "premium": j["N"] / j["Ns"],
             "eqrisk": 0.5 * j["N"] / j["Ns"]}[size]
    shorts = shorts[shorts["X"].isin(j.index)]
    longs = longs[longs["X"].isin(j.index)]
    a = agg(longs, d_long, longs["w"])
    b = agg(shorts, d_short, shorts["w0"] * shorts["X"].map(ratio))
    tot = a.add(b, fill_value=0).div(j["N"], axis=0)
    return tot.assign(n=j["N"])


# ----------------------------------------------------------------------------------------------- stats / verdict
def stats(s):
    s = pd.Series(s).dropna()
    out = {}
    for w, (a, b) in WIN.items():
        x = s[(s.index >= a) & (s.index <= b)]
        if len(x) >= 3:
            sd = x.std(ddof=1)
            out[w] = {"n": int(len(x)), "mean": float(x.mean()), "median": float(x.median()),
                      "t": float(newey_west_t(x)), "sharpe": float(x.mean() / sd * np.sqrt(12)) if sd > 0 else np.nan,
                      "hit": float((x > 0).mean()), "worst": float(x.min())}
    return out


def comp_means(df):
    out = {}
    for w, (a, b) in WIN.items():
        x = df[(df.index >= a) & (df.index <= b)]
        if len(x) >= 3:
            out[w] = {c: float(x[c].mean()) for c in COMP if c in x}
            out[w]["n_pos"] = float(x["n"].mean()) if "n" in x else np.nan
    return out


def verdict(st):
    d, v = st.get("DISC", {}), st.get("VAL", {})
    if not d or not v or not np.isfinite(d.get("t", np.nan)):
        return "FAIL"
    if d["mean"] > 0 and d["t"] > 2 and v["mean"] > 0:
        return "PASS"
    if d["mean"] > 0 and d["t"] > 1 and v["mean"] > 0:
        return "WEAK"
    return "FAIL"


def record(rows, series, fam, pol, lv, df):
    df = df.sort_index()
    series[(fam, pol, lv)] = df
    st = stats(df["tot"])
    cm = comp_means(df)
    row = {"family": fam, "hedge": pol, "cost": lv}
    for w, x in st.items():
        row.update({f"{w}_{k}": v for k, v in x.items()})
    for w, x in cm.items():
        row.update({f"{w}_{k}": v for k, v in x.items() if k != "tot"})
    rows.append(row)


FIXED_HEDGE = {"D2_slope_S_ew": "H1", "D2_slope_S_adv": "H1"}   # charter §6 Phase D: D2 is defined on H1 returns


def family_verdicts(tab):
    """Per family: hedge policy chosen in DISCOVERY at C50 by NW t (charter §6B), verdict at C50, plus MID/GROSS
    reference and the cost share of gross edge. Families whose hedge the charter fixes use that hedge."""
    out = []
    for fam, g in tab.groupby("family", sort=False):
        c50 = g[(g["cost"] == "C50") & g["DISC_t"].notna()]
        if fam in FIXED_HEDGE:
            c50 = c50[c50["hedge"] == FIXED_HEDGE[fam]]
        if c50.empty:
            out.append({"family": fam, "verdict": "FAIL", "note": "no C50 DISC series"})
            continue
        best = c50.loc[c50["DISC_t"].idxmax()]
        pol = best["hedge"]
        st = {w: {"mean": best.get(f"{w}_mean"), "t": best.get(f"{w}_t")} for w in ("DISC", "VAL")}
        st = {w: x for w, x in st.items() if pd.notna(x["mean"])}
        v = verdict(st)
        ref = {lv: g[(g["cost"] == lv) & (g["hedge"] == pol)] for lv in ("GROSS", "MID", "C100")}
        gross_edge = best.get("DISC_opt", np.nan) + best.get("DISC_hedge", np.nan)
        costs = best.get("DISC_cost", np.nan) + best.get("DISC_hcost", np.nan)
        r = {"family": fam, "hedge": pol, "verdict": v,
             "DISC_C50_mean": best.get("DISC_mean"), "DISC_C50_t": best.get("DISC_t"),
             "VAL_C50_mean": best.get("VAL_mean"), "VAL_C50_t": best.get("VAL_t"),
             "DISC_n_months": best.get("DISC_n"), "DISC_n_pos": best.get("DISC_n_pos"),
             "cost_share_of_gross_DISC": float(costs / gross_edge) if gross_edge and gross_edge > 0 else np.nan}
        for lv, x in ref.items():
            if len(x):
                for c in ("DISC_mean", "DISC_t", "VAL_mean"):
                    r[f"{c.split('_')[0]}_{lv}_{c.split('_')[1]}"] = float(x[c].iloc[0]) if c in x else np.nan
        r["mid_only"] = bool(r.get("DISC_MID_mean", -1) > 0 and r.get("DISC_MID_t", 0) > 2 and v == "FAIL")
        out.append(r)
    return pd.DataFrame(out)


# ----------------------------------------------------------------------------------------------- universe helpers
def rank_in(U, flag, sig="S0"):
    d = U[U[flag] & U[sig].notna()].copy()
    d["pct"] = d.groupby("X")[sig].rank(pct=True)
    return d


def sector_map(U):
    """Point-in-time sector proxy on the FULL cross-section: SPDR sector ETF with the highest 252-session
    daily-return correlation, returns with |r| > 40% removed (unadjusted DoltHub splits)."""
    path = os.path.join(DATA, "derived", "v2_sector_map_full.parquet")
    if os.path.exists(path):
        return pd.read_parquet(path)
    from equity_vix import normalize_root
    px = pd.read_parquet(os.path.join(DATA, "stocks", "ohlcv.parquet"), columns=["date", "act_symbol", "close"])
    px["date"] = pd.to_datetime(px["date"]); px["close"] = px["close"].astype("float64")
    px["root"] = normalize_root(px["act_symbol"].astype(str))
    px = px[px["date"] >= "2012-01-01"].drop_duplicates(["root", "date"])
    ret = px.pivot(index="date", columns="root", values="close").pct_change(fill_method=None)
    ret = ret.where(ret.abs() <= 0.4)
    rows = []
    stocks = U[~U["is_etf"].astype(bool)]
    for F, g in stocks.groupby("F"):
        h = ret[ret.index < F].tail(252)
        etfs = [x for x in SECTOR_ETFS if x in h.columns and h[x].notna().sum() > 150]
        names = [r for r in g["root"].unique() if r in h.columns]
        if not etfs or not names:
            continue
        A, Bm = h[names], h[etfs]
        A = (A - A.mean()) / A.std(); Bm = (Bm - Bm.mean()) / Bm.std()
        C = A.fillna(0).T.values @ Bm.fillna(0).values / (
            A.notna().T.values.astype(float) @ Bm.notna().values.astype(float)).clip(min=1)
        C = np.where(np.isfinite(C), C, -9)
        best = np.array(etfs)[np.argmax(C, axis=1)]
        valid = A.notna().sum().values > 150
        rows.append(pd.DataFrame({"F": F, "root": np.array(names)[valid], "sector": best[valid]}))
    m = pd.concat(rows, ignore_index=True)
    m.to_parquet(path, index=False)
    return m


def _cut(df):
    return df[df["X"] <= pd.Timestamp("2023-12-31")] if HIDE_FWD else df


# ----------------------------------------------------------------------------------------------- Phase B
def run_phase_B(bk, U):
    rows, series = [], {}
    d0 = rank_in(U, "LOU")
    dB = rank_in(U, "LOU_B")
    full = U[~U["is_etf"].astype(bool) & U["S0"].notna()].copy()
    full["pct_full"] = full.groupby("X")["S0"].rank(pct=True)
    contrast = full[full["LOU"]]
    smap = sector_map(U)
    key = ["F", "X", "root"]
    for pol in HEDGES:
        for lv in LEVELS:
            uf = _cut(bk.get("STR_F", STRADDLE("FRONT"), lv, pol))
            ub = _cut(bk.get("STR_B", STRADDLE("BACK"), lv, pol))
            m = d0.merge(uf, on=key)
            mb = dB.merge(ub, on=key)
            top = m[m["pct"] >= 0.9]
            fam = {"B1a_top10_long": ew_long(top), "B1b_top20_long": ew_long(m[m["pct"] >= 0.8]),
                   "B1c_top10_long_BACK": ew_long(mb[mb["pct"] >= 0.9]), "B1_LOUavg_long": ew_long(m)}
            cm = contrast.merge(uf, on=key)
            fam["B1x_contrast_rankP_keepLOU_top10"] = ew_long(cm[cm["pct_full"] >= 0.9])
            for etf in ("SPY", "IWM"):
                h = uf[uf["root"] == etf]
                for sz in ("vega", "gamma", "premium", "eqrisk"):
                    fam[f"B2_{etf}_{sz}"] = hedged(top, h, sz)
            # B3: each long name hedged with its own sector ETF straddle
            et = uf[uf["root"].isin(SECTOR_ETFS)].rename(columns={"root": "sector"})
            st = top.merge(smap, on=["F", "root"]).merge(et, on=["X", "sector"], suffixes=("", "_e"))
            st = st.dropna(subset=["L_tot", "S_tot_e"])
            w = 1 / st["prem_L"]
            for sz in ("vega", "gamma", "premium", "eqrisk"):
                q = {"vega": st["vega"] * w / st["vega_e"], "gamma": st["dgamma"] * w / st["dgamma_e"],
                     "premium": 1 / st["prem_e"], "eqrisk": 0.5 / st["prem_e"]}[sz]
                a = agg(st, "L", w)
                se = st[["X"] + [f"S_{c}_e" for c in COMP]].rename(columns={f"S_{c}_e": f"S_{c}" for c in COMP})
                b = agg(se, "S", q)
                n = st.groupby("X").size()
                fam[f"B3_sector_{sz}"] = a.add(b, fill_value=0).div(n, axis=0).assign(n=n)
            fam["B4_LOUavg_vega"] = hedged(top, m, "vega")
            fam["B5a_Q5_vs_Q4"] = hedged(m[m["pct"] > 0.8], m[(m["pct"] > 0.6) & (m["pct"] <= 0.8)], "vega")
            fam["B5b_Q5_vs_Q3"] = hedged(m[m["pct"] > 0.8], m[(m["pct"] > 0.4) & (m["pct"] <= 0.6)], "vega")
            fam["B5c_D10_vs_D5D6"] = hedged(top, m[(m["pct"] > 0.4) & (m["pct"] <= 0.6)], "vega")
            fam["B5d_top5_vs_LOUavg"] = hedged(m[m["pct"] >= 0.95], m, "vega")
            for k, df in fam.items():
                if df is not None and len(df):
                    record(rows, series, k, pol, lv, df)
    return pd.DataFrame(rows), series


# ----------------------------------------------------------------------------------------------- Phase C
def run_phase_C(bk, U):
    rows, series = [], {}
    d = U[U["LOU_B"] & U["S0"].notna() & U["S0p2"].notna()].copy()
    d["CS"] = d["S0"] - d["S0p2"]
    d["pct"] = d.groupby("X")["CS"].rank(pct=True)
    L = bk.L
    key = ["F", "X", "root"]
    vF = L[(L["exp"] == "FRONT") & L["tag"].isin(["ATM_C", "ATM_P"])].groupby(key)["vega"].sum()
    vB = L[(L["exp"] == "BACK") & L["tag"].isin(["ATMF_C", "ATMF_P"])].groupby(key)["vega"].sum()
    vS = L[(L["exp"] == "BACK") & L["tag"].isin(["C25", "P25"])].groupby(key)["vega"].sum()
    ratio = pd.DataFrame({"rB": vF / vB, "rS": vF / vS, "one": 1.0}).replace([np.inf, -np.inf], np.nan).reset_index()
    specs = {"CAL": STRADDLE("FRONT") + [("BACK", "ATMF_C", -1.0, "rB"), ("BACK", "ATMF_P", -1.0, "rB")],
             "CAL11": STRADDLE("FRONT") + [("BACK", "ATMF_C", -1.0, "one"), ("BACK", "ATMF_P", -1.0, "one")],
             "DIAG": STRADDLE("FRONT") + [("BACK", "C25", -1.0, "rS"), ("BACK", "P25", -1.0, "rS")]}
    for pol in ("H0", "H1", "H2"):
        for lv in LEVELS:
            fam = {}
            for nm, spec in specs.items():
                u = _cut(bk.get(nm, spec, lv, pol, ratio=ratio))
                m = d.merge(u, on=key)
                top, bot = m[m["pct"] >= 0.9], m[m["pct"] <= 0.1]
                c1 = ew_long(top, "L", "prem_L")                       # long FRONT, short BACK
                c2 = ew_long(bot, "S", "prem_S")                       # long BACK, short FRONT
                both = pd.concat([c1[list(COMP)], c2[list(COMP)]], axis=1, keys=["a", "b"])
                c3 = both["a"].add(both["b"], fill_value=np.nan).div(2)
                c3 = c3.where(both["a"].notna() & both["b"].notna()).dropna(how="all")
                c3["n"] = c1["n"].reindex(c3.index).fillna(0) + c2["n"].reindex(c3.index).fillna(0)
                if nm == "CAL":
                    fam["C1_reverse_calendar_top10"], fam["C2_calendar_bottom10"], fam["C3_combined"] = c1, c2, c3
                elif nm == "CAL11":
                    fam["C4_1to1_combined"] = c3
                else:
                    fam["C5_diagonal_combined"] = c3
            for k, df in fam.items():
                if len(df):
                    record(rows, series, k, pol, lv, df)
    return pd.DataFrame(rows), series


# ----------------------------------------------------------------------------------------------- Phase D
def sector_scores(U, smap):
    full = U[~U["is_etf"].astype(bool) & U["S0"].notna()].copy()
    full["pct_full"] = full.groupby("X")["S0"].rank(pct=True)
    f = full.merge(smap, on=["F", "root"])
    f["w_adv"] = f["adv20"].fillna(0)
    ssec = f.groupby(["X", "sector"]).apply(lambda g: pd.Series({
        "S_ew": g["pct_full"].mean(),
        "S_adv": np.average(g["pct_full"], weights=g["w_adv"]) if g["w_adv"].sum() > 0 else np.nan,
        "n": len(g)})).reset_index()
    smkt = full.groupby("X")["S0"].mean()
    return ssec, smkt


def run_phase_D(bk, U):
    rows, series = [], {}
    smap = sector_map(U)
    ssec, smkt = sector_scores(U, smap)
    thr = smkt[(smkt.index >= WIN["DISC"][0]) & (smkt.index <= WIN["DISC"][1])].quantile(2 / 3)
    for pol in HEDGES:
        for lv in LEVELS:
            uf = _cut(bk.get("STR_F", STRADDLE("FRONT"), lv, pol))
            et = uf[uf["root"].isin(SECTOR_ETFS)].rename(columns={"root": "sector"}).dropna(subset=["L_tot"])
            fam = {}
            for wname in ("S_ew", "S_adv"):
                m = ssec.merge(et, on=["X", "sector"]).dropna(subset=[wname])
                m = m[m["n"] >= 5]
                m["rk"] = m.groupby("X")[wname].rank(ascending=False, method="first")
                m["nk"] = m.groupby("X")[wname].transform("size")
                m = m[m["nk"] >= 6]
                t1, b1 = m[m["rk"] == 1], m[m["rk"] == m["nk"]]
                fam[f"D1_LS_{wname}"] = hedged(t1, b1, "vega")
                fam[f"D1_L_top1_{wname}"] = ew_long(t1)
                fam[f"D1_2v2_{wname}"] = hedged(m[m["rk"] <= 2], m[m["rk"] > m["nk"] - 2], "vega")
                # D2: per-month OLS slope of ETF straddle L return (per $ premium) on centred S_sec rank
                m["rr"] = m.groupby("X")[wname].rank(pct=True) - 0.5
                m["r"] = m["L_tot"] / m["prem_L"]
                sl = m.groupby("X").apply(lambda g: np.polyfit(g["rr"], g["r"], 1)[0] if len(g) >= 6 else np.nan)
                fam[f"D2_slope_{wname}"] = pd.DataFrame({"tot": sl, "n": m.groupby("X").size()})
            spy = uf[uf["root"] == "SPY"].dropna(subset=["L_tot"])
            alw = ew_long(spy)
            on = smkt.reindex(alw.index) >= thr
            tim = alw.copy()
            tim.loc[~on, list(COMP)] = 0.0
            tim.loc[~on, "n"] = 0
            fam["D3_SPY_timing_long"], fam["D3_SPY_always_long"] = tim, alw
            for k, df in fam.items():
                if len(df):
                    record(rows, series, k, pol, lv, df)
    return pd.DataFrame(rows), series


# ----------------------------------------------------------------------------------------------- Phase E
E_FEATS = ["pct", "FRONT_atm_rel_spread", "lspot", "ladv", "ivhv", "term_slope", "FRONT_skew25", "liv"]


def run_phase_E(bk, U):
    """Walk-forward (refit each January, burn-in 2014-16) prediction of the long FRONT ATM straddle H1 return at
    C50 net (per $ premium). Trade iff predicted net return > k x est. C50 round-trip spread cost (half_spread/prem)."""
    rows, series = [], {}
    d = rank_in(U, "LOU")
    net = _cut(bk.get("STR_F", STRADDLE("FRONT"), "C50", "H1"))
    key = ["F", "X", "root"]
    m = d.merge(net[key + ["prem_L", "half_spread"] + [f"L_{c}" for c in COMP]], on=key)
    m = m.dropna(subset=["L_tot"])
    m["y"] = m["L_tot"] / m["prem_L"]
    m["est_cost"] = m["half_spread"] / m["prem_L"]
    m["year"] = m["X"].dt.year
    m["s_dec"] = np.ceil(m["pct"] * 10).clip(1, 10)
    m["liq_terc"] = m.groupby("X")["FRONT_atm_rel_spread"].transform(
        lambda x: pd.qcut(x.rank(method="first"), 3, labels=False))
    m["lspot"] = np.log(m["spot_F"]); m["ladv"] = np.log(m["adv20"].clip(lower=1)); m["liv"] = np.log(m["FRONT_atm_iv"])
    m["ivhv"] = m["FRONT_atm_iv"] / m["hv21"]
    for c in E_FEATS:
        m[c + "_z"] = m.groupby("X")[c].transform(lambda x: (x - x.mean()) / x.std())
    m["pct_x_spread"] = m["pct_z"] * m["FRONT_atm_rel_spread_z"]
    m["pct_x_liv"] = m["pct_z"] * m["liv_z"]
    Xc = [c + "_z" for c in E_FEATS] + ["pct_x_spread", "pct_x_liv"]
    m = m.replace([np.inf, -np.inf], np.nan).dropna(subset=Xc + ["y", "est_cost"])
    preds = {"E1": pd.Series(np.nan, index=m.index), "E2": pd.Series(np.nan, index=m.index)}

    def ridge(tr):
        A1 = np.column_stack([np.ones(len(tr)), tr[Xc].values])
        lo, hi = np.nanquantile(tr["y"].values, [0.01, 0.99])
        lam = 10.0 * np.eye(A1.shape[1]); lam[0, 0] = 0
        return np.linalg.solve(A1.T @ A1 + lam, A1.T @ np.clip(tr["y"].values, lo, hi))

    for yr in range(2017, 2024):
        tr, te = m[m["year"] < yr], m[m["year"] == yr]
        if te.empty:
            continue
        lo, hi = np.nanquantile(tr["y"].values, [0.01, 0.99])
        cell = tr.assign(yc=tr["y"].clip(lo, hi)).groupby(["s_dec", "liq_terc"])["yc"].mean()
        preds["E1"].loc[te.index] = [cell.get((a, b), np.nan) for a, b in zip(te["s_dec"], te["liq_terc"])]
        preds["E2"].loc[te.index] = np.column_stack([np.ones(len(te)), te[Xc].values]) @ ridge(tr)
    months = sorted(m.loc[m["X"] >= "2017-01-01", "X"].unique())
    for model, pr in preds.items():
        m[f"pred_{model}"] = pr
        for k in (1.0, 1.5, 2.0, 3.0):
            take = m[(m[f"pred_{model}"] > k * m["est_cost"]) & (m["X"] >= "2017-01-01")]
            df = ew_long(take).reindex(months)
            df["n"] = df["n"].fillna(0)
            df[list(COMP)] = df[list(COMP)].fillna(0.0)        # flat months earn 0 (cash at rf = excess 0)
            fam = f"{model}_k{k}"
            record(rows, series, fam, "H1", "C50", df)
            rows[-1]["trades_per_month"] = float(df["n"].mean())
            rows[-1]["months_flat_share"] = float((df["n"] == 0).mean())
    # pre-registered k selection: best DISC OOS (2017-2020) mean per model
    tab = pd.DataFrame(rows)
    tr = m[m["X"] <= "2020-12-31"]
    coefs = dict(zip(["const"] + Xc, np.round(ridge(tr), 5)))
    return tab, series, coefs


def phase_E_verdicts(tab):
    out = []
    for model in ("E1", "E2"):
        g = tab[tab["family"].str.startswith(model)]
        best = g.loc[g["DISC_mean"].idxmax()]
        st = {"DISC": {"mean": best["DISC_mean"], "t": best["DISC_t"]}, "VAL": {"mean": best["VAL_mean"], "t": best["VAL_t"]}}
        out.append({"family": best["family"], "hedge": "H1", "verdict": verdict(st), "DISC_C50_mean": best["DISC_mean"],
                    "DISC_C50_t": best["DISC_t"], "VAL_C50_mean": best["VAL_mean"], "VAL_C50_t": best["VAL_t"],
                    "trades_per_month": best["trades_per_month"], "months_flat_share": best["months_flat_share"],
                    "note": "DISC window = 2017-2020 OOS predictions only"})
    return pd.DataFrame(out)


# ----------------------------------------------------------------------------------------------- driver
def save(name, tab, series, extra=None):
    d = os.path.join(OUT, name)
    os.makedirs(d, exist_ok=True)
    tab.to_csv(os.path.join(d, "grid.csv"), index=False)
    ser = []
    for (fam, pol, lv), df in series.items():
        x = df.copy(); x["family"], x["hedge"], x["cost"] = fam, pol, lv
        ser.append(x.reset_index().rename(columns={"index": "X"}))
    pd.concat(ser, ignore_index=True).to_csv(os.path.join(d, "monthly.csv"), index=False)
    if extra is not None:
        json.dump(extra, open(os.path.join(d, "extra.json"), "w"), indent=1, default=float)


def main(phases="BCDE"):
    U = v2_universe.load()
    U = _cut(U)
    keys = U[U["LOU_loose"] | U["is_etf"].astype(bool)]
    L = load_legs(keys)
    R = load_roots()
    bk = Book(L, R)
    summary = {}
    if "B" in phases:
        tab, ser = run_phase_B(bk, U)
        v = family_verdicts(tab)
        save("phaseB", tab, ser, {"drops": {k: bk.drops(k) for k in ("STR_F", "STR_B")}})
        v.to_csv(os.path.join(OUT, "phaseB", "verdicts.csv"), index=False)
        summary["B"] = v
        print(v.to_string(), flush=True)
    if "C" in phases:
        tab, ser = run_phase_C(bk, U)
        v = family_verdicts(tab)
        save("phaseC", tab, ser, {"drops": {k: bk.drops(k) for k in ("CAL", "CAL11", "DIAG")}})
        v.to_csv(os.path.join(OUT, "phaseC", "verdicts.csv"), index=False)
        summary["C"] = v
        print(v.to_string(), flush=True)
    if "D" in phases:
        tab, ser = run_phase_D(bk, U)
        v = family_verdicts(tab)
        save("phaseD", tab, ser)
        v.to_csv(os.path.join(OUT, "phaseD", "verdicts.csv"), index=False)
        summary["D"] = v
        print(v.to_string(), flush=True)
    if "E" in phases:
        tab, ser, coefs = run_phase_E(bk, U)
        v = phase_E_verdicts(tab)
        save("phaseE", tab, ser, {"ridge_coefs_DISC": coefs})
        v.to_csv(os.path.join(OUT, "phaseE", "verdicts.csv"), index=False)
        summary["E"] = v
        print(v.to_string(), flush=True)
    return summary


if __name__ == "__main__":
    main(*(sys.argv[1:2] or []))
