# RETAIL V2 — RESULTS (Phases B–E)

**All 39 pre-registered families FAIL at C50. No family qualifies for Phase F ($25k integer portfolio) or Phase G (kill tests).**

## Phase verdicts

| Phase | Families | PASS | WEAK | FAIL | Phase verdict |
|---|---|---|---|---|---|
| A — decomposition | 1 test | — | — | ✔ | **FAIL** (seasonal-specific component = 0 inside LOU) |
| B — liquid long-vol + liquid hedge | 22 | 0 | 0 | 22 | **FAIL** |
| C — same-name term structure | 5 | 0 | 0 | 5 | **FAIL** |
| D — sector / ETF / market compression | 10 | 0 | 0 | 10 | **FAIL** (after the ledger-row-5 correction of D2) |
| E — cost-aware ranking + abstention | 2 models × 4 hurdles | 0 | 0 | 2 | **FAIL** |

Grid-wide check (each family × H0–H3 hedge cell, at a given cost level):
- **C50:** 151 cells; none meets the PASS or WEAK rule. The only exception was D2 under H2, a fee artifact (ledger row 5).
- **C25:** no B, C or E cell is WEAK or better.
- **MID (mid fills plus commissions and fees):** no B, C or E cell is WEAK or better.

Conventions:
- Windows by exit month: DISCOVERY (DISC) 2014-02 … 2020-12; VALIDATION (VAL) 2021-01 … 2023-12. **FORWARD 2024-01 … 2026-09 was never computed for V2.** The runners hide it, and no candidate was frozen.
- Returns are per $ of long premium at mid per month, with equal premium per long position. NW(3) t in brackets.
- Cost levels:
  - GROSS = mid fills, no commissions, no hedge fees;
  - MID = mid fills plus all commissions and fees;
  - C50 = mid ± half the half-spread, the primary verdict level;
  - C100 = pay the full spread.
- Commissions: $0.70 per option contract per side.
- Stock hedging: $0.005/share with a $1 minimum per order, plus 2 bps slippage and 0.25% borrow.
- Research units are 1 contract per leg (see RETAIL_V2_COST_MODEL.md).

Code and outputs:
- Code: `src/v2_strategies.py`.
- Full grids (family × hedge × cost × window, with option / cost / hedge / hedge-cost / financing components): `results/v2/phase{B,C,D,E}/grid.csv`.
- Monthly series: `results/v2/phase{B,C,D,E}/monthly.csv`.

## Per-family tables

### Phase B — per-family verdict (hedge chosen in DISCOVERY at C50 by NW t)

