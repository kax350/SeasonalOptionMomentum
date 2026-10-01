"""RETAIL V2 — Phase A: liquid universe + signal decomposition (Q1) + mid-artifact tests (Q2).
Charter §6 Phase A. DISCOVERY = holding months 2014-02 … 2020-12 (verdict); 2021-2026 reported only.
"""
import os, sys, json, glob
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(__file__))
from paper_core import month_index, newey_west_t, sas_rank_groups

DATA = os.environ.get("SOM_DATA", "/home/user/data")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "results", "v2", "phaseA")
DISC = ("2014-01-01", "2020-12-31")
LATE = ("2021-01-01", "2026-12-31")
LAGS = {"S0": ((3, 6, 9, 12), 3, "vix_all"), "S1": ((3, 6, 9, 12), 3, "vix_posoi"),
        "NonQ": ((1, 2, 4, 5, 7, 8, 10, 11), 6, "vix_all"), "S0p2": ((2, 5, 8, 11), 3, "vix_all"),
        "Mom": (tuple(range(2, 13)), 8, "vix_all"), "Lag1": ((1,), 1, "vix_all")}


def load_panel():
    s = pd.read_parquet(os.path.join(DATA, "panel", "vix_sort.parquet"))
    h = pd.read_parquet(os.path.join(DATA, "panel", "vix_hold.parquet"))
    s["vix_all"] = s["Dynamic_VIX_Return_Corridor"] - s["rf"]
    h["vix_posoi"] = h["Dynamic_VIX_Return_Corridor"] - h["rf"]
    keep = ["root", "exdate_trade", "vix_posoi", "VIX_Prc", "VIX_Prc_bid", "VIX_Prc_ask", "RV_Corridor",
            "VIX_BA_percent", "St_start", "IV_avg"]
    p = s[["root", "ticker", "date", "exdate_trade", "vix_all"]].merge(h[keep], on=["root", "exdate_trade"], how="left")
    p = p.rename(columns={"exdate_trade": "X", "date": "F"})
    p["m"] = month_index(p["X"])
    for c in p.columns:
        if str(p[c].dtype) in ("Float64", "Int64"):
            p[c] = p[c].astype("float64")
    return p


def add_signals(p):
    for name, (lags, need, var) in LAGS.items():
        base = p.dropna(subset=[var]).drop_duplicates(["root", "m"]).set_index(["root", "m"])[var]
        V = np.vstack([base.reindex(pd.MultiIndex.from_arrays([p["root"].values, (p["m"] - L).values])).values
                       for L in lags]).T
        n = (~np.isnan(V)).sum(1)
        with np.errstate(invalid="ignore"):
            p[name] = np.where(n >= need, np.nanmean(V, axis=1), np.nan)
    return p


def add_v2(p):
    """LOU flags and V2 root features (FRONT/BACK ATM IV, spreads, skew) + DoltHub outcomes."""
    R = pd.concat([pd.read_parquet(f) for f in sorted(glob.glob(os.path.join(DATA, "v2", "roots", "*.parquet")))],
                  ignore_index=True)
    D = pd.read_parquet(os.path.join(DATA, "v2", "root_features_dolthub.parquet"))
    R = R.merge(D, on=["root", "F", "X"], how="left")
    R = R[~R["is_etf"]]
    q = (R["S0"] >= 20) & R["FRONT_atm_bid_ok"].fillna(False) & R["BACK_atm_bid_ok"].fillna(False)
    for name, sp, top in (("LOU", 0.10, 500), ("LOU_tight", 0.05, 250), ("LOU_loose", 0.20, 1000)):
        ok = q & (R["FRONT_atm_rel_spread"] <= sp) & (R["BACK_atm_rel_spread"] <= sp)
        if name == "LOU_loose":
            ok = ((R["S0"] >= 10) & R["FRONT_atm_bid_ok"].fillna(False) & R["BACK_atm_bid_ok"].fillna(False)
                  & (R["FRONT_atm_rel_spread"] <= sp) & (R["BACK_atm_rel_spread"] <= sp))
        rk = R["adv20"].where(ok).groupby(R["F"]).rank(ascending=False)
        R[name] = ok & (rk <= top)
    R["term_slope"] = R["BACK_atm_iv"] - R["FRONT_atm_iv"]
    R = R.sort_values(["root", "F"])
    R["skew_next"] = R.groupby("root")["FRONT_skew25"].shift(-1)
    R["iv_next"] = R.groupby("root")["FRONT_atm_iv"].shift(-1)
    cols = ["root", "F", "X", "LOU", "LOU_tight", "LOU_loose", "S0", "FRONT_atm_iv", "BACK_atm_iv", "FRONT_atm_rel_spread",
            "BACK_atm_rel_spread", "FRONT_skew25", "skew_next", "iv_next", "term_slope", "adv20", "hv21", "hv252", "beta",
            "rv", "rv_idio", "jump_share", "FRONT_atm_min_size"]
    R = R[cols].rename(columns={"S0": "spot_F"})
    return p.merge(R, on=["root", "F", "X"], how="left")


