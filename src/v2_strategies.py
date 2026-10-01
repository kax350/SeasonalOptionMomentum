"""RETAIL V2 — Phases B, C, D, E on the V2 leg table (RETAIL_V2_CHARTER.md §6).

Unit conventions
  * A "position" is a set of legs on one underlying with signed contract quantities (fractional in research
    mode; integer only in Phase F).
  * Per-contract option P&L at cost level e (both entry and exit pay e*half-spread) minus $0.70/contract/side;
    a long leg whose exit bid is 0 is abandoned (no exit commission).
  * Hedge P&L (H1 entry-only, H2 daily) is linear in legs -> signed sum of per-leg hedge P&L; hedge costs =
    2 bps * turnover + $0.005/share (turnover/spot), summed over legs (conservative for offsetting legs).
  * Returns: total P&L / gross LONG premium at mid (B1-B5, C, D) — the capital a retail account pays out.
"""
import os, sys, glob, json
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(__file__))
from paper_core import newey_west_t

DATA = os.environ.get("SOM_DATA", "/home/user/data")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "results", "v2")
COMM = 0.70
E = {"MID": 0.0, "C25": 0.25, "C50": 0.5, "C100": 1.0}
WIN = {"DISC": ("2014-01-01", "2020-12-31"), "VAL": ("2021-01-01", "2023-12-31"), "FWD": ("2024-01-01", "2026-12-31")}
SECTOR_ETFS = ["XLB", "XLE", "XLF", "XLI", "XLK", "XLP", "XLU", "XLV", "XLY", "XLRE", "XLC"]


# ----------------------------------------------------------------------------------------------- loading
def load_legs():
    L = pd.concat([pd.read_parquet(f) for f in sorted(glob.glob(os.path.join(DATA, "v2", "legs", "*.parquet")))],
                  ignore_index=True)
    L["mid"] = (L["bid"] + L["ask"]) / 2
    L["x_mid"] = (L["x_bid"] + L["x_ask"]) / 2
    return L


def leg_pnl(L, e, spread_mult=1.0, comm=COMM):
    """Per-contract P&L for a LONG (+1) and a SHORT (-1) contract of each leg at cost e, before hedging."""
    hs_in = (L["ask"] - L["bid"]) / 2 * spread_mult
    hs_out = (L["x_ask"] - L["x_bid"]) / 2 * spread_mult
    buy_in = L["mid"] + e * hs_in
    sell_in = L["mid"] - e * hs_in
    sell_out = (L["x_mid"] - e * hs_out).clip(lower=0)
    buy_out = L["x_mid"] + e * hs_out
    abandon = L["x_bid"] <= 0
    long_ = 100 * (sell_out - buy_in) - comm - np.where(abandon, 0.0, comm)
    short_ = 100 * (sell_in - buy_out) - 2 * comm
    return long_, short_


def hedge_net(L, pol, stk_mult=1.0):
    """Per-contract hedge P&L net of costs for a LONG contract (negate for short)."""
    if pol == "H0":
        return pd.Series(0.0, index=L.index), pd.Series(0.0, index=L.index)
    pnl = L["h1_pnl"] if pol == "H1" else L["h2_pnl"]
    turn = L["h1_turn"] if pol == "H1" else L["h2_turn"]
    spot = (L["strike"]).clip(lower=1)  # approx spot for share count (ATM-ish); conservative for OTM puts
    cost = stk_mult * (0.0002 * turn + 0.005 * turn / spot)
    return pnl, cost


# ----------------------------------------------------------------------------------------------- structures
def unit_table(L, exp, tags, e, pol, spread_mult=1.0, comm=COMM, stk_mult=1.0):
    """Long-one-unit and short-one-unit P&L per (F, X, root) for a structure made of `tags` (1 contract each)
    on expiry `exp`. Also returns mid premium, vega, dollar gamma, delta of one long unit."""
    sub = L[(L["exp"] == exp) & L["tag"].isin(tags)].copy()
    if sub.empty:
        return pd.DataFrame()
    lp, sp = leg_pnl(sub, E[e] if isinstance(e, str) else e, spread_mult, comm)
    hp, hc = hedge_net(sub, pol, stk_mult)
    sub["long_pnl"] = lp + hp - hc
    sub["short_pnl"] = sp - hp - hc
    sub["opt_long"], sub["hedge_long"], sub["hcost"] = lp, hp, hc
    sub["prem"] = 100 * sub["mid"]
    sub["v"] = 100 * sub["vega"]
    sub["dg"] = 100 * sub["gamma"] * sub["strike"] ** 2 / 100.0
    sub["hs_cost"] = 100 * (sub["ask"] - sub["bid"]) / 2
    g = sub.groupby(["F", "X", "root"])
    u = g.agg(n=("tag", "nunique"), long_pnl=("long_pnl", "sum"), short_pnl=("short_pnl", "sum"),
              opt_long=("opt_long", "sum"), hedge_long=("hedge_long", "sum"), hcost=("hcost", "sum"),
              prem=("prem", "sum"), vega=("v", "sum"), dgamma=("dg", "sum"), half_spread=("hs_cost", "sum"),
              x_missing=("x_missing", "sum"))
    u = u[u["n"] == len(set(tags))].reset_index()
    return u


