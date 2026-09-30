"""Round 6 (transaction-cost audit), Round 7 (extreme-rank compression) and the $25k feasibility
numbers for the paper portfolio (Round 11 part 1), all on the equity-VIX portfolios (paper
construction, PROXY data).

Cost model (RESEARCH_LEDGER A3): long leg bought at VIX_Prc + e*(VIX_Prc_ask - VIX_Prc), short leg sold
at VIX_Prc - e*(VIX_Prc - VIX_Prc_bid); COST4 = natural -/+ one tick per option (sigma2_tick);
stock hedge 2 bps of traded notional (hedge_turnover), options held to expiry (paper).
"""
import os, sys, json, glob
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(__file__))
from paper_core import month_index, factor_stats, sas_rank_groups
from analysis_paper_core import load_panel, signal, SIGNALS

DATA = os.environ.get("SOM_DATA", "/home/user/data")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "results", "costs_concentration")
COSTS = {"COST0_mid": (0.0, False), "COST1_e25": (0.25, False), "COST2_e50": (0.5, False),
         "COST3_natural": (1.0, False), "COST4_nat_1tick": (1.0, True)}
HEDGE_BPS = 0.0002


def fl(x):
    return float(x) if pd.notna(x) else np.nan


def leg_returns(d: pd.DataFrame, e: float, tick: bool, side: int, hedge_bps=HEDGE_BPS):
    """Excess return of buying (side=+1) / the 'long-equivalent' return of the shorted VIX portfolio
    (side=-1) at cost level e. Returns the series that enters Q5 (side +1) or Q1 (side -1)."""
    payoff = d["Dynamic_VIX_Payoff_Corridor"]
    hc = hedge_bps * d["hedge_turnover"]
    if side > 0:
        P = d["VIX_Prc"] + e * (d["VIX_Prc_ask"] - d["VIX_Prc"]) + (d["sigma2_tick"] if tick else 0)
        return (payoff - hc) / P - 1 - d["rf"]
    P = d["VIX_Prc"] - e * (d["VIX_Prc"] - d["VIX_Prc_bid"]) - (d["sigma2_tick"] if tick else 0)
    P = P.where(P > 1e-9, np.nan)
    return (payoff + hc) / P - 1 - d["rf"]


def close_liquidity():
    """Per (date, root) liquidity at the 15:59 snapshot: ATM put/call relative spread, #OTM strikes with bid."""
    cache = os.path.join(DATA, "panel", "close_liquidity.parquet")
    if os.path.exists(cache):
        return pd.read_parquet(cache)
    from equity_vix import select_chain
    import datetime as dt
    hold = pd.read_parquet(os.path.join(DATA, "panel", "vix_hold.parquet"), columns=["root", "date", "St_start", "Forward"])
    rows = []
    for f in sorted(glob.glob(os.path.join(DATA, "opra", "close_snap", "20*.parquet"))):
        d = dt.date.fromisoformat(os.path.basename(f)[:10])
        ch = select_chain(pd.read_parquet(f), d)
        h = hold[hold["date"] == pd.Timestamp(d)].set_index("root")
        ch = ch[ch["root"].isin(h.index)]
        ch["F"] = ch["root"].map(h["Forward"])
        for root, g in ch.groupby("root"):
            Fw = g["F"].iloc[0]
            both = sorted(set(g[g["cp"] == "C"]["strike"]) & set(g[g["cp"] == "P"]["strike"]))
            if not both:
                continue
            k = min(both, key=lambda x: abs(x - Fw))
            a = g[g["strike"] == k]
            mid = (a["bid"] + a["ask"]) / 2
            rs = ((a["ask"] - a["bid"]) / mid).max() if (a["bid"] > 0).all() else np.inf
            otm = ((g["cp"] == "P") & (g["strike"] <= Fw)) | ((g["cp"] == "C") & (g["strike"] > Fw))
            rows.append((pd.Timestamp(d), root, rs, int((otm & (g["bid"] > 0)).sum())))
    liq = pd.DataFrame(rows, columns=["date", "root", "atm_rel_spread", "n_otm_bid"])
    liq.to_parquet(cache, index=False)
    return liq


def adv_table():
    px = pd.read_parquet(os.path.join(DATA, "stocks", "ohlcv.parquet"), columns=["date", "act_symbol", "close", "volume"])
    px["date"] = pd.to_datetime(px["date"])
    px = px[px["date"] >= "2013-01-01"].sort_values(["act_symbol", "date"])
    px["dv"] = px["close"] * px["volume"]
    px["adv20"] = px.groupby("act_symbol")["dv"].transform(lambda x: x.shift(1).rolling(20, min_periods=15).mean())
    return px[["date", "act_symbol", "adv20"]]


