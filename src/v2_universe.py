"""RETAIL V2 — point-in-time universe table shared by Phases A–G (charter §1, §3; ledger row 2 items 1, 7, 13).

One row per (root, F, X) from the V2 roots table (every underlying that passed the loose pre-screen at F).
  * Seasonal signals are computed on this grid from PAST returns only (paper panel, keyed by (root, month)),
    so a name's score never depends on whether it has a current-month VIX row.
  * LOU flags use FRONT screens only; *_B variants add the BACK screens (needed only by BACK families).
Output: $SOM_DATA/derived/v2_universe.parquet
"""
import os, sys, glob
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(__file__))
from paper_core import month_index

DATA = os.environ.get("SOM_DATA", "/home/user/data")
PATH = os.path.join(DATA, "derived", "v2_universe.parquet")
# name: (lags relative to the target month m(X), min non-missing, source)
LAGS = {"S0": ((3, 6, 9, 12), 3, "sort"), "S1": ((3, 6, 9, 12), 3, "hold"),
        "NonQ": ((1, 2, 4, 5, 7, 8, 10, 11), 6, "sort"), "S0p2": ((2, 5, 8, 11), 3, "sort"),
        "Mom": (tuple(range(2, 13)), 8, "sort"), "Lag1": ((1,), 1, "sort")}
LOU_RULES = {"LOU": (20.0, 0.10, 500), "LOU_tight": (20.0, 0.05, 250), "LOU_loose": (10.0, 0.20, 1000)}


def past_returns():
    s = pd.read_parquet(os.path.join(DATA, "panel", "vix_sort.parquet"),
                        columns=["root", "exdate_trade", "Dynamic_VIX_Return_Corridor", "rf"])
    h = pd.read_parquet(os.path.join(DATA, "panel", "vix_hold.parquet"),
                        columns=["root", "exdate_trade", "Dynamic_VIX_Return_Corridor", "rf"])
    out = {}
    for k, d in (("sort", s), ("hold", h)):
        d = d.assign(m=month_index(d["exdate_trade"]),
                     r=(d["Dynamic_VIX_Return_Corridor"] - d["rf"]).astype("float64"))
        out[k] = d.dropna(subset=["r"]).drop_duplicates(["root", "m"]).set_index(["root", "m"])["r"]
    return out


def load_roots():
    R = pd.concat([pd.read_parquet(f) for f in sorted(glob.glob(os.path.join(DATA, "v2", "roots", "*.parquet")))],
                  ignore_index=True)
    for c in R.columns:
        if str(R[c].dtype) in ("Float64", "Int64", "boolean"):
            R[c] = R[c].astype("float64") if str(R[c].dtype) != "boolean" else R[c].fillna(False).astype(bool)
    return R


def build(save=True):
    R = load_roots()
    D = pd.read_parquet(os.path.join(DATA, "v2", "root_features_dolthub.parquet"))
    U = R.rename(columns={"S0": "spot_F"}).merge(D, on=["root", "F", "X"], how="left")   # roots' S0 = parity spot
    U["m"] = month_index(U["X"])
    base = past_returns()
    for name, (lags, need, src) in LAGS.items():
        b = base[src]
        V = np.vstack([b.reindex(pd.MultiIndex.from_arrays([U["root"].values, (U["m"] - L).values])).values
                       for L in lags]).T
        n = (~np.isnan(V)).sum(1)
        with np.errstate(invalid="ignore"):
            U[name] = np.where(n >= need, np.nanmean(V, axis=1), np.nan)
    stock = ~U["is_etf"].astype(bool)
    for side in ("FRONT", "BACK"):
        U[f"{side}_atm_bid_ok"] = U[f"{side}_atm_bid_ok"].fillna(False).astype(bool) if f"{side}_atm_bid_ok" in U else False
    U["back_listed"] = U["BACK_atm_strike"].notna() if "BACK_atm_strike" in U else False
    for name, (px, sp, top) in LOU_RULES.items():
        ok = stock & (U["S_close_F"] >= px) & U["FRONT_atm_bid_ok"] & (U["FRONT_atm_rel_spread"] <= sp)
        rk = U["adv20"].where(ok).groupby(U["F"]).rank(ascending=False, method="first")
        U[name] = (ok & (rk <= top)).astype(bool)
        U[f"{name}_B"] = (U[name] & U["BACK_atm_bid_ok"] & (U["BACK_atm_rel_spread"] <= sp)).astype(bool)
    U["term_slope"] = U["BACK_atm_iv"] - U["FRONT_atm_iv"]
    nxt = U[["root", "F", "FRONT_skew25", "FRONT_atm_iv"]].rename(
        columns={"F": "X", "FRONT_skew25": "skew_next", "FRONT_atm_iv": "iv_next"})
    U = U.merge(nxt, on=["root", "X"], how="left")      # value observed at the next formation date (= X)
    if save:
        os.makedirs(os.path.dirname(PATH), exist_ok=True)
        U.to_parquet(PATH, index=False)
    return U


def load(rebuild=False):
    if rebuild or not os.path.exists(PATH):
        return build()
    return pd.read_parquet(PATH)


if __name__ == "__main__":
    U = build()
    print(len(U), U["F"].min(), U["F"].max())
    print(U.groupby("X")[["LOU", "LOU_B", "LOU_tight", "LOU_loose"]].sum().describe().round(1))