| Family | Hedge | DISC C50 mean (t) | VAL C50 mean (t) | DISC GROSS mean (t) | VAL GROSS | DISC MID (t) | DISC C100 | worst DISC month C50 | cost / gross | positions | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|
| B1a_top10_long | H0 | +0.8% (+0.15) | -9.4% (-2.04) | +5.8% (+1.03) | -6.4% | +4.5% (+0.81) | -2.9% | -66.6% | 84% | 20.2 | **FAIL** |
| B1b_top20_long | H0 | +0.6% (+0.12) | -6.7% (-1.51) | +5.5% (+1.05) | -3.5% | +4.3% (+0.82) | -3.1% | -54.1% | 88% | 39.9 | **FAIL** |
| B1c_top10_long_BACK | H0 | +0.0% (+0.01) | -4.6% (-1.74) | +3.1% (+0.79) | -2.4% | +2.6% (+0.67) | -2.5% | -34.7% | 97% | 10.3 | **FAIL** |
| B1_LOUavg_long | H0 | +1.4% (+0.24) | -7.9% (-2.48) | +7.2% (+1.20) | -2.5% | +5.6% (+0.94) | -2.8% | -39.3% | 79% | 196.3 | **FAIL** |
| B1x_contrast_rankP_keepLOU_top10 | H0 | -0.2% (-0.05) | -7.1% (-1.49) | +4.6% (+0.84) | -3.9% | +3.4% (+0.62) | -3.9% | -55.1% | 104% | 30.8 | **FAIL** |
| B2_SPY_vega | H0 | -0.1% (-0.03) | -5.7% (-1.13) | +5.4% (+2.09) | -2.1% | +4.0% (+1.56) | -4.2% | -45.0% | 100% | 20.2 | **FAIL** |
| B2_SPY_gamma | H0 | +0.7% (+0.18) | -7.3% (-1.66) | +5.9% (+1.55) | -4.0% | +4.6% (+1.21) | -3.2% | -56.0% | 87% | 20.2 | **FAIL** |
| B2_SPY_premium | H0 | -3.6% (-0.47) | -1.7% (-0.16) | +2.8% (+0.37) | +2.8% | +1.2% (+0.15) | -8.4% | -407.5% | 224% | 20.2 | **FAIL** |
| B2_SPY_eqrisk | H0 | -1.4% (-0.52) | -5.5% (-0.90) | +4.3% (+1.62) | -1.8% | +2.9% (+1.07) | -5.6% | -71.6% | 130% | 20.2 | **FAIL** |
| B2_IWM_vega | H0 | +0.9% (+0.23) | -4.9% (-0.78) | +6.8% (+1.85) | -1.3% | +5.3% (+1.44) | -3.5% | -104.6% | 86% | 20.2 | **FAIL** |
| B2_IWM_gamma | H0 | +1.5% (+0.39) | -5.6% (-1.11) | +7.0% (+1.79) | -2.2% | +5.6% (+1.44) | -2.7% | -82.5% | 78% | 20.2 | **FAIL** |
| B2_IWM_premium | H0 | -2.1% (-0.23) | -3.4% (-0.30) | +4.7% (+0.52) | +0.8% | +3.0% (+0.33) | -7.2% | -562.3% | 142% | 20.2 | **FAIL** |
| B2_IWM_eqrisk | H0 | -0.6% (-0.19) | -6.4% (-1.07) | +5.3% (+1.58) | -2.8% | +3.8% (+1.14) | -5.0% | -106.6% | 111% | 20.2 | **FAIL** |
| B3_sector_vega | H0 | -3.0% (-1.40) | -9.1% (-1.99) | +4.3% (+2.06) | -4.4% | +2.5% (+1.15) | -8.5% | -59.5% | 167% | 20.2 | **FAIL** |
| B3_sector_gamma | H0 | -0.9% (-0.30) | -8.7% (-2.08) | +5.5% (+1.73) | -4.8% | +3.8% (+1.21) | -5.7% | -53.3% | 116% | 20.2 | **FAIL** |
| B3_sector_premium | H0 | -8.2% (-1.33) | -10.5% (-1.40) | +1.4% (+0.25) | -3.9% | -1.1% (-0.18) | -15.2% | -351.3% | 635% | 20.2 | **FAIL** |
| B3_sector_eqrisk | H0 | -3.7% (-1.69) | -9.9% (-2.04) | +3.6% (+1.69) | -5.1% | +1.7% (+0.81) | -9.0% | -61.6% | 198% | 20.2 | **FAIL** |
| B4_LOUavg_vega | H0 | -9.9% (-5.55) | -11.9% (-4.05) | -0.2% (-0.11) | -4.9% | -2.0% (-1.14) | -17.8% | -58.2% | n/a (gross ≤ 0) | 20.2 | **FAIL** |
| B5a_Q5_vs_Q4 | H0 | -11.6% (-6.01) | -10.3% (-4.00) | -2.4% (-1.20) | -3.8% | -4.2% (-2.15) | -19.0% | -105.4% | n/a (gross ≤ 0) | 39.6 | **FAIL** |
| B5b_Q5_vs_Q3 | H0 | -9.8% (-5.31) | -8.9% (-3.37) | -0.3% (-0.17) | -2.0% | -2.1% (-1.24) | -17.5% | -42.0% | n/a (gross ≤ 0) | 39.6 | **FAIL** |
| B5c_D10_vs_D5D6 | H0 | -9.1% (-4.25) | -11.8% (-3.90) | +0.2% (+0.11) | -5.2% | -1.6% (-0.76) | -16.6% | -58.3% | 3298% | 20.2 | **FAIL** |
| B5d_top5_vs_LOUavg | H0 | -8.7% (-3.70) | -11.2% (-3.36) | +0.9% (+0.37) | -4.3% | -1.0% (-0.42) | -16.4% | -63.9% | 1028% | 10.3 | **FAIL** |

### Phase C — per-family verdict (hedge chosen in DISCOVERY at C50 by NW t)

