"""Round 12-13: frozen-candidate validation (2024-2025 holdout, 2026 extension), the 20 kill tests,
tail-risk report, benchmarks and the $25k account statistics. Requires results/retail/frozen_candidate.json.
Nothing here may change the candidate (RESEARCH_LEDGER A10-A11)."""
import os, sys, json
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(__file__))
from analysis_retail import load, account_series, research_series, executable, OUT, NAV, DATA
from risk_stats import tail_report, block_bootstrap
from portfolio import COMM

WIN = {"pre_2019_2020": ("2019-07-01", "2020-12-31"), "dev_2021_2023": ("2021-01-01", "2023-12-31"),
       "holdout_2024_2025": ("2024-01-01", "2025-12-31"), "ext_2026": ("2026-01-01", "2026-12-31"),
       "post_2021_2026": ("2021-01-01", "2026-12-31"), "frozen_2024_2026": ("2024-01-01", "2026-12-31"),
       "y2022_bear": ("2022-01-01", "2022-12-31"), "covid_2020": ("2020-02-01", "2020-05-31"),
       "y2024": ("2024-01-01", "2024-12-31"), "y2025": ("2025-01-01", "2025-12-31"), "y2026": ("2026-01-01", "2026-12-31")}


def window(s, k):
    a, b = WIN[k]
    return s[(s.index >= a) & (s.index <= b)]


def summarize(df, label):
    r = df["ret"]
    out = {"label": label}
    for k in WIN:
        x = window(r, k)
        if len(x) >= 2:
            t = tail_report(x)
            out[k] = {kk: (float(v) if isinstance(v, (int, float, np.floating, np.integer)) else v) for kk, v in t.items()}
    return out


def shifted_variant(c, uni, pos, kind_override, entry_when="1545"):
    """Re-evaluate the candidate's own monthly selections with a different structure kind or entry
    snapshot (kill tests 16, 17). Only the selected names are re-priced."""
    from retail import evaluate_month, daily_paths
    from equity_vix import RateCurve
    from analysis_retail import pick
    rates = RateCurve()
    rows = []
    budget = min(c["risk"] * NAV / (2 * c["K"]), 500.0)
    for F in sorted(pos["F"].unique()):
        hi, lo = pick(uni, pos, F, c["universe"], c["K"], c["kind"], "seasonal", c["method"], budget_per_pos=budget)
        names = sorted(set(hi) | set(lo))
        if not names:
            continue
        X = pos[pos["F"] == F]["X"].iloc[0]
        paths = daily_paths(names, F, X)
        from retail import KINDS
        df = evaluate_month(pd.Timestamp(F).date(), pd.Timestamp(X).date(), entry_when, rates, paths, names=names,
                            kinds_by_root={r: [kind_override] for r in names})
        if df.empty:
            continue
        keep = [(r, 1) for r in hi] + [(r, -1) for r in lo]
        df = df[[(r, s) in set(keep) for r, s in zip(df["root"], df["side"])]]
        df["kind"] = c["kind"]   # relabel so account_series can treat it as the candidate kind
        rows.append(df)
    if not rows:
        return None
    v = pd.concat(rows, ignore_index=True)
    from analysis_retail import HEDGES, COSTS
    for h in HEDGES:
        hp = 0.0 if h == "H0" else (v[f"hedge_pnl_{h}"].fillna(0) - 0.005 * v[f"hedge_shares_{h}"].fillna(0)
                                     - 0.0002 * v[f"hedge_notional_{h}"].fillna(0) - v[f"hedge_borrow_{h}"].fillna(0))
        for cc in COSTS:
            v[f"net_{h}_{cc}"] = v[f"pnl_{cc}"] - COMM * v[f"ncontracts_{cc}"] + hp
    v["capital"] = np.where(np.isfinite(v["max_loss_nat"]), v["max_loss_nat"], 100 * v["entry_nat"].abs())
    return v


