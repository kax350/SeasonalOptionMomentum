# RETAIL V2 — KILL TESTS

## Status: Phase G not run, because no candidate survived to be frozen

The charter (§6 Phase G) applies the 20 kill tests and the concentration audit to the **frozen candidate**. Phase F and the freeze are reserved for PASS or WEAK families (§6 Phase F, §8). No V2 family reached PASS or WEAK at C50 (RETAIL_V2_RESULTS.md), so:

- `RETAIL_V2_FROZEN_CANDIDATE.json` was **not** created;
- the FORWARD window (2024-01 … 2026-09) was **never evaluated** for any V2 rule;
- the 20 kill tests and the concentration audit have no object.

Running them on failed families would be a parameter search on dead strategies, which charter §8 forbids.

What follows is the **kill record**: for each pre-registered family, the cheapest cost level at which it already fails.

## Kill record: where each family dies

Criterion: the most generous WEAK rule (DISCOVERY mean > 0 with NW t > 1, and VALIDATION mean > 0), applied to *any* hedge policy H0–H3 at that cost level. "Killed at" = the first cost level where no hedge policy survives.
- GROSS = mid fills, no commissions, no fees.
- MID = mid fills plus all commissions and fees.
- D2 uses its charter hedge (H1).
- Phase E rules exist only at C50 (their target is the C50 net return).

| Family | Survives GROSS (any hedge)? | Survives MID? | Survives C25? | Survives C50? | Killed at |
|---|---|---|---|---|---|
| B1a_top10_long | no | no | no | no | **GROSS** |
| B1b_top20_long | no | no | no | no | **GROSS** |
| B1c_top10_long_BACK | no | no | no | no | **GROSS** |
| B1_LOUavg_long | no | no | no | no | **GROSS** |
| B1x_contrast_rankP_keepLOU_top10 | no | no | no | no | **GROSS** |
| B2_SPY_vega | yes (H2, H3) | no | no | no | **MID** |
| B2_SPY_gamma | yes (H2) | no | no | no | **MID** |
| B2_SPY_premium | yes (H2, H3) | no | no | no | **MID** |
| B2_SPY_eqrisk | yes (H2, H3) | no | no | no | **MID** |
| B2_IWM_vega | yes (H2, H3) | no | no | no | **MID** |
| B2_IWM_gamma | yes (H2, H3) | no | no | no | **MID** |
| B2_IWM_premium | yes (H2, H3) | no | no | no | **MID** |
| B2_IWM_eqrisk | yes (H2, H3) | no | no | no | **MID** |
| B3_sector_vega | yes (H2, H3) | no | no | no | **MID** |
| B3_sector_gamma | yes (H2) | no | no | no | **MID** |
| B3_sector_premium | yes (H2, H3) | no | no | no | **MID** |
| B3_sector_eqrisk | yes (H2) | no | no | no | **MID** |
| B4_LOUavg_vega | no | no | no | no | **GROSS** |
| B5a_Q5_vs_Q4 | no | no | no | no | **GROSS** |
| B5b_Q5_vs_Q3 | yes (H2) | no | no | no | **MID** |
| B5c_D10_vs_D5D6 | no | no | no | no | **GROSS** |
| B5d_top5_vs_LOUavg | no | no | no | no | **GROSS** |
| C1_reverse_calendar_top10 | no | no | no | no | **GROSS** |
| C2_calendar_bottom10 | yes (H2) | no | no | no | **MID** |
| C3_combined | yes (H2) | no | no | no | **MID** |
| C4_1to1_combined | no | no | no | no | **GROSS** |
| C5_diagonal_combined | no | no | no | no | **GROSS** |
| D1_LS_S_ew | no | no | no | no | **GROSS** |
| D1_L_top1_S_ew | no | no | no | no | **GROSS** |
| D1_2v2_S_ew | no | no | no | no | **GROSS** |
| D1_LS_S_adv | no | no | no | no | **GROSS** |
| D1_L_top1_S_adv | no | no | no | no | **GROSS** |
| D1_2v2_S_adv | no | no | no | no | **GROSS** |
| D3_SPY_timing_long | no | no | no | no | **GROSS** |
| D3_SPY_always_long | no | no | no | no | **GROSS** |
| D2_slope_S_ew | no | no | no | no | **GROSS** |
| D2_slope_S_adv | no | no | no | no | **GROSS** |
| E1_k1.0 | n/a | n/a | n/a | no | **C50** |
| E1_k1.5 | n/a | n/a | n/a | no | **C50** |
| E1_k2.0 | n/a | n/a | n/a | no | **C50** |
| E1_k3.0 | n/a | n/a | n/a | no | **C50** |
| E2_k1.0 | n/a | n/a | n/a | no | **C50** |
| E2_k1.5 | n/a | n/a | n/a | no | **C50** |
| E2_k2.0 | n/a | n/a | n/a | no | **C50** |
| E2_k3.0 | n/a | n/a | n/a | no | **C50** |

