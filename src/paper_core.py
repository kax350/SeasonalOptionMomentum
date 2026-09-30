"""Signal formation, quintile sorts and factor statistics — port of
SAS functions/form_hold_period_seas_2third.sas, HL_CS(_HL_length).sas, GMM.sas and
Tables/Table 5/Table5_Seasonal.sas.

Panel convention (as in the SAS code): one row per (id, date_var) where date_var = exdate_trade,
i.e. a monthly return is indexed by the END of its holding period; month lags are counted with
SAS intck('month', lag_date, date) = difference in calendar-month index.
"""
import numpy as np, pandas as pd


def month_index(d: pd.Series) -> pd.Series:
    d = pd.to_datetime(d)
    return d.dt.year * 12 + d.dt.month


def form_signal(panel: pd.DataFrame, form_var: str, minlag: int, maxlag: int, period: int = 1,
                id_col="id", date_col="date_var", stat="mean") -> pd.Series:
    """AVG formation: mean of form_var at lags L in [minlag, maxlag] with L % period == 0,
    requiring n_nonmissing >= (floor(maxlag/period) - ceil(minlag/period) + 1) * 2/3."""
    lags = [L for L in range(minlag, maxlag + 1) if L % period == 0]
    need = (np.floor(maxlag / period) - np.ceil(minlag / period) + 1) * 2.0 / 3.0
    p = panel[[id_col, date_col, form_var]].copy()
    p["m"] = month_index(p[date_col])
    base = p.set_index([id_col, "m"])[form_var]
    base = base[~base.index.duplicated()]
    vals = []
    for L in lags:
        key = pd.MultiIndex.from_arrays([p[id_col].values, (p["m"] - L).values])
        vals.append(base.reindex(key).values)
    V = np.vstack(vals).T
    n = np.sum(~np.isnan(V), axis=1)
    with np.errstate(invalid="ignore"):
        f = np.nanmean(V, axis=1) if stat == "mean" else np.nansum(V, axis=1)
    f = np.where(n >= need - 1e-9, f, np.nan)
    return pd.Series(f, index=panel.index, name="fvar")


def sas_rank_groups(x: pd.Series, ngroups: int = 5) -> pd.Series:
    """PROC RANK GROUPS=k TIES=LOW: r = order rank (ties get the lowest rank),
    SAS group = FLOOR(r * k / (N + 1))  (0-based)  -> +1 here (1..k)."""
    x = x.dropna()
    N = len(x)
    if N == 0:
        return pd.Series(dtype=float)
    r = x.rank(method="min")
    g = np.floor(r * ngroups / (N + 1)) + 1
    return g.astype(int)


def hl_cs(panel: pd.DataFrame, sortvar="fvar", depvar="hvar", date_col="date_var", ngroups=5):
    """Monthly equal-weighted quintile returns and H-L (= group n minus group 1).
    Only observations with non-missing sortvar are ranked (as in HL_CS: where missing(sortvar)=0);
    returns are averaged over those with non-missing depvar."""
    out = []
    for d, g in panel[panel[sortvar].notna()].groupby(date_col):
        grp = sas_rank_groups(g[sortvar], ngroups)
        gg = g.assign(q=grp)
        m = gg.groupby("q")[depvar].mean()
        c = gg.groupby("q")[depvar].count()
        row = {date_col: d, **{f"Q{int(k)}": v for k, v in m.items()}, **{f"N{int(k)}": v for k, v in c.items()}}
        out.append(row)
    res = pd.DataFrame(out).set_index(date_col).sort_index()
    res["HL"] = res[f"Q{ngroups}"] - res["Q1"]
    return res


def newey_west_t(x, lags=3):
    x = np.asarray(pd.Series(x).dropna(), float)
    T = len(x)
    mu = x.mean()
    e = x - mu
    s = e @ e / T
    for L in range(1, lags + 1):
        w = 1 - L / (lags + 1)
        s += 2 * w * (e[L:] @ e[:-L]) / T
    se = np.sqrt(s / T)
    return mu / se


def max_drawdown(ret, rf=None):
    """Table5_Seasonal.sas: cumulative value of (1 + ret + rf); largest fraction below prior max."""
    r = pd.Series(ret).fillna(0.0)
    rr = 1 + r + (0 if rf is None else pd.Series(rf).reindex(r.index).fillna(0.0))
    cum = rr.cumprod()
    prior = cum.cummax().shift(1)
    dd = (cum / prior - 1).min()
    return min(-dd, 1.0) if pd.notna(dd) else np.nan


def factor_stats(ret, rf=None, nw_lags=3, periods_per_year=12):
    r = pd.Series(ret).dropna()
    if len(r) < 3:
        return {}
    mu, sd = r.mean(), r.std(ddof=1)
    neg = r[r < 0]
    dsd = np.sqrt((np.minimum(r, 0) ** 2).mean())
    return {
        "n_months": len(r), "mean": mu, "t_NW3": newey_west_t(r, nw_lags), "sd": sd,
        "sharpe_m": mu / sd, "sharpe_ann": mu / sd * np.sqrt(periods_per_year),
        "sortino_ann": mu / dsd * np.sqrt(periods_per_year) if dsd > 0 else np.nan,
        "skew": r.skew(), "kurt": r.kurt(), "maxdd": max_drawdown(r, rf),
        "hit_rate": (r > 0).mean(), "worst": r.min(), "best": r.max(),
    }