| Family | Hedge | DISC C50 mean (t) | VAL C50 mean (t) | DISC GROSS mean (t) | VAL GROSS | DISC MID (t) | DISC C100 | worst DISC month C50 | cost / gross | positions | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|
| C1_reverse_calendar_top10 | H0 | -5.2% (-2.25) | -9.7% (-4.57) | +2.9% (+1.17) | -3.3% | +1.2% (+0.46) | -11.5% | -44.9% | 274% | 7.3 | **FAIL** |
| C2_calendar_bottom10 | H0 | -8.7% (-2.47) | -4.0% (-1.39) | -1.8% (-0.54) | +2.0% | -2.9% (-0.88) | -14.5% | -187.8% | n/a (gross ≤ 0) | 6.2 | **FAIL** |
| C3_combined | H0 | -6.9% (-4.60) | -6.9% (-6.08) | +0.6% (+0.44) | -0.6% | -0.9% (-0.63) | -13.0% | -51.9% | 1243% | 13.4 | **FAIL** |
| C4_1to1_combined | H0 | -7.0% (-9.12) | -6.8% (-10.26) | +0.7% (+0.93) | -0.6% | -0.8% (-1.12) | -13.1% | -27.8% | 1123% | 13.4 | **FAIL** |
| C5_diagonal_combined | H0 | -10.9% (-3.37) | -9.2% (-3.29) | -0.7% (-0.22) | +0.4% | -2.9% (-0.96) | -18.9% | -96.7% | n/a (gross ≤ 0) | 11.3 | **FAIL** |

### Phase D — per-family verdict (hedge chosen in DISCOVERY at C50 by NW t)

| Family | Hedge | DISC C50 mean (t) | VAL C50 mean (t) | DISC GROSS mean (t) | VAL GROSS | DISC MID (t) | DISC C100 | worst DISC month C50 | cost / gross | positions | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|
| D1_LS_S_ew | H0 | -8.5% (-0.95) | -29.4% (-1.87) | +5.1% (+0.59) | -19.6% | +1.7% (+0.20) | -18.8% | -158.0% | 265% | 1.0 | **FAIL** |
| D1_L_top1_S_ew | H0 | +0.3% (+0.02) | -11.3% (-0.92) | +5.3% (+0.34) | -6.0% | +3.7% (+0.24) | -3.1% | -99.9% | 92% | 1.0 | **FAIL** |
| D1_2v2_S_ew | H0 | -11.7% (-1.89) | -15.2% (-1.45) | +0.1% (+0.02) | -6.2% | -3.4% (-0.56) | -20.1% | -216.8% | 7248% | 2.0 | **FAIL** |
| D2_slope_S_ew | H1 | +4.8% (+0.64) | -11.3% (-0.77) | +2.1% (+0.28) | -12.5% | +3.4% (+0.45) | +6.2% | -353.3% | n/a (slope) | 9.7 | **FAIL** |
| D1_LS_S_adv | H0 | -18.4% (-2.09) | -39.2% (-4.37) | -4.0% (-0.48) | -29.2% | -7.5% (-0.89) | -29.2% | -224.9% | n/a (gross ≤ 0) | 1.0 | **FAIL** |
| D1_L_top1_S_adv | H0 | +2.3% (+0.15) | -22.8% (-2.09) | +7.9% (+0.49) | -18.1% | +6.3% (+0.38) | -1.6% | -99.9% | 70% | 1.0 | **FAIL** |
| D1_2v2_S_adv | H0 | -7.2% (-1.32) | -27.9% (-3.90) | +5.6% (+1.03) | -19.1% | +2.3% (+0.42) | -16.6% | -106.5% | 226% | 2.0 | **FAIL** |
| D2_slope_S_adv | H1 | +8.1% (+1.45) | -19.2% (-1.70) | +3.8% (+0.72) | -21.4% | +5.8% (+1.06) | +10.4% | -111.0% | n/a (slope) | 9.7 | **FAIL** |
| D3_SPY_timing_long | H3 | -2.0% (-1.44) | -2.5% (-1.98) | -0.7% (-0.50) | -2.1% | -1.7% (-1.18) | -2.4% | -54.4% | n/a (gross ≤ 0) | 0.3 | **FAIL** |
| D3_SPY_always_long | H0 | +1.5% (+0.12) | -10.7% (-1.07) | +2.9% (+0.24) | -9.3% | +2.5% (+0.21) | +0.4% | -97.6% | 48% | 1.0 | **FAIL** |

### Phase E — cost-aware abstention (long FRONT ATM straddle, H1, C50; OOS 2017–2023)