# ----------------------------------------------------------------------------------------------- signals / universe
def load_signals():
    p = pd.read_parquet(os.path.join(DATA, "derived", "v2_phaseA_panel.parquet"),
                        columns=["root", "F", "X", "S0", "S1", "S0p2", "NonQ", "LOU", "LOU_tight", "LOU_loose",
                                 "FRONT_atm_rel_spread", "BACK_atm_rel_spread", "FRONT_atm_iv", "BACK_atm_iv",
                                 "term_slope", "FRONT_skew25", "adv20", "hv21", "spot_F", "beta"])
    return p


def lou_rank(df, sig, flag="LOU"):
    d = df[df[flag].fillna(False) & df[sig].notna()].copy()
    d["pct"] = d.groupby("X")[sig].rank(pct=True)
    return d


def stats(s):
    s = pd.Series(s).dropna()
    out = {}
    for w, (a, b) in WIN.items():
        x = s[(s.index >= a) & (s.index <= b)]
        if len(x) >= 3:
            out[w] = {"n": int(len(x)), "mean": float(x.mean()), "median": float(x.median()),
                      "t": float(newey_west_t(x)), "sharpe": float(x.mean() / x.std(ddof=1) * np.sqrt(12)) if x.std() > 0 else np.nan,
                      "hit": float((x > 0).mean())}
    return out


def verdict(st):
    d, v = st.get("DISC", {}), st.get("VAL", {})
    if not d or not v:
        return "FAIL"
    if d["mean"] > 0 and d["t"] > 2 and v["mean"] > 0:
        return "PASS"
    if d["mean"] > 0 and d["t"] > 1 and v["mean"] > 0:
        return "WEAK"
    return "FAIL"


# ----------------------------------------------------------------------------------------------- Phase B
HIDE_FWD = True   # FORWARD (2024+) is not computed before a candidate is frozen (charter §2, §6F)


def _cut(df):
    return df[df["X"] <= pd.Timestamp("2023-12-31")] if HIDE_FWD else df


def straddle_units(L, exp, e, pol, **kw):
    return unit_table(L, exp, ["ATM_C", "ATM_P"], e, pol, **kw)


def sector_map(sig_df):
    """Point-in-time sector proxy: SPDR sector ETF with the highest 252-day daily-return correlation."""
    path = os.path.join(DATA, "derived", "v2_sector_map.parquet")
    if os.path.exists(path):
        return pd.read_parquet(path)
    from equity_vix import normalize_root
    px = pd.read_parquet(os.path.join(DATA, "stocks", "ohlcv.parquet"), columns=["date", "act_symbol", "close"])
    px["date"] = pd.to_datetime(px["date"]); px["close"] = px["close"].astype("float64")
    px["root"] = normalize_root(px["act_symbol"].astype(str))
    px = px[px["date"] >= "2012-06-01"].drop_duplicates(["root", "date"])
    ret = px.pivot(index="date", columns="root", values="close").pct_change(fill_method=None)
    rows = []
    for F, g in sig_df.groupby("F"):
        h = ret[ret.index < F].tail(252)
        etfs = [x for x in SECTOR_ETFS if x in h.columns and h[x].notna().sum() > 150]
        names = [r for r in g["root"].unique() if r in h.columns]
        if not etfs or not names:
            continue
        A = h[names]; B = h[etfs]
        A = (A - A.mean()) / A.std(); B = (B - B.mean()) / B.std()
        C = A.fillna(0).T.values @ B.fillna(0).values / (A.notna().T.values.astype(float) @ B.notna().values.astype(float)).clip(min=1)
        best = np.array(etfs)[np.nanargmax(C, axis=1)]
        valid = A.notna().sum().values > 150
        rows.append(pd.DataFrame({"F": F, "root": np.array(names)[valid], "sector": best[valid]}))
    m = pd.concat(rows, ignore_index=True)
    m.to_parquet(path, index=False)
    return m


