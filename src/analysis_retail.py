"""Rounds 8-12: retail proxies, concentration, $25k integer sizing, hedge simplification, frozen
selection (DEVELOPMENT only) and frozen evaluation.

  python analysis_retail.py dev    -> uses ONLY holding months with exit X <= 2023-12-31; runs the
                                     A11 hierarchy and writes results/retail/frozen_candidate.json
  python analysis_retail.py full   -> requires frozen_candidate.json; evaluates everything on all
                                     months (2019-07 ... 2026-09) and writes the full grids.
"""
import os, sys, json, itertools
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(__file__))
from portfolio import account_month, COMM
from risk_stats import tail_report, block_bootstrap
from signals_universe import sector_proxy

DATA = os.environ.get("SOM_DATA", "/home/user/data")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "results", "retail")
DEV_END = pd.Timestamp("2023-12-31")
PERIODS = {"pre_2019_2020": ("2019-07-01", "2020-12-31"), "dev_2021_2023": ("2021-01-01", "2023-12-31"),
           "hold_2024_2025": ("2024-01-01", "2025-12-31"), "ext_2026": ("2026-01-01", "2026-12-31"),
           "post_2021_2026": ("2021-01-01", "2026-12-31"), "frozen_2024_2026": ("2024-01-01", "2026-12-31")}
DEFINED = ["IFLY10", "IFLY15", "SSPREAD"]
HEDGES = ["H0", "H1", "H2_15", "H2_25"]
COSTS = ["e000", "e025", "e050", "e100", "tick"]
NAV = 25000.0


def load(mode):
    pos = pd.read_parquet(os.path.join(DATA, "retail", "positions_1545.parquet"))
    uni = pd.read_parquet(os.path.join(DATA, "retail", "universe_1545.parquet"))
    if mode == "dev":
        pos = pos[pos["X"] <= DEV_END]
        uni = uni[uni["X"] <= DEV_END]
    pos = pos[pos["pnl_e050"].notna()]
    # per-unit net P&L for every (hedge, cost): research convention (no $1 min per stock order)
    for h in HEDGES:
        if h == "H0":
            hp = 0.0
        else:
            hp = pos[f"hedge_pnl_{h}"].fillna(0) - 0.005 * pos[f"hedge_shares_{h}"].fillna(0) \
                - 0.0002 * pos[f"hedge_notional_{h}"].fillna(0) - pos[f"hedge_borrow_{h}"].fillna(0)
        for c in COSTS:
            pos[f"net_{h}_{c}"] = pos[f"pnl_{c}"] - COMM * pos[f"ncontracts_{c}"] + hp
            if c == "e050":
                pos[f"net2x_{h}_{c}"] = pos[f"pnl_{c}"] - 2 * COMM * pos[f"ncontracts_{c}"] + hp
    pos["capital"] = np.where(np.isfinite(pos["max_loss_nat"]), pos["max_loss_nat"], 100 * pos["entry_nat"].abs())
    return pos, uni


