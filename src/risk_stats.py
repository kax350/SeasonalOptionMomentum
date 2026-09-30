"""Tail-risk report and kill-test statistics on a monthly return series (fraction of NAV)."""
import numpy as np, pandas as pd


def max_consecutive_losses(r):
    best = cur = 0
    for x in r:
        cur = cur + 1 if x < 0 else 0
        best = max(best, cur)
    return best


def drawdown(r):
    cum = (1 + r).cumprod()
    peak = cum.cummax().clip(lower=1.0)
    return (cum / peak - 1).min()


def tail_report(r: pd.Series, rf_monthly: float = 0.0):
    r = pd.Series(r).dropna()
    n = len(r)
    if n < 2:
        return {"n_months": n}
    mu, sd = r.mean(), r.std(ddof=1)
    ex = r - rf_monthly
    dsd = np.sqrt((np.minimum(ex, 0) ** 2).mean())
    cagr = (1 + r).prod() ** (12 / n) - 1
    mdd = drawdown(r)
    var95 = -np.quantile(r, 0.05)
    cvar95 = -r[r <= np.quantile(r, 0.05)].mean()
    pos = r[r > 0].sort_values(ascending=False)
    tot = r.sum()
    return {
        "n_months": n, "CAGR": cagr, "ann_return": mu * 12, "monthly_mean": mu, "monthly_vol": sd,
        "sharpe_ann": ex.mean() / sd * np.sqrt(12) if sd > 0 else np.nan,
        "sortino_ann": ex.mean() / dsd * np.sqrt(12) if dsd > 0 else np.nan,
        "maxDD": mdd, "calmar": cagr / abs(mdd) if mdd < 0 else np.nan, "worst_month": r.min(), "best_month": r.max(),
        "VaR95": var95, "CVaR95": cvar95, "skew": r.skew(), "kurt": r.kurt(), "win_pct": (r > 0).mean(),
        "max_consec_losing": max_consecutive_losses(r),
        "top5_share_of_profit": pos.head(5).sum() / tot if tot > 0 else np.nan,
        "top10_share_of_profit": pos.head(10).sum() / tot if tot > 0 else np.nan,
        "cum_ex_best3": r.drop(r.nlargest(3).index).sum(), "cum_ex_best6": r.drop(r.nlargest(6).index).sum(),
        "cum_total": tot,
    }


def block_bootstrap(r, block=3, n_boot=10000, seed=7, stationary=False):
    """Moving-block (or Politis-Romano stationary, mean block length `block`) bootstrap of the mean
    and annualised Sharpe. Returns P(mean>0), 5% / 95% quantiles."""
    r = np.asarray(pd.Series(r).dropna(), float)
    n = len(r)
    rng = np.random.default_rng(seed)
    means, sharpes = np.empty(n_boot), np.empty(n_boot)
    for b in range(n_boot):
        idx = []
        if stationary:
            i = rng.integers(n)
            while len(idx) < n:
                idx.append(i % n)
                i = rng.integers(n) if rng.random() < 1 / block else i + 1
        else:
            while len(idx) < n:
                s = rng.integers(0, n - block + 1)
                idx.extend(range(s, s + block))
        x = r[np.array(idx[:n])]
        means[b] = x.mean()
        sd = x.std(ddof=1)
        sharpes[b] = x.mean() / sd * np.sqrt(12) if sd > 0 else np.nan
    return {"p_mean_gt0": float((means > 0).mean()), "mean_q05": float(np.quantile(means, 0.05)),
            "mean_q95": float(np.quantile(means, 0.95)), "sharpe_q05": float(np.nanquantile(sharpes, 0.05)),
            "sharpe_q50": float(np.nanquantile(sharpes, 0.5)), "sharpe_q95": float(np.nanquantile(sharpes, 0.95))}