def main():
    os.makedirs(OUT, exist_ok=True)
    p = load_panel()
    hold = pd.read_parquet(os.path.join(DATA, "panel", "vix_hold.parquet"))
    hold = hold.rename(columns={"root": "id", "exdate_trade": "date_var"})
    lags, need = SIGNALS["Q_3_6_9_12"]
    p["fvar"] = signal(p, lags, need)
    p["pct"] = p.groupby("date_var")["fvar"].rank(pct=True)
    p["q"] = np.nan
    for dv, g in p[p["fvar"].notna()].groupby("date_var"):
        p.loc[g.index, "q"] = sas_rank_groups(g["fvar"], 5).values
    d = p[p["fvar"].notna() & p["vix_posoi"].notna()][["id", "ticker", "date", "date_var", "fvar", "pct", "q"]].merge(
        hold, on=["id", "date_var"], how="left", suffixes=("", "_h"))
    d = d[d["date_var"] >= "2014-01-01"]
    for c in d.columns:  # nullable pandas dtypes -> plain numpy
        if str(d[c].dtype) in ("Float64", "Int64", "boolean"):
            d[c] = d[c].astype("float64")
    # liquidity flags (paper-level L at the 15:59 snapshot)
    liq = close_liquidity().rename(columns={"root": "id"})
    d = d.merge(liq, on=["date", "id"], how="left")
    adv = adv_table()
    d = d.merge(adv.rename(columns={"act_symbol": "ticker"}), on=["date", "ticker"], how="left")
    base = (d["St_start"] >= 20) & (d["atm_rel_spread"] <= 0.10) & (d["n_otm_bid"] >= 8)
    d["adv_rank"] = d["adv20"].where(base).groupby(d["date"]).rank(ascending=False)
    d["L"] = base & (d["adv_rank"] <= 500)
    baset = (d["St_start"] >= 20) & (d["atm_rel_spread"] <= 0.05) & (d["n_otm_bid"] >= 8)
    d["adv_rank_t"] = d["adv20"].where(baset).groupby(d["date"]).rank(ascending=False)
    d["Ltight"] = baset & (d["adv_rank_t"] <= 250)
    for c, (e, tk) in COSTS.items():
        d[f"rL_{c}"] = leg_returns(d, e, tk, +1)
        d[f"rS_{c}"] = leg_returns(d, e, tk, -1)
    os.makedirs(os.path.join(DATA, "derived"), exist_ok=True)
    d.to_parquet(os.path.join(DATA, "derived", "firm_month_costs.parquet"), index=False)  # quote-derived: keep out of the public repo

    periods = {"overlap_2014_2020": ("2014-01-01", "2020-12-31"), "post_2021_2026": ("2021-01-01", "2026-12-31"),
               "dev_2021_2023": ("2021-01-01", "2023-12-31"), "hold_2024_2025": ("2024-01-01", "2025-12-31"),
               "ext_2026": ("2026-01-01", "2026-12-31")}
    rows = []
    monthly = {}

    def hl_series(sel_hi, sel_lo, c):
        a = sel_hi.groupby("date_var")[f"rL_{c}"].mean()
        b = sel_lo.groupby("date_var")[f"rS_{c}"].mean()
        return (a - b).dropna(), a, b

    configs = []
    for uni in ("P", "L", "Ltight"):
        du = d if uni == "P" else d[d[uni]]
        # quintiles re-ranked within the universe for L (full-universe percentiles kept for P)
        configs.append((uni, "quintile", du[du["q"] == 5], du[du["q"] == 1]))
        for K in (20, 10, 5, 3, 2, 1):
            hi = du.sort_values(["date_var", "fvar", "id"], ascending=[True, False, True]).groupby("date_var").head(K)
            lo = du.sort_values(["date_var", "fvar", "id"], ascending=[True, True, True]).groupby("date_var").head(K)
            configs.append((uni, f"K{K}", hi, lo))
    for uni, kname, hi, lo in configs:
        spread = hi.groupby("date_var")["fvar"].mean() - lo.groupby("date_var")["fvar"].mean()
        thr = spread[(spread.index >= "2014-01-01") & (spread.index <= "2020-12-31")].quantile(0.20)
        for c in COSTS:
            s, a, b = hl_series(hi, lo, c)
            monthly[(uni, kname, c)] = s
            for skip in (False, True):
                ss = s[spread.reindex(s.index) >= thr] if skip else s
                for per, (a0, a1) in periods.items():
                    x = ss[(ss.index >= a0) & (ss.index <= a1)]
                    st = factor_stats(x) if len(x) > 2 else {}
                    st.update({"universe": uni, "K": kname, "cost": c, "skip": skip, "period": per,
                               "long_leg_mean": fl(a[(a.index >= a0) & (a.index <= a1)].mean()),
                               "short_leg_mean": fl(b[(b.index >= a0) & (b.index <= a1)].mean()),
                               "avg_names_per_side": fl(hi[(hi.date_var >= a0) & (hi.date_var <= a1)].groupby("date_var").size().mean()),
                               "avg_hi_pct": fl(hi["pct"].mean()), "avg_lo_pct": fl(lo["pct"].mean()),
                               "avg_score_spread": fl(spread.mean()), "skip_threshold": fl(thr),
                               "cost_drag_vs_mid": np.nan})
                    rows.append(st)
    tab = pd.DataFrame(rows)
    mid = tab[tab["cost"] == "COST0_mid"].set_index(["universe", "K", "skip", "period"])["mean"]
    tab["cost_drag_vs_mid"] = tab.apply(lambda r: mid.get((r["universe"], r["K"], r["skip"], r["period"]), np.nan) - r["mean"], axis=1)
    tab.to_csv(os.path.join(OUT, "hl_costs_concentration.csv"), index=False)
    pd.DataFrame({f"{u}|{k}|{c}": s for (u, k, c), s in monthly.items()}).to_csv(os.path.join(OUT, "hl_monthly.csv"))
    # spreads and hedge turnover diagnostics by quintile
    diag = d.groupby("q").agg(VIX_BA_percent=("VIX_BA_percent", "median"), hedge_turnover_x=("hedge_turnover", "median"),
                              n_opt=("n_opt", "mean"), VIX_Prc=("VIX_Prc", "median"))
    diag["hedge_cost_pct_of_price_2bps"] = HEDGE_BPS * d.groupby("q").apply(lambda g: (g["hedge_turnover"] / g["VIX_Prc"]).median())
    diag.to_csv(os.path.join(OUT, "cost_diagnostics_by_quintile.csv"))
    feasibility(d)
    print(tab[(tab.skip == False) & tab.period.isin(["overlap_2014_2020", "post_2021_2026"]) & tab.K.isin(["quintile", "K10", "K5", "K3", "K1"])]
          [["universe", "K", "cost", "period", "n_months", "mean", "t_NW3", "sharpe_ann", "maxdd"]].to_string())