def pick(uni, pos, F, universe, K, kind, predictor="seasonal", method="PAIR1", budget_per_pos=None,
         skip_rank=0, rng=None):
    u = uni[(uni["F"] == F) & uni["eligible_P"]]
    if universe in ("L", "Ltight"):
        u = u[u[universe]]
    elif universe == "L$":
        u = u[u["L"]]
    u = u[u[predictor].notna()] if predictor != "random" else u
    p = pos[(pos["F"] == F) & (pos["kind"] == kind)]
    hi_ok = set(p[p["side"] > 0]["root"])
    lo_ok = set(p[p["side"] < 0]["root"])
    if universe == "L$" and budget_per_pos is not None:
        ml = p.set_index(["root", "side"])["max_loss_nat"] + COMM * p.set_index(["root", "side"])["n_legs"]
        hi_ok = {r for r in hi_ok if ml.get((r, 1), np.inf) <= budget_per_pos}
        lo_ok = {r for r in lo_ok if ml.get((r, -1), np.inf) <= budget_per_pos}
    if predictor == "random":
        names = list(u["root"])
        rng.shuffle(names)
        hi = [r for r in names if r in hi_ok][:K]
        lo = [r for r in names if r in lo_ok and r not in hi][:K]
        return hi, lo
    if method == "PAIR2":
        sec = uni_sector(F, u["root"].tolist())
        u = u.assign(sector=u["root"].map(sec)).dropna(subset=["sector"])
        cand = []
        for s_, g in u.groupby("sector"):
            if len(g) < 5:
                continue
            gh = g[g["root"].isin(hi_ok)].sort_values([predictor, "root"], ascending=[False, True])
            gl = g[g["root"].isin(lo_ok)].sort_values([predictor, "root"])
            if gh.empty or gl.empty or gh.iloc[0]["root"] == gl.iloc[0]["root"]:
                continue
            cand.append((gh.iloc[0][predictor] - gl.iloc[0][predictor], gh.iloc[0]["root"], gl.iloc[0]["root"]))
        cand.sort(reverse=True)
        if len(cand) < K:
            return [], []
        return [c[1] for c in cand[:K]], [c[2] for c in cand[:K]]
    uh = u[u["root"].isin(hi_ok)].sort_values([predictor, "root"], ascending=[False, True])
    ul = u[u["root"].isin(lo_ok)].sort_values([predictor, "root"])
    hi = list(uh["root"].iloc[skip_rank:skip_rank + K])
    lo = [r for r in ul["root"].iloc[skip_rank:] if r not in hi][:K]
    return hi, lo


_SECTOR_CACHE = {}


def uni_sector(F, roots):
    if F not in _SECTOR_CACHE:
        from equity_vix import normalize_root
        px = uni_sector.px
        if px is None:
            px = pd.read_parquet(os.path.join(DATA, "stocks", "ohlcv.parquet"), columns=["date", "act_symbol", "close"])
            px["date"] = pd.to_datetime(px["date"])
            px["root"] = normalize_root(px["act_symbol"].astype(str))
            uni_sector.px = px
        _SECTOR_CACHE[F] = sector_proxy(px, F, list(roots))
    return _SECTOR_CACHE[F]


uni_sector.px = None


def research_series(uni, pos, universe, K, kind, hedge="H0", cost="e050", sides="LS", predictor="seasonal",
                    method="PAIR1", net_prefix="net", skip_rank=0, rng=None):
    """Equal-capital monthly return (P&L / capital, capital = max loss or |premium|)."""
    out, npos = {}, {}
    col = f"{net_prefix}_{hedge}_{cost}"
    for F in sorted(pos["F"].unique()):
        hi, lo = pick(uni, pos, F, universe, K, kind, predictor, method, skip_rank=skip_rank, rng=rng)
        if sides == "LS" and (not hi or not lo):
            continue
        sel = []
        if sides in ("LS", "L"):
            sel += [(r, 1) for r in hi]
        if sides in ("LS", "S"):
            sel += [(r, -1) for r in lo]
        p = pos[(pos["F"] == F) & (pos["kind"] == kind)].set_index(["root", "side"])
        rows = p.loc[[s for s in sel if s in p.index]]
        if rows.empty:
            continue
        X = rows["X"].iloc[0]
        out[X] = float((rows[col] / rows["capital"]).mean())
        npos[X] = len(rows)
    return pd.Series(out).sort_index(), pd.Series(npos).sort_index()


