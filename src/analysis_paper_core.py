"""Rounds 3-5: reproduce the 3/6/9/12 seasonal momentum sort on OPRA-era PROXY data, compare to the
authors' own monthly H-L series (package Figure 4 file), lag-structure tests, RV-vs-IV
decomposition, momentum comparison, and the frozen post-sample extension by calendar year.

Outputs -> results/paper_core/
"""
import os, sys, json
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(__file__))
from paper_core import month_index, hl_cs, factor_stats, sas_rank_groups, newey_west_t

DATA = os.environ.get("SOM_DATA", "/home/user/data")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "results", "paper_core")
FIG4 = os.path.join(ROOT, "replication_package", "code", "Figures", "Figure 4", "seas_1_12_3_.txt")

SIGNALS = {  # name: (lags, NEED)   (PAPER_SPEC §3(b))
    "Q_3_6_9_12": ((3, 6, 9, 12), 3),
    "All_1_12": (tuple(range(1, 13)), 8),
    "NonQ_1_12": ((1, 2, 4, 5, 7, 8, 10, 11), 6),
    "Q_nonannual_3_6_9": ((3, 6, 9), 2),
    "Annual_12": ((12,), 1),
    "Annual_12_24_36": ((12, 24, 36), 2),
    "Q_3_to_36": (tuple(range(3, 37, 3)), 8),
    "Mom_2_12": (tuple(range(2, 13)), 8),
    "Lag1": ((1,), 1),
}


def load_panel():
    s = pd.read_parquet(os.path.join(DATA, "panel", "vix_sort.parquet"))
    h = pd.read_parquet(os.path.join(DATA, "panel", "vix_hold.parquet"))
    s["vix_all"] = s["Dynamic_VIX_Return_Corridor"] - s["rf"]
    h["vix_posoi"] = h["Dynamic_VIX_Return_Corridor"] - h["rf"]
    hcols = ["root", "exdate_trade", "vix_posoi", "VIX_Prc", "RV_Corridor", "VSR_Corridor", "Monthly_RV",
             "VIX_BA_percent", "St_start", "IV_avg", "days_expire", "Static_VIX_Return", "VIX_Prc_bid", "VIX_Prc_ask",
             "Static_VIX_Payoff", "Dynamic_VIX_Payoff_Corridor", "Rf", "num_strikes"]
    p = s[["root", "ticker", "date", "exdate_trade", "vix_all", "rf"]].merge(
        h[hcols], on=["root", "exdate_trade"], how="left")  # left join FROM sorting sample (spec P11)
    p = p.rename(columns={"root": "id", "exdate_trade": "date_var"})
    p["m"] = month_index(p["date_var"])
    return p


def signal(p, lags, need, var="vix_all"):
    base = p.set_index(["id", "m"])[var]
    base = base[~base.index.duplicated()]
    V = np.vstack([base.reindex(pd.MultiIndex.from_arrays([p["id"].values, (p["m"] - L).values])).values
                   for L in lags]).T
    n = np.sum(~np.isnan(V), axis=1)
    with np.errstate(invalid="ignore", divide="ignore"):
        f = np.nanmean(V, axis=1)
    return pd.Series(np.where(n >= need, f, np.nan), index=p.index)


def authors_series():
    a = pd.read_csv(FIG4, sep=r"\s+", header=None, names=["ymd", "d9", "All_1_12", "Q_3_6_9_12", "NonQ_1_12"],
                    na_values=".")
    a["date_var"] = pd.to_datetime(a["ymd"].astype(str))
    a["m"] = month_index(a["date_var"])
    return a


def year_table(hl: pd.DataFrame, col="HL"):
    rows = []
    for y, g in hl.groupby(hl.index.year):
        st = factor_stats(g[col])
        st.update({"year": y, "Q5": g["Q5"].mean(), "Q1": g["Q1"].mean(),
                   "N_avg": g[[c for c in g.columns if c.startswith("N")]].sum(axis=1).mean()})
        rows.append(st)
    return pd.DataFrame(rows)