def run_phase_B(L, sig):
    rows, series = [], {}
    d0 = lou_rank(sig, "S0")
    full = sig[sig["S0"].notna()].copy(); full["pct_full"] = full.groupby("X")["S0"].rank(pct=True)
    contrast = full[full["LOU"].fillna(False)]
    smap = sector_map(sig[sig["LOU"].fillna(False)])
    for pol in ("H0", "H1", "H2"):
        for e in ("MID", "C25", "C50", "C100"):
            uf = _cut(straddle_units(L, "FRONT", e, pol)); ub = _cut(straddle_units(L, "BACK", e, pol))
            uf["r_long"] = uf["long_pnl"] / uf["prem"]
            ub["r_long"] = ub["long_pnl"] / ub["prem"]
            m = d0.merge(uf, on=["F", "X", "root"])
            mb = d0.merge(ub, on=["F", "X", "root"])
            fam = {}
            fam["B1a_top10_long"] = m[m["pct"] >= 0.9].groupby("X")["r_long"].mean()
            fam["B1b_top20_long"] = m[m["pct"] >= 0.8].groupby("X")["r_long"].mean()
            fam["B1c_top10_long_BACK"] = mb[mb["pct"] >= 0.9].groupby("X")["r_long"].mean()
            fam["B1_LOUavg_long"] = m.groupby("X")["r_long"].mean()
            cm = contrast.merge(uf, on=["F", "X", "root"])
            fam["B1x_contrast_rankP_keepLOU_top10"] = cm[cm["pct_full"] >= 0.9].groupby("X")["r_long"].mean()
            top = m[m["pct"] >= 0.9].copy()
            top["w"] = 1 / top["prem"]
            agg = top.groupby("X").apply(lambda g: pd.Series({"N": len(g), "P": (g["long_pnl"] * g["w"]).sum(),
                                                               "V": (g["vega"] * g["w"]).sum(), "D": (g["dgamma"] * g["w"]).sum()}))
            # B2 index hedge (SPY / IWM), 4 sizings
            for etf in ("SPY", "IWM"):
                h = uf[uf["root"] == etf].set_index("X")
                j = agg.join(h[["short_pnl", "vega", "dgamma", "prem"]], how="inner", rsuffix="_h")
                for sz, q in (("vega", j["V"] / j["vega"]), ("gamma", j["D"] / j["dgamma"]),
                              ("premium", j["N"] / j["prem"]), ("eqrisk", 0.5 * j["N"] / j["prem"])):
                    fam[f"B2_{etf}_{sz}"] = (j["P"] + q * j["short_pnl"]) / j["N"]
            # B3 sector hedge (per-name sector ETF straddle), 4 sizings
            st = top.merge(smap, on=["F", "root"]).merge(
                uf[uf["root"].isin(SECTOR_ETFS)][["X", "root", "short_pnl", "vega", "dgamma", "prem"]].rename(
                    columns={"root": "sector", "short_pnl": "s_short", "vega": "s_vega", "dgamma": "s_dg", "prem": "s_prem"}),
                on=["X", "sector"])
            for sz, q in (("vega", st["vega"] * st["w"] / st["s_vega"]), ("gamma", st["dgamma"] * st["w"] / st["s_dg"]),
                          ("premium", 1 / st["s_prem"]), ("eqrisk", 0.5 / st["s_prem"])):
                fam[f"B3_sector_{sz}"] = (st["long_pnl"] * st["w"] + q * st["s_short"]).groupby(st["X"]).mean()
            # B4 universe hedge: short EW LOU straddles, vega-neutral
            allm = m.assign(w=1 / m["prem"]).groupby("X").apply(lambda g: pd.Series({
                "Ps": (g["short_pnl"] * g["w"]).sum(), "Vs": (g["vega"] * g["w"]).sum()}))
            j = agg.join(allm, how="inner")
            fam["B4_LOUavg_vega"] = (j["P"] + j["V"] / j["Vs"] * j["Ps"]) / j["N"]
            # B5 single-name relative, vega-neutral, both legs in LOU
            def rel(lo_hi, sh_lo, sh_hi):
                L_ = m[(m["pct"] >= lo_hi)]; S_ = m[(m["pct"] >= sh_lo) & (m["pct"] < sh_hi)]
                a = L_.assign(w=1 / L_["prem"]).groupby("X").apply(lambda g: pd.Series({"N": len(g), "P": (g["long_pnl"] * g["w"]).sum(), "V": (g["vega"] * g["w"]).sum()}))
                b = S_.assign(w=1 / S_["prem"]).groupby("X").apply(lambda g: pd.Series({"Ps": (g["short_pnl"] * g["w"]).sum(), "Vs": (g["vega"] * g["w"]).sum()}))
                j = a.join(b, how="inner")
                return (j["P"] + j["V"] / j["Vs"] * j["Ps"]) / j["N"]
            fam["B5a_Q5_vs_Q4"] = rel(0.8, 0.6, 0.8)
            fam["B5b_Q5_vs_Q3"] = rel(0.8, 0.4, 0.6)
            fam["B5c_D10_vs_D5D6"] = rel(0.9, 0.4, 0.6)
            fam["B5d_top5_vs_LOUavg"] = rel(0.95, 0.0, 1.01)
            for k, s in fam.items():
                st_ = stats(s)
                series[(k, pol, e)] = s
                rows.append({"family": k, "hedge": pol, "cost": e, **{f"{w}_{kk}": vv for w, x in st_.items() for kk, vv in x.items()}})
    return pd.DataFrame(rows), series


