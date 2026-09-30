"""Point-in-time monthly scores (seasonal 3/6/9/12 and benchmark predictors) for every root, plus
universe screens used by the retail tests (A5) and the sector proxy for PAIR2 (A9).

Score for formation date F (holding month ending X) uses only returns that ended on or before F:
lags are counted in calendar months of exdate_trade, exactly as in the paper.
"""
import os, sys
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(__file__))
from paper_core import month_index

DATA = os.environ.get("SOM_DATA", "/home/user/data")

PRED = {"seasonal": ((3, 6, 9, 12), 3), "mom_2_12": (tuple(range(2, 13)), 8), "lag1": ((1,), 1)}
SECTOR_ETFS = ["XLB", "XLE", "XLF", "XLI", "XLK", "XLP", "XLU", "XLV", "XLY", "XLRE", "XLC"]


def score_grid(formation_dates, next_exdate_trade):
    """DataFrame (F, X, root, seasonal, mom_2_12, lag1, pct_seasonal, n_ranked)."""
    s = pd.read_parquet(os.path.join(DATA, "panel", "vix_sort.parquet"))
    s["r"] = s["Dynamic_VIX_Return_Corridor"] - s["rf"]
    s["m"] = month_index(s["exdate_trade"])
    base = s.drop_duplicates(["root", "m"]).set_index(["root", "m"])["r"]
    roots = s["root"].unique()
    out = []
    for F, X in zip(formation_dates, next_exdate_trade):
        mX = pd.Timestamp(X).year * 12 + pd.Timestamp(X).month
        df = pd.DataFrame({"root": roots})
        for name, (lags, need) in PRED.items():
            V = np.vstack([base.reindex(pd.MultiIndex.from_arrays([roots, np.full(len(roots), mX - L)])).values
                           for L in lags]).T
            n = (~np.isnan(V)).sum(1)
            with np.errstate(invalid="ignore"):
                df[name] = np.where(n >= need, np.nanmean(V, axis=1), np.nan)
        df = df[df["seasonal"].notna() | df["mom_2_12"].notna()]
        df["pct_seasonal"] = df["seasonal"].rank(pct=True)
        df["n_ranked"] = df["seasonal"].notna().sum()
        df["F"], df["X"] = pd.Timestamp(F), pd.Timestamp(X)
        out.append(df)
    return pd.concat(out, ignore_index=True)


def adv20(px: pd.DataFrame, F):
    """20-session average dollar volume ending the session before F (point-in-time)."""
    x = px[(px["date"] < pd.Timestamp(F)) & (px["date"] >= pd.Timestamp(F) - pd.Timedelta(days=40))]
    x = x.sort_values("date").groupby("root").tail(20)
    return (x["close"] * x["volume"]).groupby(x["root"]).mean()


def sector_proxy(px: pd.DataFrame, F, roots):
    """Assign each root to the SPDR sector ETF with the highest daily-return correlation over the
    prior 252 sessions (ETFs that did not yet exist are ignored)."""
    w = px[(px["date"] < pd.Timestamp(F)) & (px["date"] >= pd.Timestamp(F) - pd.Timedelta(days=380))]
    piv = w.pivot_table(index="date", columns="root", values="close").sort_index().pct_change().iloc[1:]
    etfs = [e for e in SECTOR_ETFS if e in piv.columns and piv[e].notna().sum() > 150]
    names = [r for r in roots if r in piv.columns]
    if not etfs or not names:
        return pd.Series(dtype=object)
    R = piv[names]
    E = piv[etfs]
    C = pd.DataFrame({e: R.corrwith(E[e]) for e in etfs})
    return C.idxmax(axis=1)