def main():
    os.makedirs(OUT, exist_ok=True)
    p = load_panel()
    res = {}
    hls = {}
    for name, (lags, need) in SIGNALS.items():
        p["fvar"] = signal(p, lags, need)
        hl = hl_cs(p, sortvar="fvar", depvar="vix_posoi", date_col="date_var")
        hl = hl[hl.index >= "2014-01-01"]
        hls[name] = hl
        hl.to_csv(os.path.join(OUT, f"hl_{name}.csv"))
    # ---------- main signal: overlap vs authors, post-sample by year
    main_hl = hls["Q_3_6_9_12"]
    a = authors_series()
    ov = main_hl[(main_hl.index <= "2020-12-31")].copy()
    ov["m"] = month_index(pd.Series(ov.index, index=ov.index))
    cmp_ = ov.merge(a[["m", "Q_3_6_9_12", "All_1_12", "NonQ_1_12"]], on="m", how="inner")
    res["overlap_vs_authors"] = {
        "n_months": int(len(cmp_)),
        "first": str(ov.index.min().date()), "last": str(ov.index.max().date()),
        "corr_monthly_HL": float(cmp_[["HL", "Q_3_6_9_12"]].corr().iloc[0, 1]),
        "ours": factor_stats(cmp_["HL"]), "authors_same_months": factor_stats(cmp_["Q_3_6_9_12"]),
        "mean_diff": float((cmp_["HL"] - cmp_["Q_3_6_9_12"]).mean()),
    }
    for nm in ["All_1_12", "NonQ_1_12"]:
        o2 = hls[nm][hls[nm].index <= "2020-12-31"].copy()
        o2["m"] = month_index(pd.Series(o2.index, index=o2.index))
        c2 = o2.merge(a[["m", nm]], on="m", how="inner")
        res[f"overlap_vs_authors_{nm}"] = {"n": int(len(c2)), "corr": float(c2[["HL", nm]].corr().iloc[0, 1]),
                                           "ours": factor_stats(c2["HL"]), "authors": factor_stats(c2[nm])}
    cmp_.to_csv(os.path.join(OUT, "overlap_monthly_vs_authors.csv"), index=False)
    # quintile means on overlap
    qcols = [f"Q{i}" for i in range(1, 6)]
    res["quintiles_overlap"] = {q: {"mean": float(ov[q].mean()), "t": float(newey_west_t(ov[q]))} for q in qcols}
    res["avg_firms_overlap"] = float(ov[[f"N{i}" for i in range(1, 6)]].sum(axis=1).mean())
    # ---------- all signals: overlap + post
    tab = []
    for name, hl in hls.items():
        for per, (a0, a1) in {"overlap_2014_2020": ("2014-01-01", "2020-12-31"),
                               "post_2021_2026": ("2021-01-01", "2026-12-31"),
                               "all_2014_2026": ("2014-01-01", "2026-12-31")}.items():
            x = hl[(hl.index >= a0) & (hl.index <= a1)]
            st = factor_stats(x["HL"])
            st.update({"signal": name, "period": per})
            tab.append(st)
    pd.DataFrame(tab).to_csv(os.path.join(OUT, "signals_summary.csv"), index=False)
    # ---------- post-sample by year (frozen paper rule)
    post = main_hl[main_hl.index >= "2020-12-01"]
    yt = year_table(post)
    yt.to_csv(os.path.join(OUT, "post_sample_by_year.csv"), index=False)
    res["post_sample_all"] = factor_stats(post["HL"])
    # ---------- RV vs IV decomposition for main signal (holding sample months)
    p["fvar"] = signal(p, *SIGNALS["Q_3_6_9_12"])
    d = p[p["fvar"].notna() & p["vix_posoi"].notna()].copy()
    d["q"] = d.groupby("date_var")["fvar"].transform(lambda x: sas_rank_groups(x, 5))
    d["logRV"] = np.log(d["RV_Corridor"].clip(lower=1e-8))
    d["logIV"] = np.log(d["VIX_Prc"])
    d["logRV_IV"] = d["logRV"] - d["logIV"]
    dec = d.groupby(["date_var", "q"])[["logRV", "logIV", "logRV_IV", "vix_posoi", "VIX_BA_percent"]].mean().unstack("q")
    dec_hl = pd.DataFrame({k: dec[k][5] - dec[k][1] for k in ["logRV", "logIV", "logRV_IV", "vix_posoi"]})
    res["rv_iv_decomposition"] = {
        per: {k: {"mean_HL": float(dec_hl.loc[(dec_hl.index >= a0) & (dec_hl.index <= a1), k].mean()),
                  "t": float(newey_west_t(dec_hl.loc[(dec_hl.index >= a0) & (dec_hl.index <= a1), k]))}
              for k in dec_hl.columns}
        for per, (a0, a1) in {"overlap": ("2014-01-01", "2020-12-31"), "post": ("2021-01-01", "2026-12-31")}.items()}
    res["ba_percent_by_quintile"] = {int(q): float(dec["VIX_BA_percent"][q].mean()) for q in range(1, 6)}
    # ---------- Fama-MacBeth: seasonal vs momentum (standardised cross-sectional)
    p["sig_Q"] = signal(p, *SIGNALS["Q_3_6_9_12"])
    p["sig_M"] = signal(p, *SIGNALS["Mom_2_12"])
    p["sig_L1"] = signal(p, *SIGNALS["Lag1"])
    fm_rows = []
    for dv, g in p[p[["sig_Q", "sig_M", "sig_L1", "vix_posoi"]].notna().all(axis=1)].groupby("date_var"):
        if len(g) < 30:
            continue
        Z = g[["sig_Q", "sig_M", "sig_L1"]].rank(pct=True) - 0.5
        X = np.column_stack([np.ones(len(g)), Z.values])
        y = g["vix_posoi"].clip(g["vix_posoi"].quantile(0.005), g["vix_posoi"].quantile(0.995)).values
        b = np.linalg.lstsq(X, y, rcond=None)[0]
        fm_rows.append({"date_var": dv, "a": b[0], "seasonal": b[1], "momentum": b[2], "lag1": b[3]})
    fm = pd.DataFrame(fm_rows).set_index("date_var")
    res["fama_macbeth_rank_slopes"] = {
        per: {k: {"mean": float(fm.loc[(fm.index >= a0) & (fm.index <= a1), k].mean()),
                  "t": float(newey_west_t(fm.loc[(fm.index >= a0) & (fm.index <= a1), k]))}
              for k in ["seasonal", "momentum", "lag1"]}
        for per, (a0, a1) in {"overlap": ("2014-01-01", "2020-12-31"), "post": ("2021-01-01", "2026-12-31")}.items()}
    json.dump(res, open(os.path.join(OUT, "summary.json"), "w"), indent=1, default=float)
    print(json.dumps(res, indent=1, default=float)[:6000])
    print(yt.to_string())


if __name__ == "__main__":
    main()