# ----------------------------------------------------------------------------------------------- Phase C
def run_phase_C(L, sig):
    rows, series = [], {}
    d = sig[sig["LOU"].fillna(False) & sig["S0"].notna() & sig["S0p2"].notna()].copy()
    d["CS"] = d["S0"] - d["S0p2"]
    d["pct"] = d.groupby("X")["CS"].rank(pct=True)
    for pol in ("H0", "H1", "H2"):
        for e in ("MID", "C25", "C50", "C100"):
            uf = _cut(straddle_units(L, "FRONT", e, pol)).set_index(["F", "X", "root"])
            ub = _cut(straddle_units(L, "BACK", e, pol)).set_index(["F", "X", "root"])
            us = _cut(unit_table(L, "BACK", ["C25", "P25"], e, pol)).set_index(["F", "X", "root"])
            j = uf.join(ub, lsuffix="_f", rsuffix="_b", how="inner").join(us[["long_pnl", "short_pnl", "vega", "prem"]].rename(
                columns=lambda c: c + "_s"), how="left").reset_index()
            m = d.merge(j, on=["F", "X", "root"])
            fam = {}
            top, bot = m[m["pct"] >= 0.9], m[m["pct"] <= 0.1]
            # C1 reverse calendar: long FRONT, short BACK (vega-neutral) ; C2 calendar: long BACK, short FRONT
            c1 = (top["long_pnl_f"] + top["vega_f"] / top["vega_b"] * top["short_pnl_b"]) / top["prem_f"]
            c2 = (bot["long_pnl_b"] + bot["vega_b"] / bot["vega_f"] * bot["short_pnl_f"]) / bot["prem_b"]
            fam["C1_reverse_calendar_top10"] = c1.groupby(top["X"]).mean()
            fam["C2_calendar_bottom10"] = c2.groupby(bot["X"]).mean()
            fam["C3_combined"] = pd.concat([fam["C1_reverse_calendar_top10"], fam["C2_calendar_bottom10"]], axis=1).mean(axis=1)
            c1n = (top["long_pnl_f"] + top["short_pnl_b"]) / top["prem_f"]
            c2n = (bot["long_pnl_b"] + bot["short_pnl_f"]) / bot["prem_b"]
            fam["C4_1to1"] = pd.concat([c1n.groupby(top["X"]).mean(), c2n.groupby(bot["X"]).mean()], axis=1).mean(axis=1)
            t5 = top.dropna(subset=["vega_s"]); b5 = bot.dropna(subset=["vega_s"])
            c5a = (t5["long_pnl_f"] + t5["vega_f"] / t5["vega_s"] * t5["short_pnl_s"]) / t5["prem_f"]
            c5b = (b5["long_pnl_s"] + b5["vega_s"] / b5["vega_f"] * b5["short_pnl_f"]) / b5["prem_s"]
            fam["C5_diagonal"] = pd.concat([c5a.groupby(t5["X"]).mean(), c5b.groupby(b5["X"]).mean()], axis=1).mean(axis=1)
            for k, s in fam.items():
                st_ = stats(s); series[(k, pol, e)] = s
                rows.append({"family": k, "hedge": pol, "cost": e, **{f"{w}_{kk}": vv for w, x in st_.items() for kk, vv in x.items()}})
    return pd.DataFrame(rows), series


