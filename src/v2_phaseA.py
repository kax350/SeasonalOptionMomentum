"""RETAIL V2 — Phase A: signal decomposition (Q1) and mid-artifact tests (Q2). Charter §6 Phase A, ledger row 2.

Universes
  P   = paper panel rows with a holding-sample return (vix_posoi), signals from past returns.
  LOU = V2 liquid option universe at F (FRONT screens), signal re-ranked inside LOU.
Windows: DISC = exit months 2014-02 … 2020-12 (verdict); VAL = 2021-01 … 2023-12 (reported). FORWARD hidden.
Verdict A: NW(3) t of the monthly paired difference [Q5−Q1 of S0] − [Q5−Q1 of NonQ] on vix_posoi inside LOU, DISC.
"""
import os, sys, json
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(__file__))
from paper_core import month_index, newey_west_t, sas_rank_groups
import v2_universe
import v2_strategies as vs

DATA = os.environ.get("SOM_DATA", "/home/user/data")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "results", "v2", "phaseA")
WINS = {"DISC": ("2014-02-01", "2020-12-31"), "VAL": ("2021-01-01", "2023-12-31")}
END = pd.Timestamp("2023-12-31")


def load_panel():
    s = pd.read_parquet(os.path.join(DATA, "panel", "vix_sort.parquet"))
    h = pd.read_parquet(os.path.join(DATA, "panel", "vix_hold.parquet"))
    s["vix_all"] = s["Dynamic_VIX_Return_Corridor"] - s["rf"]
    h["vix_posoi"] = h["Dynamic_VIX_Return_Corridor"] - h["rf"]
    keep = ["root", "exdate_trade", "vix_posoi", "VIX_Prc", "VIX_Prc_bid", "VIX_Prc_ask", "RV_Corridor",
            "VIX_BA_percent", "IV_avg"]
    p = s[["root", "date", "exdate_trade", "vix_all"]].merge(h[keep], on=["root", "exdate_trade"], how="left")
    p = p.rename(columns={"exdate_trade": "X", "date": "F"})
    p["m"] = month_index(p["X"])
    for c in p.columns:
        if str(p[c].dtype) in ("Float64", "Int64"):
            p[c] = p[c].astype("float64")
    base = p.dropna(subset=["vix_all"]).drop_duplicates(["root", "m"]).set_index(["root", "m"])["vix_all"]
    hb = h.assign(m=month_index(h["exdate_trade"]))
    hbase = hb.dropna(subset=["vix_posoi"]).drop_duplicates(["root", "m"]).set_index(["root", "m"])["vix_posoi"].astype("float64")
    for name, (lags, need, src) in v2_universe.LAGS.items():
        b = base if src == "sort" else hbase
        V = np.vstack([b.reindex(pd.MultiIndex.from_arrays([p["root"].values, (p["m"] - L).values])).values
                       for L in lags]).T
        n = (~np.isnan(V)).sum(1)
        with np.errstate(invalid="ignore"):
            p[name] = np.where(n >= need, np.nanmean(V, axis=1), np.nan)
    return p, base


def window_stats(s):
    s = pd.Series(s).dropna().sort_index()
    out = {}
    for w, (a, b) in WINS.items():
        x = s[(s.index >= a) & (s.index <= b)]
        if len(x) >= 3:
            out[w] = {"mean": float(x.mean()), "t": float(newey_west_t(x)), "n": int(len(x))}
    return out


def fm(df, y, xs, min_n=30):
    rows = []
    for d, g in df.dropna(subset=[y] + xs).groupby("X"):
        if len(g) < min_n:
            continue
        A = np.column_stack([np.ones(len(g))] + [g[x].values for x in xs])
        yy = g[y].values
        lo, hi = np.nanquantile(yy, [0.01, 0.99])
        b = np.linalg.lstsq(A, np.clip(yy, lo, hi), rcond=None)[0]
        rows.append([d] + list(b[1:]))
    if not rows:
        return {}
    r = pd.DataFrame(rows, columns=["X"] + xs).set_index("X")
    return {x: window_stats(r[x]) for x in xs}