def account_series(uni, pos, universe, K, kind, hedge, risk_pct, vega_match=False, method="PAIR1",
                   cost="e050", comm=COMM, stk_mult=1.0, predictor="seasonal", skip_rank=0, drop_one=False):
    recs = []
    budget_per_pos = min(risk_pct * NAV / (2 * K), 500.0)
    for F in sorted(pos["F"].unique()):
        hi, lo = pick(uni, pos, F, universe, K, kind, predictor, method, budget_per_pos=budget_per_pos,
                      skip_rank=skip_rank)
        p = pos[(pos["F"] == F) & (pos["kind"] == kind)].set_index(["root", "side"])
        sel = [(r, 1) for r in hi] + [(r, -1) for r in lo]
        sel = [s for s in sel if s in p.index]
        X = pos[pos["F"] == F]["X"].iloc[0]
        if drop_one and len(sel) > 1:
            sel = sel[:-1]  # kill test 18: the last-ranked low-side position is missing
        if not sel:
            recs.append({"X": X, "pnl": 0.0, "traded": False, "n_long": 0, "n_short": 0})
            continue
        rows = p.loc[sel].reset_index()
        rows = rows.rename(columns={f"pnl_{cost}": f"pnl_{cost}"})
        res = account_month(rows, nav=NAV, risk_pct=risk_pct, cost_tag=cost, hedge=hedge, comm=comm,
                            vega_match=vega_match, stk_mult=stk_mult)
        res["X"] = X
        recs.append(res)
    df = pd.DataFrame(recs).set_index("X").sort_index()
    df["ret"] = df["pnl"] / NAV
    return df


def executable(df, K):
    need = min(K, 2)
    ok = (df.get("n_long", 0) >= need) & (df.get("n_short", 0) >= need)
    return float(ok.mean())


def sharpe(x):
    x = pd.Series(x).dropna()
    return float(x.mean() / x.std(ddof=1) * np.sqrt(12)) if len(x) > 2 and x.std(ddof=1) > 0 else np.nan


def per_stats(s):
    res = {}
    for per, (a, b) in PERIODS.items():
        x = s[(s.index >= a) & (s.index <= b)]
        if len(x) > 2:
            res[per] = {"n": int(len(x)), "mean": float(x.mean()), "sharpe": sharpe(x),
                        "maxdd": float(((1 + x).cumprod() / (1 + x).cumprod().cummax().clip(lower=1) - 1).min()),
                        "worst": float(x.min()), "hit": float((x > 0).mean())}
    return res


def research_grid(uni, pos, mode):
    rows = []
    for universe, K, kind, hedge, cost, sides in itertools.product(
            ["P", "L", "Ltight"], [10, 5, 3, 2, 1], ["STRADDLE", "STRANGLE25", "IFLY10", "IFLY15", "SSPREAD"],
            HEDGES, ["e000", "e050", "e100", "tick"], ["LS", "L", "S"]):
        if (hedge != "H0" and cost not in ("e050",)) or (sides != "LS" and (cost != "e050")):
            continue
        s, n = research_series(uni, pos, universe, K, kind, hedge, cost, sides)
        for per, st in per_stats(s).items():
            rows.append({"universe": universe, "K": K, "kind": kind, "hedge": hedge, "cost": cost, "sides": sides,
                         "period": per, "avg_positions": float(n.mean()) if len(n) else 0, **st})
    return pd.DataFrame(rows)


def benchmark_grid(uni, pos):
    rows = []
    for pred in ["seasonal", "mom_2_12", "hv_iv"]:
        for kind in ["STRADDLE", "IFLY15"]:
            for K in (3, 10):
                s, _ = research_series(uni, pos, "L", K, kind, "H0", "e050", "LS", predictor=pred)
                for per, st in per_stats(s).items():
                    rows.append({"bench": pred, "kind": kind, "K": K, "period": per, **st})
    # B3/B4: equal-weight long / short structure on all of L
    for kind in ["STRADDLE", "IFLY15"]:
        for side, name in ((1, "B3_EW_long_vol"), (-1, "B4_EW_short_vol")):
            m = pos[(pos["kind"] == kind) & (pos["side"] == side)].merge(
                uni[["F", "root", "L"]], on=["F", "root"])
            m = m[m["L"]]
            s = (m["net_H0_e050"] / m["capital"]).groupby(m["X"]).mean()
            for per, st in per_stats(s).items():
                rows.append({"bench": name, "kind": kind, "K": "all_L", "period": per, **st})
    # B5 random assignment (200 draws, K=3 IFLY15 and STRADDLE)
    for kind in ["STRADDLE", "IFLY15"]:
        sh = {per: [] for per in PERIODS}
        for seed in range(200):
            rng = np.random.default_rng(seed)
            s, _ = research_series(uni, pos, "L", 3, kind, "H0", "e050", "LS", predictor="random", rng=rng)
            for per, st in per_stats(s).items():
                sh[per].append(st["sharpe"])
        for per, v in sh.items():
            if v:
                rows.append({"bench": "B5_random", "kind": kind, "K": 3, "period": per,
                             "sharpe": float(np.nanmedian(v)), "sharpe_q95": float(np.nanquantile(v, 0.95)),
                             "sharpe_q05": float(np.nanquantile(v, 0.05))})
    return pd.DataFrame(rows)