| Killed at | Families |
|---|---|
| **GROSS:** no signal value even at mid with no costs | 22 |
| **MID:** dies from commissions and hedge fees alone, before paying any spread | 15 |
| **C50:** Phase E rules, defined only at C50 | 8 |
| C25 or later | 0 |

The 15 families that survive at GROSS all do so only with **daily or threshold delta hedging** (H2/H3). They are:
- long top-decile single-name straddles against short index or sector straddles (B2, B3), plus B5b Q5-vs-Q3;
- same-name calendars (C2, C3).

As RETAIL_V2_RESULTS.md shows, that gross premium is mostly the index-versus-single-name variance spread, not the seasonal ranking.

## Robustness of the FAIL: the strategy does not survive even under kinder assumptions

These are hypotheticals for information only. None of them could revive a family (charter §8).

| Kinder assumption | Best result | Verdict |
|---|---|---|
| Stock hedging is **free** (no commission, slippage or borrow), options still at C50 | B2_IWM_premium H3: +1.6%/month (t 0.49) DISCOVERY, +3.0% (t 0.79) VALIDATION. Worst month **−127% of long premium** (March 2020). | Not significant. It is a short-index-straddle crash book, not the seasonal signal. |
| Free stock hedging, options at C25 | B2_IWM_premium H3: +4.1% DISCOVERY / +4.6% VALIDATION, same crash profile | Same object (dispersion with index-crash risk) |
| Options at MID (no spread), all fees | 0 of 88 Phase B and 0 of 15 Phase C cells are WEAK or better | FAIL |
| Inside LOU, the seasonal-specific component itself (Phase A): quarterly minus non-quarterly lags, at mid | −1.2%/month (t −0.28) DISCOVERY | No seasonal information to harvest |

## Concentration and tail notes on the families tested (C50, DISCOVERY)

Worst single month, as a share of long premium:
- B1a top-decile long straddles: **−66.6%**.
- E2 ridge rule: **−96.4%**.
- B2 premium-neutral SPY hedge: **−408%**.
- B2 premium-neutral IWM hedge: **−562%**.
- Sector top-1 long straddle (D1-L): **−99.9%**.

Any book built on unhedged or index-hedged long single-name straddles can lose essentially all its premium in a month. Index-short variants can lose several times the premium in March 2020.

## What would have to be true for a retail edge

Arithmetic on the Phase A and Phase B numbers:
- The best seasonal-specific gross spread inside LOU is about +3.8%/month (daily-hedged straddle Q5−Q1, DISCOVERY only; VALIDATION −1.4%).
- A two-leg implementation costs about 8% of premium per month at C50, before hedging.

Even at C25 (about 5% for two legs) the cost would exceed the DISCOVERY gross spread. The VALIDATION gross spread is already ≤ 0. No retail execution assumption in our cost model closes that gap.