def crank(df, col, by=("X",)):
    return df.groupby(list(by))[col].rank(pct=True) - 0.5


def hl_series(df, sig, ret, ng=5, min_per_group=3):
    ser = {}
    for d, g in df.dropna(subset=[sig, ret]).groupby("X"):
        if len(g) < min_per_group * ng:
            continue
        q = sas_rank_groups(g[sig], ng)
        ser[d] = g[ret][q == ng].mean() - g[ret][q == 1].mean()
    return pd.Series(ser, dtype=float).sort_index()


def hl_by_bucket(df, sig, ret, bucket, ng=5):
    return {str(b): window_stats(hl_series(g, sig, ret, ng)) for b, g in df.dropna(subset=[bucket]).groupby(bucket)}


def main():
    os.makedirs(OUT, exist_ok=True)
    U = v2_universe.load()
    U = U[(U["X"] <= END) & ~U["is_etf"].astype(bool)].copy()
    p, base = load_panel()
    p = p[(p["X"] >= "2014-01-01") & (p["X"] <= END)]
    # V2 straddle outcomes (FRONT ATM straddle per $ premium): GROSS delta-hedged daily, and C50 H1 net
    keys = U[U["LOU_loose"]]
    bk = vs.Book(vs.load_legs(keys), vs.load_roots())
    for nm, lv, pol in (("str_gross_H2", "GROSS", "H2"), ("str_gross_H0", "GROSS", "H0"), ("str_C50_H1", "C50", "H1")):
        v = bk.get("STR_F", vs.STRADDLE("FRONT"), lv, pol)
        v = v.assign(**{nm: v["L_tot"] / v["prem_L"]})[["F", "X", "root", nm]]
        U = U.merge(v, on=["F", "X", "root"], how="left")
    fc = pd.read_parquet(os.path.join(DATA, "derived", "firm_month_costs.parquet"),
                         columns=["id", "date_var", "rL_COST2_e50", "rS_COST2_e50"]).rename(columns={"id": "root", "date_var": "X"})
    ucols = ["root", "F", "X", "LOU", "LOU_B", "back_listed", "FRONT_atm_iv", "FRONT_atm_rel_spread", "FRONT_skew25",
             "skew_next", "iv_next", "rv", "rv_idio", "jump_share", "beta", "str_gross_H2", "str_gross_H0", "str_C50_H1"]
    P = p.merge(U[ucols].drop(columns=["F"]), on=["root", "X"], how="left").merge(fc, on=["root", "X"], how="left")
    # LOU frame: all LOU names, panel outcomes where available (signals from the universe grid)
    D = U[U["LOU"]].merge(p[["root", "X", "vix_posoi", "VIX_Prc", "VIX_Prc_bid", "RV_Corridor", "VIX_BA_percent"]],
                          on=["root", "X"], how="left")
    for d in (P, D):
        d["logRVc"] = np.log(d["RV_Corridor"].clip(lower=1e-8))
        d["logIVc"] = np.log(d["VIX_Prc"])
        d["VRP"] = d["logRVc"] - d["logIVc"]
        d["log_rv"] = np.log(d["rv"].clip(lower=1e-8))
        d["log_rv_idio"] = np.log(d["rv_idio"].clip(lower=1e-8))
        d["log_rv_sys"] = np.log((d["rv"] - d["rv_idio"]).clip(lower=1e-8))
        d["idio_share"] = d["rv_idio"] / d["rv"]
        d["log_atm_iv"] = np.log(d["FRONT_atm_iv"])
        d["VRP_atm"] = d["log_rv"] - np.log(d["FRONT_atm_iv"] ** 2 * (d["X"] - d["F"]).dt.days / 365)
        d["d_skew"] = d["skew_next"] - d["FRONT_skew25"]
        d["d_iv"] = d["iv_next"] - d["FRONT_atm_iv"]
        d["mid_bias"] = (d["VIX_Prc"] - d["VIX_Prc_bid"]) / d["VIX_Prc"]
    res = {"counts": {
        "P_rows_DISC": int(((P["X"] >= WINS["DISC"][0]) & (P["X"] <= WINS["DISC"][1]) & P["vix_posoi"].notna()).sum()),
        "LOU_per_month_median": float(D.groupby("X").size().median()),
        "LOU_with_S0_per_month_median": float(D[D["S0"].notna()].groupby("X").size().median()),
        "LOU_B_per_month_median": float(U[U["LOU_B"]].groupby("X").size().median()),
        "LOU_with_vix_posoi_share": float(D["vix_posoi"].notna().mean())}}
    # ---------------- A1 decomposition ----------------
    outcomes = ["vix_posoi", "rL_COST2_e50", "str_gross_H2", "str_gross_H0", "str_C50_H1", "logRVc", "logIVc", "VRP",
                "log_rv", "log_rv_idio", "log_rv_sys", "idio_share", "jump_share", "log_atm_iv", "VRP_atm", "d_iv",
                "FRONT_skew25", "d_skew", "VIX_BA_percent", "FRONT_atm_rel_spread", "mid_bias"]
    Ph = P[P["vix_posoi"].notna()].copy()
    for uni, d in (("P", Ph), ("LOU", D.copy())):
        for c in ("S0", "Mom", "Lag1"):
            d[f"r_{c}"] = crank(d, c)
        res[f"A1_{uni}"] = {y: fm(d, y, ["r_S0"]) for y in outcomes if y in d}
        res[f"A1_{uni}_controls"] = {y: fm(d, y, ["r_S0", "r_Mom", "r_Lag1"])
                                     for y in ["vix_posoi", "str_gross_H2", "VRP", "log_rv", "log_rv_idio", "log_atm_iv"] if y in d}
    # ---------------- A2 mid-artifact ----------------
    d = Ph
    d["spr"] = d["FRONT_atm_rel_spread"].fillna(np.inf)            # not in V2 roots => failed the 25% screen
    d["liq_terc"] = d.groupby("X")["spr"].transform(
        lambda x: pd.qcut(x.rank(method="first"), 3, labels=["liq", "mid", "illiq"])).astype(str)
    res["A2i_double_sort_MID"] = hl_by_bucket(d, "S0", "vix_posoi", "liq_terc")
    out = {}
    for b, gb in d.dropna(subset=["S0", "rL_COST2_e50", "rS_COST2_e50"]).groupby("liq_terc"):
        ser = {}
        for dd, g in gb.groupby("X"):
            if len(g) < 15:
                continue
            q = sas_rank_groups(g["S0"], 5)
            ser[dd] = g["rL_COST2_e50"][q == 5].mean() - g["rS_COST2_e50"][q == 1].mean()
        out[str(b)] = window_stats(pd.Series(ser, dtype=float))
    res["A2i_double_sort_C50_executable_paper_construction"] = out
    res["A2i_tercile_median_spread"] = d.replace(np.inf, np.nan).groupby("liq_terc")["FRONT_atm_rel_spread"].median().to_dict()
    res["A2i_tercile_share_missing_from_V2"] = d.groupby("liq_terc")["FRONT_atm_rel_spread"].apply(lambda x: float(x.isna().mean())).to_dict()
    res["A2ii_NonQ_MID_by_tercile"] = hl_by_bucket(d, "NonQ", "vix_posoi", "liq_terc")
    d["r_S0t"] = crank(d, "S0", ("X", "liq_terc")); d["r_NonQt"] = crank(d, "NonQ", ("X", "liq_terc"))
    res["A2ii_FM_S0_vs_NonQ_by_tercile"] = {str(b): fm(g, "vix_posoi", ["r_S0t", "r_NonQt"], min_n=20)
                                           for b, g in d.groupby("liq_terc")}
    # inside LOU (re-ranked): S0, NonQ, S1 H-L and the paired difference (VERDICT A)
    dl = D.copy()
    for c in ("S0", "NonQ", "S1"):
        dl[f"r_{c}"] = crank(dl, c)
    res["A2ii_FM_S0_vs_NonQ_LOU"] = fm(dl, "vix_posoi", ["r_S0", "r_NonQ"], min_n=20)
    res["A2ii_FM_S0_vs_NonQ_LOU_straddle_gross_H2"] = fm(dl, "str_gross_H2", ["r_S0", "r_NonQ"], min_n=20)
    verd = {}
    for ret in ("vix_posoi", "str_gross_H2", "str_C50_H1"):
        a, b = hl_series(dl, "S0", ret), hl_series(dl, "NonQ", ret)
        j = pd.concat([a, b], axis=1, keys=["S0", "NonQ"]).dropna()
        verd[ret] = {"HL_S0": window_stats(a), "HL_NonQ": window_stats(b), "paired_diff": window_stats(j["S0"] - j["NonQ"])}
        if ret == "vix_posoi":
            j.to_csv(os.path.join(OUT, "lou_hl_series.csv"))
    res["A_verdict_inputs_LOU"] = verd
    pd_ = verd["vix_posoi"]["paired_diff"].get("DISC", {})
    res["VERDICT_A"] = ("PASS" if pd_.get("mean", -1) > 0 and pd_.get("t", 0) > 2 else
                        "FAIL (seasonal-specific component not significant inside LOU: treat as mainly mid/liquidity artifact)")
    # (iii) S1 vs S0
    res["A2iii_S1_MID_by_tercile"] = hl_by_bucket(d, "S1", "vix_posoi", "liq_terc")
    res["A2iii_S0_MID_LOU"] = window_stats(hl_series(dl, "S0", "vix_posoi"))
    res["A2iii_S1_MID_LOU"] = window_stats(hl_series(dl, "S1", "vix_posoi"))
    # (iv) persistence: FM slope of vix_posoi(m) on rank of vix_all(m-L), L = 1..12, by tercile
    pers = {}
    for L in range(1, 13):
        d[f"lag{L}"] = base.reindex(pd.MultiIndex.from_arrays([d["root"].values, (d["m"] - L).values])).values
        d[f"r_lag{L}"] = crank(d, f"lag{L}", ("X", "liq_terc"))
        pers[L] = {str(b): fm(g, "vix_posoi", [f"r_lag{L}"], min_n=20).get(f"r_lag{L}", {}) for b, g in d.groupby("liq_terc")}
    res["A2iv_persistence_by_lag"] = pers
    # (v) listing-cycle control: BACK monthly listed at F or not
    res["A2v_listing_cycle_P"] = hl_by_bucket(d.assign(bl=d["back_listed"].map({True: "back_listed", False: "back_not_listed"})),
                                              "S0", "vix_posoi", "bl")
    res["A2v_listing_cycle_LOU"] = hl_by_bucket(dl.assign(bl=dl["back_listed"].map({True: "back_listed", False: "back_not_listed"})),
                                                "S0", "vix_posoi", "bl")
    # composition: where the paper's Q1/Q5 live
    d["q_full"] = d.groupby("X")["S0"].transform(lambda x: sas_rank_groups(x.dropna(), 5).reindex(x.index))
    res["composition"] = {
        "share_in_LOU_by_full_quintile": d.groupby("q_full")["LOU"].apply(lambda x: float(x.fillna(False).mean())).to_dict(),
        "median_front_atm_spread_by_quintile": d.replace(np.inf, np.nan).groupby("q_full")["FRONT_atm_rel_spread"].median().round(4).to_dict(),
        "share_missing_from_V2_by_quintile": d.groupby("q_full")["FRONT_atm_rel_spread"].apply(lambda x: float(x.isna().mean())).to_dict()}
    json.dump(res, open(os.path.join(OUT, "phaseA.json"), "w"), indent=1, default=float)
    print(json.dumps({k: res[k] for k in ("counts", "VERDICT_A", "A_verdict_inputs_LOU", "composition")}, indent=1, default=float))


if __name__ == "__main__":
    main()
