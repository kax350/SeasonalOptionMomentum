# V1 RETAIL ADAPTATION — VERDICT: **FAIL**

Scope: the V1 $25k manual-execution adaptation (RESEARCH_LEDGER.md Section A, rows 5–7). The frozen candidate was selected on development data only (exit months 2021-01 … 2023-12). The holdout (2024-01 … 2025-12) and extension (2026-01 … 2026-09) were evaluated afterwards, for honest reporting only. Nothing was changed after they were seen.

## Frozen candidate (results/retail/frozen_candidate.json)

| Item | Value |
|---|---|
| Structure | 10Δ-wing iron fly (IFLY10). Long-vol side on the seasonal top names, short-vol side on the bottom names. |
| Pairing | Within-sector pairs (PAIR2) |
| Sizing | Vega-matched |
| Positions | K = 3 per side |
| Risk budget | 8% of NAV |
| Universe | L$ |
| Hedge | H1 |
| Development after-cost Sharpe | −3.13 (H0: −1.37) |
| Executable share | 92% of months in development |

Every feasible configuration already had a **negative** after-cost Sharpe in development. The candidate was frozen anyway, by the pre-registered fallback, so that the holdout could be reported.

## Out-of-sample: 2024-01 … 2026-09, 33 months, $25k account, C50 + $0.70/contract

| Window | Mean monthly return on NAV | Cumulative | Win rate |
|---|---|---|---|
| Holdout 2024–2025 | −0.79% | −19.0% | 12.5% |
| Extension 2026 YTD | −0.05% | −0.5% | 0% |
| All 33 months | −0.59% (Sharpe −2.78) | −19.5% (max drawdown −17.8%) | — |

## Kill tests: all negative, none rescues the strategy

| Kill test | 2024–26 mean/month | Sharpe |
|---|---|---|
| T2 natural fill (C100) | −0.85% | −3.34 |
| T3 natural + 1 tick | −0.88% | −3.41 |
| T4 commissions ×2 | −1.07% | −3.90 |
| COST0 mid fills (theoretical) | −0.34% | −1.84 |
| H0 (no hedge) | −0.46% | −1.37 |
| H2 25-share threshold | −0.24% | −1.28 |
| T19 tighter liquidity | −0.05% | −1.28 |

- **T20 (half size) and T16 (one strike down):** no trade. At those budgets no position could be built with integer contracts.
- **T12 / T13 (block and stationary bootstrap):** P(mean > 0) = 0.00 for both 2024–26 and 2021–26.
- **T5 / T6:** removing the best 3 or 6 months makes the result slightly worse.

## Conclusion

The V1 mapping fails at every level, including mid fills:
- extreme-rank single-name structures;
- iron flies, straddles and strangles;
- within-sector or market pairing.

The cost audit (ROUND6_7) explains why. The paper's edge sits in illiquid names and is consumed by the bid-ask spread at C50 or worse. Within liquid names the signal is not significant even at mid (dev diagnostic: delta-hedged ATM straddle Q5−Q1 = +0.64%/month, t = 0.46).

**No manual trading guide is issued.** Follow-up work is the separate RETAILIZATION V2 project (RETAIL_V2_*.md). It re-maps the signal rather than shrinking the paper portfolio.

Raw outputs:
- results/retail/kill_tests.json
- results/retail/kill_tests_monthly.csv
- results/retail/candidate_monthly_full.csv