# ----------------------------------------------------------------------------------------------- Phase D
def run_phase_D(L, sig):
    rows, series = [], {}
    full = sig[sig["S0"].notna()].copy()
    full["pct_full"] = full.groupby("X")["S0"].rank(pct=True)
    smap = sector_map(full)
    f = full.merge(smap, on=["F", "root"])
    f["w_adv"] = f["adv20"].fillna(0)
    ssec = f.groupby(["X", "sector"]).apply(lambda g: pd.Series({
        "S_ew": g["pct_full"].mean(), "S_adv": np.average(g["pct_full"], weights=g["w_adv"]) if g["w_adv"].sum() > 0 else np.nan,
        "n": len(g)})).reset_index()
    smkt = full.groupby("X")["S0"].mean()      # level (cross-sectional mean of raw S0)
    thr = smkt[(smkt.index >= WIN["DISC"][0]) & (smkt.index <= WIN["DISC"][1])].quantile(2 / 3)
    for pol in ("H0", "H1", "H2"):
        for e in ("MID", "C25", "C50", "C100"):
            uf = _cut(straddle_units(L, "FRONT", e, pol))
            et = uf[uf["root"].isin(SECTOR_ETFS)].rename(columns={"root": "sector"})
            et["r_long"] = et["long_pnl"] / et["prem"]
            fam = {}
            for wname in ("S_ew", "S_adv"):
                m = ssec.merge(et, on=["X", "sector"]).dropna(subset=[wname])
                m = m[m["n"] >= 5]
                m["rk"] = m.groupby("X")[wname].rank(ascending=False, method="first")
                m["nk"] = m.groupby("X")[wname].transform("size")
                top1, bot1 = m[m["rk"] == 1].set_index("X"), m[m["rk"] == m["nk"]].set_index("X")
                j = top1.join(bot1, lsuffix="_t", rsuffix="_b", how="inner")
                fam[f"D1_LS_{wname}"] = (j["long_pnl_t"] + j["vega_t"] / j["vega_b"] * j["short_pnl_b"]) / j["prem_t"]
                fam[f"D1_L_top1_{wname}"] = top1["r_long"]
                t2, b2 = m[m["rk"] <= 2], m[m["rk"] > m["nk"] - 2]
                a = t2.groupby("X").apply(lambda g: pd.Series({"P": (g["long_pnl"] / g["prem"]).sum(), "V": (g["vega"] / g["prem"]).sum(), "N": len(g)}))
                b = b2.groupby("X").apply(lambda g: pd.Series({"Ps": (g["short_pnl"] / g["prem"]).sum(), "Vs": (g["vega"] / g["prem"]).sum()}))
                jj = a.join(b, how="inner")
                fam[f"D1_2v2_{wname}"] = (jj["P"] + jj["V"] / jj["Vs"] * jj["Ps"]) / jj["N"]
                # D2: FM slope of ETF straddle return on sector-score rank
                m["rr"] = m.groupby("X")[wname].rank(pct=True) - 0.5
                sl = m.groupby("X").apply(lambda g: np.polyfit(g["rr"], g["r_long"], 1)[0] if len(g) >= 5 else np.nan)
                fam[f"D2_slope_{wname}"] = sl
            spy = uf[uf["root"] == "SPY"].set_index("X")
            sig_on = smkt.reindex(spy.index) >= thr
            fam["D3_SPY_timing_long"] = (spy["long_pnl"] / spy["prem"]).where(sig_on, 0.0)
            fam["D3_SPY_always_long"] = spy["long_pnl"] / spy["prem"]
            for k, s in fam.items():
                st_ = stats(s); series[(k, pol, e)] = s
                rows.append({"family": k, "hedge": pol, "cost": e, **{f"{w}_{kk}": vv for w, x in st_.items() for kk, vv in x.items()}})
    return pd.DataFrame(rows), series