def dev_selection(uni, pos):
    """A11 hierarchy on DEVELOPMENT months only (exit month X in 2021-01 ... 2023-12, ledger A10)."""
    pos = pos[(pos["X"] >= pd.Timestamp("2021-01-01")) & (pos["X"] <= DEV_END)]
    uni = uni[(uni["X"] >= pd.Timestamp("2021-01-01")) & (uni["X"] <= DEV_END)]
    log = []
    configs = []
    for K in (3, 2, 1):
        for risk in (0.04, 0.08):
            feas = []
            for kind, universe, method, vm in itertools.product(DEFINED, ["L", "L$"], ["PAIR1", "PAIR2"], [False, True]):
                sh = {}
                dfs = {}
                for h in HEDGES:
                    df = account_series(uni, pos, universe, K, kind, h, risk, vm, method)
                    dfs[h] = df
                    sh[h] = sharpe(df["ret"])
                ex = executable(dfs["H0"], K)
                maxc = int(dfs["H0"].get("contracts", pd.Series([0])).max())
                hedge = "H0" if sh["H0"] > 0.5 else ("H1" if sh["H1"] > 0.5 else
                                                      ("H2_15" if sh["H2_15"] > 0.5 else ("H2_25" if sh["H2_25"] > 0.5 else "H1")))
                rec = {"K": K, "risk": risk, "kind": kind, "universe": universe, "method": method, "vega_match": vm,
                       "executable_share": ex, "max_contracts": maxc, **{f"dev_sharpe_{h}": v for h, v in sh.items()},
                       "chosen_hedge": hedge, "dev_sharpe_chosen": sh[hedge],
                       "dev_mean_ret": float(dfs[hedge]["ret"].mean()), "n_legs": 4}
                log.append(rec)
                if ex >= 0.8 and maxc <= 24:
                    feas.append(rec)
            if feas:
                best = sorted(feas, key=lambda r: (-(r["dev_sharpe_chosen"] if np.isfinite(r["dev_sharpe_chosen"]) else -99), r["n_legs"]))[0]
                return best, pd.DataFrame(log)
    return None, pd.DataFrame(log)


def main(mode):
    os.makedirs(OUT, exist_ok=True)
    pos, uni = load(mode)
    if mode == "dev":
        best, log = dev_selection(uni, pos)
        log.to_csv(os.path.join(OUT, "dev_selection_log.csv"), index=False)
        rg = research_grid(uni, pos, mode)
        rg.to_csv(os.path.join(OUT, "dev_research_grid.csv"), index=False)
        frozen = {"frozen_utc": pd.Timestamp.utcnow().isoformat(), "selected_on": "DEVELOPMENT 2021-01..2023-12 only",
                  "candidate": best}
        json.dump(frozen, open(os.path.join(OUT, "frozen_candidate.json"), "w"), indent=1, default=float)
        print(json.dumps(frozen, indent=1, default=float))
        return
    frozen = json.load(open(os.path.join(OUT, "frozen_candidate.json")))
    c = frozen["candidate"]
    rg = research_grid(uni, pos, mode)
    rg.to_csv(os.path.join(OUT, "full_research_grid.csv"), index=False)
    bg = benchmark_grid(uni, pos)
    bg.to_csv(os.path.join(OUT, "benchmarks.csv"), index=False)
    if c is None:
        print("no feasible candidate in DEVELOPMENT")
        return
    df = account_series(uni, pos, c["universe"], c["K"], c["kind"], c["chosen_hedge"], c["risk"], c["vega_match"], c["method"])
    df.to_csv(os.path.join(OUT, "candidate_monthly.csv"))
    print(df.tail())


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "dev")