def fm(df, y, xs, by="X", min_n=30):
    rows = []
    for d, g in df.dropna(subset=[y] + xs).groupby(by):
        if len(g) < min_n:
            continue
        X = np.column_stack([np.ones(len(g))] + [g[x].values for x in xs])
        yy = g[y].values
        lo, hi = np.nanquantile(yy, [0.01, 0.99])
        b = np.linalg.lstsq(X, np.clip(yy, lo, hi), rcond=None)[0]
        rows.append([d] + list(b[1:]))
    if not rows:
        return {}
    r = pd.DataFrame(rows, columns=[by] + xs).set_index(by)
    out = {}
    for per, (a, b) in (("disc", DISC), ("late", LATE)):
        z = r[(r.index >= a) & (r.index <= b)]
        out[per] = {x: {"slope": float(z[x].mean()), "t": float(newey_west_t(z[x])), "n": int(len(z))} for x in xs}
    return out


def ranks(df, col, mask=None, by="X"):
    g = df[col].where(mask) if mask is not None else df[col]
    return g.groupby(df[by]).rank(pct=True) - 0.5


def hl_by_bucket(df, sig, ret, bucket, ng=5):
    """Within each month and bucket, re-rank `sig` into ng groups; H-L of `ret`. Returns per-bucket stats."""
    out = {}
    for b, gb in df.dropna(subset=[sig, ret, bucket]).groupby(bucket):
        ser = []
        for d, g in gb.groupby("X"):
            if len(g) < 3 * ng:
                continue
            q = sas_rank_groups(g[sig], ng)
            ser.append((d, g[ret][q == ng].mean() - g[ret][q == 1].mean()))
        s = pd.Series(dict(ser)).sort_index()
        out[str(b)] = {per: {"mean": float(s[(s.index >= a) & (s.index <= bb)].mean()),
                             "t": float(newey_west_t(s[(s.index >= a) & (s.index <= bb)])),
                             "n": int(((s.index >= a) & (s.index <= bb)).sum())}
                       for per, (a, bb) in (("disc", DISC), ("late", LATE))}
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    p = add_signals(load_panel())
    p = add_v2(p)
    # C50 executable returns from the cost audit (paper construction)
    fc = pd.read_parquet(os.path.join(DATA, "derived", "firm_month_costs.parquet"),
                         columns=["id", "date_var", "rL_COST2_e50", "rS_COST2_e50", "rL_COST0_mid"])
    fc = fc.rename(columns={"id": "root", "date_var": "X"})
    p = p.merge(fc, on=["root", "X"], how="left")
    p = p[p["X"] >= "2014-01-01"]
    p["logRVc"] = np.log(p["RV_Corridor"].clip(lower=1e-8))
    p["logIVc"] = np.log(p["VIX_Prc"])
    p["VRP"] = p["logRVc"] - p["logIVc"]
    p["log_rv"] = np.log(p["rv"].clip(lower=1e-8))
    p["log_rv_idio"] = np.log(p["rv_idio"].clip(lower=1e-8))
    p["idio_share"] = p["rv_idio"] / p["rv"]
    p["d_skew"] = p["skew_next"] - p["FRONT_skew25"]
    p["d_iv"] = p["iv_next"] - p["FRONT_atm_iv"]
    p["mid_bias"] = (p["VIX_Prc"] - p["VIX_Prc_bid"]) / p["VIX_Prc"]
    res = {}
    # ---------------- A1 decomposition ----------------
    outcomes = ["vix_posoi", "rL_COST2_e50", "logRVc", "logIVc", "VRP", "log_rv", "log_rv_idio", "idio_share",
                "jump_share", "FRONT_atm_iv", "d_iv", "FRONT_skew25", "d_skew", "VIX_BA_percent", "mid_bias"]
    hold = p["vix_posoi"].notna()
    for uni, mask in (("P", hold), ("LOU", hold & p["LOU"].fillna(False))):
        d = p[mask].copy()
        d["r_S0"] = ranks(d, "S0")
        d["r_Mom"] = ranks(d, "Mom")
        d["r_Lag1"] = ranks(d, "Lag1")
        res[f"A1_{uni}"] = {y: fm(d, y, ["r_S0"]) for y in outcomes}
        res[f"A1_{uni}_controls"] = {y: fm(d, y, ["r_S0", "r_Mom", "r_Lag1"]) for y in ["vix_posoi", "VRP", "log_rv", "log_rv_idio"]}
    # ---------------- A2 mid-artifact ----------------
    d = p[hold].copy()
    d["liq_terc"] = d.groupby("X")["VIX_BA_percent"].transform(lambda x: pd.qcut(x.rank(method="first"), 3, labels=["liq", "mid", "illiq"]))
    res["A2i_double_sort_MID"] = hl_by_bucket(d, "S0", "vix_posoi", "liq_terc")
    res["A2i_double_sort_C50_longleg_Q5minusQ1_longs"] = hl_by_bucket(d, "S0", "rL_COST2_e50", "liq_terc")
    # executable H-L at C50 per tercile: long Q5 at C50 buy, short Q1 at C50 sell
    out = {}
    for b, gb in d.dropna(subset=["S0", "rL_COST2_e50", "rS_COST2_e50"]).groupby("liq_terc"):
        ser = []
        for dd, g in gb.groupby("X"):
            if len(g) < 15:
                continue
            q = sas_rank_groups(g["S0"], 5)
            ser.append((dd, g["rL_COST2_e50"][q == 5].mean() - g["rS_COST2_e50"][q == 1].mean()))
        s = pd.Series(dict(ser)).sort_index()
        out[str(b)] = {per: {"mean": float(s[(s.index >= a) & (s.index <= bb)].mean()),
                             "t": float(newey_west_t(s[(s.index >= a) & (s.index <= bb)]))}
                       for per, (a, bb) in (("disc", DISC), ("late", LATE))}
    res["A2i_double_sort_C50_executable"] = out
    res["A2ii_NonQ_MID"] = hl_by_bucket(d, "NonQ", "vix_posoi", "liq_terc")
    d["r_S0"] = d.groupby(["X", "liq_terc"])["S0"].rank(pct=True) - 0.5
    d["r_NonQ"] = d.groupby(["X", "liq_terc"])["NonQ"].rank(pct=True) - 0.5
    res["A2ii_FM_S0_vs_NonQ_by_tercile"] = {str(b): fm(g, "vix_posoi", ["r_S0", "r_NonQ"], min_n=20)
                                           for b, g in d.groupby("liq_terc")}
    dl = d[d["LOU"].fillna(False)].copy()
    dl["r_S0"] = ranks(dl, "S0"); dl["r_NonQ"] = ranks(dl, "NonQ"); dl["r_S1"] = ranks(dl, "S1")
    res["A2ii_FM_S0_vs_NonQ_LOU"] = fm(dl, "vix_posoi", ["r_S0", "r_NonQ"], min_n=20)
    # quarterly-specific component inside LOU: H-L(S0) - H-L(NonQ), LOU re-ranked (Phase A verdict)
    dl["all"] = "LOU"
    a = hl_by_bucket(dl, "S0", "vix_posoi", "all")["LOU"]
    b = hl_by_bucket(dl, "NonQ", "vix_posoi", "all")["LOU"]
    res["A2ii_LOU_HL_S0_MID"], res["A2ii_LOU_HL_NonQ_MID"] = a, b
    # (iii) S1 vs S0
    res["A2iii_S1_MID_by_tercile"] = hl_by_bucket(d, "S1", "vix_posoi", "liq_terc")
    res["A2iii_LOU_HL_S1_MID"] = hl_by_bucket(dl, "S1", "vix_posoi", "all")["LOU"]
    # (iv) persistence: FM slope of vix_posoi(m) on vix_all(m-L), L=1..12, by tercile
    base = p.dropna(subset=["vix_all"]).drop_duplicates(["root", "m"]).set_index(["root", "m"])["vix_all"]
    pers = {}
    for L in range(1, 13):
        d[f"lag{L}"] = base.reindex(pd.MultiIndex.from_arrays([d["root"].values, (d["m"] - L).values])).values
        d[f"r_lag{L}"] = d.groupby(["X", "liq_terc"])[f"lag{L}"].rank(pct=True) - 0.5
        pers[L] = {str(b): fm(g, "vix_posoi", [f"r_lag{L}"], min_n=20) for b, g in d.groupby("liq_terc")}
    res["A2iv_persistence_by_lag"] = pers
    # descriptive: where do Q1/Q5 names live
    d["q_full"] = d.groupby("X")["S0"].transform(lambda x: sas_rank_groups(x.dropna(), 5).reindex(x.index))
    res["composition"] = {
        "share_in_LOU_by_full_quintile": d.groupby("q_full")["LOU"].mean().round(4).to_dict(),
        "median_front_atm_spread_by_quintile": d.groupby("q_full")["FRONT_atm_rel_spread"].median().round(4).to_dict(),
        "LOU_names_per_month_median": float(p[p["LOU"].fillna(False)].groupby("X").size().median()),
        "LOU_with_S0_per_month_median": float(p[p["LOU"].fillna(False) & p["S0"].notna()].groupby("X").size().median()),
    }
    json.dump(res, open(os.path.join(OUT, "phaseA.json"), "w"), indent=1, default=float)
    p.to_parquet(os.path.join(DATA, "derived", "v2_phaseA_panel.parquet"), index=False)
    print(json.dumps(res["composition"], indent=1))


if __name__ == "__main__":
    main()