| Rule | DISC (2017–20 OOS) mean (t) | VAL mean (t) | trades / month | flat months | worst DISC month |
|---|---|---|---|---|---|
| E1_k1.0 | -5.1% (-0.52) | -7.8% (-1.77) | 17.9 | 0% | -82.7% |
| E1_k1.5 | -2.6% (-0.25) | -6.4% (-1.38) | 14.2 | 0% | -82.7% |
| E1_k2.0 | -5.6% (-0.64) | -5.5% (-1.31) | 11.0 | 1% | -82.7% |
| E1_k3.0 | +0.2% (+0.02) | +3.5% (+0.53) | 5.8 | 11% | -98.9% |
| E2_k1.0 | +7.9% (+0.59) | -7.1% (-1.63) | 9.1 | 6% | -96.4% |
| E2_k1.5 | +5.7% (+0.42) | -7.4% (-1.91) | 6.9 | 10% | -95.6% |
| E2_k2.0 | +5.2% (+0.38) | -5.1% (-0.93) | 5.2 | 13% | -95.6% |
| E2_k3.0 | +6.3% (+0.44) | -3.7% (-0.47) | 3.2 | 17% | -80.5% |

Column notes:
- "cost / gross" = mean DISC (option cost + hedge cost) ÷ mean DISC gross (option + hedge) P&L, at the chosen hedge and C50.
- "positions" = average number of long positions per month.
- D2 is a monthly regression slope, not a portfolio. It is defined on H1 returns (charter); see ledger row 5.

## Daily hedging: a gross premium exists, but it is not the seasonal signal and the fees eat it

FRONT ATM straddles in LOU, H2 (daily delta hedge), DISCOVERY unless stated:

| Family (H2 = daily hedge) | GROSS DISC (t) | GROSS VAL (t) | MID DISC (t) | C50 DISC (t) | C50 VAL (t) | option cost / prem | hedge fees / prem |
|---|---|---|---|---|---|---|---|
| B1a_top10_long | +3.5% (+1.76) | -1.1% (-0.44) | -3.7% (-1.79) | -7.3% (-3.72) | -7.4% (-2.91) | 4.9% | 6.0% |
| B1_LOUavg_long | +2.4% (+1.35) | -0.3% (-0.14) | -5.8% (-3.20) | -10.0% (-5.84) | -9.9% (-4.59) | 5.8% | 6.7% |
| B2_SPY_vega | +5.4% (+3.66) | +1.6% (+0.86) | -4.2% (-2.78) | -8.4% (-5.71) | -6.4% (-3.38) | 5.5% | 8.3% |
| B2_IWM_vega | +6.5% (+3.61) | +3.2% (+1.40) | -4.4% (-2.30) | -8.8% (-4.74) | -5.4% (-2.27) | 5.9% | 9.3% |
| B3_sector_vega | +5.4% (+3.66) | +0.9% (+0.60) | -8.8% (-5.48) | -14.2% (-9.05) | -10.1% (-6.38) | 7.4% | 12.3% |
| B4_LOUavg_vega | +1.7% (+1.39) | -0.9% (-0.65) | -11.9% (-9.28) | -19.8% (-15.72) | -14.4% (-7.96) | 9.7% | 11.8% |
| B5b_Q5_vs_Q3 | +1.8% (+1.39) | +0.3% (+0.23) | -12.2% (-9.78) | -19.8% (-15.79) | -13.5% (-8.40) | 9.5% | 12.1% |

How to read this table:
1. **There is a gross premium, but it is not the seasonal signal.**
   - Hedged with daily delta hedging, a long single-name straddle book paired with a short index or sector straddle earns +5–7%/month at GROSS in DISCOVERY (t ≈ 3.6). In VALIDATION it falls to +1–3% (t < 1.5).
   - Decomposed in DISCOVERY at GROSS:
     - The *unranked* LOU-average long book, delta-hedged daily, already earns +2.4%.
     - The short index/sector straddle leg adds about +2% (B2_SPY_vega +5.4% vs B1a +3.5%).
     - The seasonal ranking adds about +1%: top decile vs LOU average, vega-neutral (B4), is +1.7% (t 1.4) in DISCOVERY and −0.9% in VALIDATION. The within-LOU relative books (B5) are similar.
   - So most of the gross premium is the well-known index-versus-single-name variance-premium spread (dispersion) plus the general delta-hedged single-name premium, not seasonal information.
2. **Commissions and hedge fees alone wipe it out, before any bid-ask cost** (MID column: −4% to −12%/month).
   - At retail size, daily hedging one straddle costs 6–12% of premium per month in stock fees, mostly the $1 per-order minimum on about 21 orders.
   - Option C50 costs add another 5–10%.
3. **Unhedged (H0)** the gross numbers look similar in DISCOVERY (B2_SPY_vega +5.4%, t 2.1) but are negative in VALIDATION at GROSS (−2.1%).