def feasibility(d: pd.DataFrame):
    """Integer-contract replication of the paper's quintile H-L (each VIX portfolio scaled so its
    smallest-weight option is exactly 1 contract)."""
    x = d[d["q"].isin([1, 5])].copy()
    w_min = 2 * x["delta_max"] / x["strike_max"] ** 2
    lam = 100.0 / w_min                                   # $-notional multiplier (shares per unit weight)
    sum_w = 2 * (1 / x["strike_min"] - 1 / x["strike_max"])  # ~ integral of 2/K^2
    x["contracts"] = lam * sum_w / 100
    x["premium"] = lam * x["sigma2"]
    x["vix_notional"] = lam * x["VIX_Prc"]
    x["stock_turnover"] = lam * x["hedge_turnover"]
    # naked short option margin (CBOE): per share max(0.2S - OTM, 0.1*K or 0.1*S) + premium -> approx 0.15*S per share on the strip
    x["short_margin"] = np.where(x["q"] == 1, lam * sum_w * 0.15 * x["St_start"] + x["premium"], 0.0)
    m = x.groupby("date_var").agg(names=("id", "size"), contracts=("contracts", "sum"), premium_long=("premium", lambda s: s[x.loc[s.index, "q"] == 5].sum()),
                                  premium_short=("premium", lambda s: s[x.loc[s.index, "q"] == 1].sum()),
                                  short_margin=("short_margin", "sum"), stock_turnover=("stock_turnover", "sum"))
    m["capital_needed"] = m["premium_long"] + m["short_margin"]
    q = m.describe(percentiles=[0.05, 0.5, 0.95]).T
    q.to_csv(os.path.join(OUT, "paper_portfolio_feasibility.csv"))
    per_name = x[["contracts", "premium", "vix_notional", "stock_turnover"]].describe(percentiles=[0.05, 0.5, 0.95]).T
    per_name.to_csv(os.path.join(OUT, "paper_portfolio_feasibility_per_name.csv"))
    print(q)
    print(per_name)


if __name__ == "__main__":
    main()