def main():
    frozen = json.load(open(os.path.join(OUT, "frozen_candidate.json")))
    c = frozen["candidate"]
    pos, uni = load("full")
    base = dict(universe=c["universe"], K=c["K"], kind=c["kind"], hedge=c["chosen_hedge"], risk_pct=c["risk"],
                vega_match=c["vega_match"], method=c["method"])
    res = {"candidate": c}

    def run(**kw):
        a = dict(base); a.update(kw)
        return account_series(uni, pos, a["universe"], a["K"], a["kind"], a["hedge"], a["risk_pct"], a["vega_match"],
                              a["method"], cost=a.get("cost", "e050"), comm=a.get("comm", COMM),
                              stk_mult=a.get("stk_mult", 1.0), skip_rank=a.get("skip_rank", 0),
                              drop_one=a.get("drop_one", False))

    main_df = run()
    main_df.to_csv(os.path.join(OUT, "candidate_monthly_full.csv"))
    res["base"] = summarize(main_df, "base: combo mid+50% spread, $0.70/contract")
    res["executable_share_all"] = executable(main_df, c["K"])
    tests = {
        "T1_real_costs_e050": {},
        "T2_natural_fill": {"cost": "e100"},
        "T3_natural_plus_1tick": {"cost": "tick"},
        "T4_double_commissions": {"comm": 2 * COMM, "stk_mult": 2.0},
        "T14_rank_perturbation_skip1": {"skip_rank": 1},
        "T15_wing_delta_perturbation": {"kind": {"IFLY15": "IFLY10", "IFLY10": "IFLY15"}.get(c["kind"], c["kind"])},
        "T18_one_missing_position": {"drop_one": True},
        "T19_liquidity_tightening": {"universe": "Ltight"},
        "T20_half_size": {"risk_pct": c["risk"] / 2},
        "COST0_mid": {"cost": "e000"}, "COST1_e25": {"cost": "e025"},
        "H0_no_hedge": {"hedge": "H0"}, "H1_daily_hedge": {"hedge": "H1"}, "H2_15": {"hedge": "H2_15"}, "H2_25": {"hedge": "H2_25"},
    }
    monthly = {"base": main_df["ret"]}
    for name, kw in tests.items():
        try:
            d = run(**kw)
            res[name] = summarize(d, name)
            monthly[name] = d["ret"]
        except Exception as e:
            res[name] = {"error": repr(e)[:300]}
    # T16 +/- 1 strike, T17 entry delay (15:59 instead of 15:45)
    for name, (kind, ew) in {"T16_strike_up": (c["kind"] + "_UP", "1545"), "T16_strike_down": (c["kind"] + "_DN", "1545"),
                             "T17_entry_delay_1559": (c["kind"], "close")}.items():
        try:
            v = shifted_variant(c, uni, pos, kind, ew)
            pos2 = pd.concat([pos[~((pos["kind"] == c["kind"]))], v], ignore_index=True) if v is not None else pos
            d = account_series(uni, pos2, c["universe"], c["K"], c["kind"], c["chosen_hedge"], c["risk"], c["vega_match"], c["method"])
            res[name] = summarize(d, name)
            monthly[name] = d["ret"]
        except Exception as e:
            res[name] = {"error": repr(e)[:300]}
    # T5/T6 remove best months, T12/T13 bootstraps
    r = main_df["ret"]
    for k in ("post_2021_2026", "frozen_2024_2026"):
        x = window(r, k)
        res[f"T5_T6_remove_best_{k}"] = {"cum": float(x.sum()), "ex_best3": float(x.drop(x.nlargest(3).index).sum()),
                                         "ex_best6": float(x.drop(x.nlargest(6).index).sum()) if len(x) > 6 else None}
        res[f"T12_block_bootstrap_{k}"] = block_bootstrap(x, block=3, stationary=False)
        res[f"T13_stationary_bootstrap_{k}"] = block_bootstrap(x, block=3, stationary=True)
    pd.DataFrame(monthly).to_csv(os.path.join(OUT, "kill_tests_monthly.csv"))
    json.dump(res, open(os.path.join(OUT, "kill_tests.json"), "w"), indent=1, default=float)
    print(json.dumps({k: (v.get("frozen_2024_2026", v) if isinstance(v, dict) else v) for k, v in res.items()}, indent=1, default=float)[:8000])


if __name__ == "__main__":
    main()