# ----------------------------------------------------------------------------------------------- Phase E
def run_phase_E(L, sig):
    rows, series = [], {}
    d = lou_rank(sig, "S0")
    gross = _cut(straddle_units(L, "FRONT", "MID", "H1"))
    net = _cut(straddle_units(L, "FRONT", "C50", "H1"))
    m = d.merge(gross[["F", "X", "root", "long_pnl", "prem", "half_spread"]], on=["F", "X", "root"]).merge(
        net[["F", "X", "root", "long_pnl"]].rename(columns={"long_pnl": "net_pnl"}), on=["F", "X", "root"])
    m["y"] = m["long_pnl"] / m["prem"]                       # gross (MID) H1 return
    m["y_net"] = m["net_pnl"] / m["prem"]                    # realised C50 net return
    m["est_cost"] = (2 * 0.5 * m["half_spread"] + 4 * COMM) / m["prem"]   # ex-ante round-trip C50 cost estimate
    m["year"] = m["X"].dt.year
    m["s_dec"] = np.ceil(m["pct"] * 10).clip(1, 10)
    m["liq_terc"] = m.groupby("X")["FRONT_atm_rel_spread"].transform(lambda x: pd.qcut(x.rank(method="first"), 3, labels=False))
    feats = ["pct", "FRONT_atm_rel_spread", "lspot", "ladv", "ivhv", "term_slope", "FRONT_skew25", "liv"]
    m["lspot"] = np.log(m["spot_F"]); m["ladv"] = np.log(m["adv20"].clip(lower=1)); m["liv"] = np.log(m["FRONT_atm_iv"])
    m["ivhv"] = m["FRONT_atm_iv"] / m["hv21"]
    for c in feats:
        m[c + "_z"] = m.groupby("X")[c].transform(lambda x: (x - x.mean()) / x.std())
    m["pct_x_spread"] = m["pct_z"] * m["FRONT_atm_rel_spread_z"]
    m["pct_x_liv"] = m["pct_z"] * m["liv_z"]
    X_cols = [c + "_z" for c in feats] + ["pct_x_spread", "pct_x_liv"]
    m = m.dropna(subset=X_cols + ["y"])
    preds = {"E1": pd.Series(np.nan, index=m.index), "E2": pd.Series(np.nan, index=m.index)}
    for yr in range(2017, 2024):
        tr, te = m[m["year"] < yr], m[m["year"] == yr]
        if te.empty:
            continue
        cell = tr.groupby(["s_dec", "liq_terc"])["y"].mean()
        preds["E1"].loc[te.index] = [cell.get((a, b), np.nan) for a, b in zip(te["s_dec"], te["liq_terc"])]
        A = tr[X_cols].values; yv = np.clip(tr["y"].values, *np.nanquantile(tr["y"].values, [0.01, 0.99]))
        A1 = np.column_stack([np.ones(len(A)), A])
        lam = 10.0 * np.eye(A1.shape[1]); lam[0, 0] = 0
        beta = np.linalg.solve(A1.T @ A1 + lam, A1.T @ yv)
        preds["E2"].loc[te.index] = np.column_stack([np.ones(len(te)), te[X_cols].values]) @ beta
    for model, pr in preds.items():
        m[f"pred_{model}"] = pr
        for k in (1.0, 1.5, 2.0, 3.0):
            take = (m[f"pred_{model}"] - m["est_cost"]) > k * m["est_cost"]
            s = m[take].groupby("X")["y_net"].mean().reindex(sorted(m["X"].unique())).fillna(0.0)
            s = s[s.index >= "2017-01-01"]
            n_tr = m[take].groupby("X").size().reindex(s.index).fillna(0)
            st_ = stats(s); series[(f"{model}_k{k}", "H1", "C50")] = s
            rows.append({"family": f"{model}_k{k}", "hedge": "H1", "cost": "C50", "trades_per_month": float(n_tr.mean()),
                         "months_flat_share": float((n_tr == 0).mean()),
                         **{f"{w}_{kk}": vv for w, x in st_.items() for kk, vv in x.items()}})
    # feature importance (ridge on full DISC window, standardised)
    tr = m[m["X"] <= "2020-12-31"]
    A1 = np.column_stack([np.ones(len(tr)), tr[X_cols].values]); lam = 10.0 * np.eye(A1.shape[1]); lam[0, 0] = 0
    beta = np.linalg.solve(A1.T @ A1 + lam, A1.T @ np.clip(tr["y"].values, *np.nanquantile(tr["y"].values, [0.01, 0.99])))
    coefs = dict(zip(["const"] + X_cols, beta.round(5)))
    return pd.DataFrame(rows), series, coefs