## Cost reference: LOU FRONT ATM straddle, one contract per leg (2014-02 … 2023-12, 29,724 name-months)

| Item | Median | IQR |
|---|---|---|
| Premium (mid) | $593 | $368 – $1,060 |
| Sum of the two legs' half-spreads | $15.0 | $8.5 – $27.5 |
| Quoted ATM relative spread (worse leg) | 6.1% | 3.8% – 8.1% |
| Smallest quoted size, ATM legs | 10 contracts | 3 – 25 |
| Round-trip option cost at C25 (spread + 4 × $0.70) / premium | 2.5% | 1.7% – 3.9% |
| Round-trip option cost at **C50** / premium | **4.1%** ($25.85) | 2.7% – 6.4% |
| Round-trip option cost at C100 / premium | 7.3% | 4.7% – 11.3% |
| Stock-hedge fees / premium: H1 (entry only) | 0.4% | 0.2% – 0.6% |
| Stock-hedge fees / premium: H3 (25-share threshold) | 1.7% | 1.1% – 2.6% |
| Stock-hedge fees / premium: H2 (daily) | 4.7% | 3.0% – 7.1% |

For comparison:
- The largest seasonal increment anywhere inside LOU is +3.8%/month gross, and only in DISCOVERY. It is the Q5−Q1 daily-hedged straddle spread from Phase A (VALIDATION −1.4%).
- Harvesting it needs two legs, so about 8% round-trip option cost at C50 plus hedge fees.

## Phase-specific notes

### Phase B
- **The re-ranked top decile is not better than the LOU average.** Unhedged at GROSS, B1a top decile = +5.8% vs LOU average +7.2% (DISCOVERY); both are negative in VALIDATION.
- **Contrast (rank in P, keep LOU):** no better (B1x: −0.2% at C50). "Rank everything, then drop illiquid names" doesn't help either.
- **Premium-neutral index hedges carry crash risk.** Worst DISCOVERY month −408% (SPY) and −562% (IWM) of long premium, in March 2020. These families also fail on mean.

### Phase C
- **Calendar spread has no gross content.** The calendar signal CS = S0(t+1) − S0₊₂(t+2) produces GROSS combined returns of +0.6% (t 0.4) to +0.7% (t 0.9) in DISCOVERY and −0.6% in VALIDATION.
- **Costs dominate.** Four legs per position: C50 −7%/month.
- **Diagonal (C5) is no better.**
- **Data:** BACK-leg units with an unquoted exit leg were dropped. 82 of 49,729 calendar units, counted in `results/v2/phaseC/extra.json`.

### Phase D
- **Sector compression has no out-of-sample content.** Tradable books (D1) never pass. D1 long top-1 sector is +0.3% at C50 in DISCOVERY and −11.3% in VALIDATION.
- **Market timing (D3) fails.** SPY timing: −2.0% at C50 in DISCOVERY, −2.5% in VALIDATION.
- **D2 is not a hidden PASS.** The D2 slope at H1 is +2.1% (t 0.28) GROSS in DISCOVERY and −12.5% in VALIDATION. The H2 "PASS" in the first verdict table was a fee artifact, described in ledger row 5.

### Phase E
- **No hurdle k ∈ {1, 1.5, 2, 3} produces a positive VALIDATION result with DISCOVERY t > 1.**
- **Pre-registered k per model** (best 2017–2020 OOS mean):
  - E1 cell model, k = 3: +0.2% (t 0.02) DISCOVERY, +3.5% (t 0.53) VALIDATION → FAIL.
  - E2 ridge, k = 1: +7.9% (t 0.59), then −7.1% (t −1.63) → FAIL.
- **Abstention trades rarely** (3–18 names/month; 0–17% of months flat). It still does not create an edge.
- **Ridge coefficients (DISCOVERY fit, z-scored features).**
  - The FRONT ATM spread dominates (−0.042 per SD).
  - Next come term slope (+0.023) and IV/HV (+0.021).
  - The S0 rank itself is small (+0.011), as is its interaction with spread (+0.016).

## Data-handling counts (FRONT/BACK straddles, 2014–2023)

| Item | Count |
|---|---|
| FRONT straddle units | 74,443 |
| Delisted before X with no exit quote (long valued at −100%, short dropped) | 68 |
| BACK straddle units | 50,391 |
| BACK units dropped (unquoted exit leg) | 19 long / 82 short |
| BACK units valued at −100% (delisted) | 63 |
