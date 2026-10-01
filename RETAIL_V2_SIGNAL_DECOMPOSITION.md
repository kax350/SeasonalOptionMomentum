# RETAIL V2 — PHASE A: SIGNAL DECOMPOSITION (Q1, Q2)

**Verdict A: FAIL.**
- Inside the liquid option universe (LOU), the *seasonal-specific* part of the signal is zero. Quarterly lags minus non-quarterly lags = −1.2%/month, t = −0.28 (DISCOVERY).
- Inside liquid names the signal works only as generic option-return momentum. All lags 1–12 predict about equally, and S0 adds nothing once 2–12 momentum is controlled.
- The quarterly-specific component exists only in the most illiquid tercile, where no retail fill level preserves it.

Sources:
- Code: `src/v2_phaseA.py` (universe: `src/v2_universe.py`).
- Raw output: `results/v2/phaseA/phaseA.json` and `lou_hl_series.csv`.
- Ledger rows 2–4.

## 1. Setup

| Item | Value |
|---|---|
| P universe | Paper-panel firm-months with a holding-sample return (`vix_posoi`, equity-VIX return at mid). 79,142 firm-months in DISCOVERY. |
| LOU | Stock ≥ $20. FRONT ATM call and put bid > 0 and (ask−bid)/mid ≤ 10%. ADV rank ≤ 500. Point-in-time at F 15:59. |
| LOU size | Median 237 names/month; 223 with an S0 score; 93.5% also have a paper-panel return. |
| Signals | From past returns only (paper panel, keyed by root × month), on the full grid. |
| Windows (exit month) | DISCOVERY 2014-02 … 2020-12 (83 months); VALIDATION 2021-01 … 2023-12 (36 months). FORWARD not used. |
| Statistics | NW(3) t on monthly Fama-MacBeth slopes or H−L series. Ranks are centred (−0.5 … +0.5), so an FM slope equals the top-minus-bottom difference implied by a linear fit. |

## 2. The verdict test (inside LOU, re-ranked)

Q5 − Q1 portfolio return per month:

| Outcome | Signal | DISCOVERY | VALIDATION |
|---|---|---|---|
| `vix_posoi` (paper return, mid) | S0 (lags 3, 6, 9, 12) | +7.6% (t 2.89) | +6.4% (t 1.85) |
| | NonQ (lags 1, 2, 4, 5, 7, 8, 10, 11) | +8.7% (t 3.72) | +7.3% (t 2.56) |
| | **S0 − NonQ (verdict)** | **−1.2% (t −0.28)** | −0.9% (t −0.35) |
| FRONT ATM straddle, daily-hedged, mid, no fees | S0 | +3.8% (t 2.94) | −1.4% (t −0.80) |
| | NonQ | +0.5% (t 0.45) | −2.1% (t −1.08) |
| | S0 − NonQ | +3.3% (t 1.92) | +0.7% (t 0.59) |
| FRONT ATM straddle, long, H1, C50 (long-leg returns only) | S0 − NonQ | −4.0% (t −1.23) | −1.7% (t −0.51) |

Fama-MacBeth inside LOU, with S0 and NonQ ranks entered jointly, on `vix_posoi`:

| Rank | DISCOVERY | VALIDATION |
|---|---|---|
| S0 | −1.6% (t −0.41) | +8.2% (t 2.45) |
| NonQ | +9.8% (t 2.61) | +4.6% (t 1.93) |

With 2–12 momentum and lag-1 controls, the S0 slope on `vix_posoi` is −12.3% (t −1.92) in DISCOVERY and +1.4% (t 0.28) in VALIDATION. Momentum carries +19.3% (t 3.43).

## 3. Q1 — What does the seasonal score predict?

FM slope of each outcome on the centred S0 rank; DISCOVERY first, then VALIDATION. Positive = Q5 higher.

| Outcome (holding month) | P: DISC | P: VAL | LOU: DISC | LOU: VAL |
|---|---|---|---|---|
| Equity-VIX return `vix_posoi` (mid) | +0.159 (8.8) | +0.196 (8.3) | +0.082 (3.9) | +0.093 (3.0) |
| log corridor RV | −0.033 (−0.8) | +0.496 (3.1) | +0.330 (6.2) | +0.897 (4.9) |
| log equity-VIX price (implied) | **−0.247 (−6.6)** | +0.149 (1.1) | +0.212 (4.1) | +0.757 (4.8) |
| VRP = log RV − log implied | **+0.215 (19.0)** | **+0.344 (12.3)** | +0.124 (6.1) | +0.139 (4.2) |
| log RV, daily closes | +0.108 (2.1) | +0.707 (4.0) | +0.323 (5.9) | +0.893 (4.8) |
| log idiosyncratic RV (vs SPY) | +0.088 (1.6) | +0.669 (3.8) | +0.330 (5.0) | +0.868 (4.8) |
| log systematic RV | −0.008 (−0.1) | +0.876 (1.9) | +0.058 (0.3) | +0.925 (1.8) |
| Idiosyncratic share of RV | −0.006 (−0.9) | −0.031 (−1.7) | +0.008 (0.7) | −0.020 (−1.1) |
| Jump share (max r² / RV) | +0.005 (1.3) | −0.005 (−0.8) | +0.004 (0.9) | −0.002 (−0.2) |
| log FRONT ATM IV at F | −0.007 (−0.3) | +0.291 (3.5) | +0.117 (4.3) | +0.399 (4.8) |
| ATM VRP (log RV − log ATM IV²·T) | +0.128 (10.6) | +0.123 (5.3) | +0.094 (4.4) | +0.098 (3.2) |
| Change in ATM IV, F → X | −0.021 (−7.4) | −0.018 (−3.0) | −0.019 (−4.1) | −0.017 (−2.8) |
| 25Δ skew level at F (put − call IV) | +0.042 (6.4) | +0.111 (6.7) | +0.008 (4.5) | +0.036 (4.0) |
| Change in 25Δ skew, F → X | +0.007 (1.3) | +0.009 (1.3) | −0.000 (−0.1) | −0.000 (−0.0) |
| Equity-VIX bid-ask % | **−0.370 (−30.8)** | **−0.690 (−17.0)** | −0.073 (−20.1) | −0.168 (−12.1) |
| FRONT ATM relative spread | **−0.085 (−32.2)** | **−0.110 (−18.6)** | −0.017 (−16.8) | −0.034 (−13.0) |
| ATM straddle return, daily-hedged, mid, no fees | +0.023 (2.7) | −0.035 (−2.1) | +0.041 (3.4) | −0.000 (−0.0) |
| ATM straddle return, unhedged, mid, no fees | −0.018 (−0.8) | −0.024 (−0.5) | +0.006 (0.2) | +0.012 (0.3) |

**Answer to Q1:**
1. **Variance risk premium.** The score predicts a *less negative VRP*: realised variance relative to the implied price.
   - In the paper universe during DISCOVERY this comes from a **lower implied price** at formation (cheaper options). Realised variance is not higher.
   - Later, both RV and IV are higher for high-score names.
2. **Not the other channels.** It does **not** predict:
   - jumps;
   - skew changes;
   - the idiosyncratic share of variance.

   The RV that it does predict is idiosyncratic.
3. **Liquidity.** It is very strongly a **liquidity** variable: high-score names have much tighter option spreads (t ≈ −31).
4. **Within liquid names.** The score is a level/persistence variable. High-score names have higher RV and higher IV, and IV falls into expiry. The tradable instrument, an ATM straddle at mid, earns nothing unhedged. Daily-hedged, it earns a DISCOVERY-only premium that vanishes in VALIDATION.

## 4. Q2 — Why is the effect strongest in illiquid names?

**Liquidity terciles.** Within each month, terciles of FRONT ATM relative spread across the P universe.
- Names absent from the V2 table count as most illiquid. They either failed the 25% ATM-spread pre-screen or have no FRONT chain.
- Median spread by tercile: liquid 7.6%, middle 17.5%, illiquid 23.7% (among names with a quote).
- 97% of illiquid-tercile names are absent from the V2 table.

| Test | Liquid | Middle | Illiquid |
|---|---|---|---|
| (i) S0 Q5−Q1 at MID, DISC | +9.1% (t 4.8) | +6.4% (t 2.4) | **+15.5% (t 6.4)** |
| (i) S0 Q5−Q1 at MID, VAL | +6.5% (t 2.4) | +10.4% (t 6.2) | +13.3% (t 6.9) |
| (i) Executable, paper construction: long Q5 and short Q1 at C50, DISC | −4.9% (t −2.2) | −15.6% (t −4.9) | **−16.0% (t −7.9)** |
| (i) Same, VAL | −6.6% (t −2.9) | −16.8% (t −10.6) | −21.3% (t −13.4) |
| (ii) NonQ Q5−Q1 at MID, DISC | +11.5% (t 4.8) | +7.5% (t 3.8) | +11.8% (t 3.7) |
| (ii) FM joint, DISC: S0 slope / NonQ slope | +0.041 (1.5) / **+0.114 (3.5)** | +0.043 (1.4) / +0.053 (1.9) | **+0.149 (6.8)** / +0.020 (0.9) |
| (ii) FM joint, VAL: S0 slope / NonQ slope | +0.100 (3.8) / +0.029 (1.2) | +0.113 (6.6) / +0.027 (1.1) | +0.144 (5.8) / +0.055 (2.0) |
| (iii) S1 (holding-sample formation) Q5−Q1 at MID, DISC | +4.1% (t 1.4) | +6.6% (t 2.2) | +12.3% (t 2.6) |
| (iii) S1, VAL | +10.4% (t 6.1) | +11.6% (t 5.7) | +16.3% (t 8.6) |

**(iv) Persistence by lag.** DISCOVERY FM slope of `vix_posoi(m)` on the within-tercile rank of the sort-sample return at lag L. Quarterly lags are in bold.

| Lag | Liquid | Middle | Illiquid |
|---|---|---|---|
| 1 | +0.045 (1.8) | +0.043 (3.2) | +0.102 (6.7) |
| 2 | +0.086 (4.0) | +0.061 (3.2) | +0.110 (6.7) |
| **3** | +0.076 (5.4) | +0.068 (3.8) | **+0.143 (7.6)** |
| 4 | +0.088 (5.9) | +0.078 (4.4) | +0.085 (5.4) |
| 5 | +0.095 (5.6) | +0.064 (3.9) | +0.121 (7.6) |
| **6** | +0.071 (5.2) | +0.080 (5.1) | **+0.128 (7.3)** |
| 7 | +0.067 (3.4) | +0.044 (2.7) | +0.102 (6.1) |
| 8 | +0.099 (4.4) | +0.065 (3.6) | +0.085 (4.3) |
| **9** | +0.076 (4.9) | +0.037 (2.2) | +0.091 (6.6) |
| 10 | +0.093 (4.5) | +0.072 (3.8) | +0.071 (4.6) |
| 11 | +0.064 (2.5) | +0.044 (2.6) | +0.071 (4.2) |
| **12** | +0.059 (4.1) | +0.081 (3.9) | **+0.127 (7.7)** |

**(v) Listing-cycle control.** S0 Q5−Q1 at MID, DISCOVERY, split by whether the m+2 monthly is already listed at F.

| Universe | m+2 listed | m+2 not listed |
|---|---|---|
| P | +11.5% (t 5.4) | +7.6% (t 3.9) |
| LOU | +8.4% (t 2.2) | +3.4% (t 0.9) |

In VALIDATION almost every LOU name has m+2 listed.

**Where the paper's extreme quintiles live.** Full-universe S0 quintiles:

| Quintile | Q1 | Q2 | Q3 | Q4 | Q5 |
|---|---|---|---|---|---|
| Share inside LOU | 3% | 10% | 21% | 35% | 49% |
| Median FRONT ATM spread | 16.9% | 14.9% | 12.5% | 10.3% | 7.8% |
| Not in the V2 table (ATM spread > 25% or no chain) | 69% | 51% | 36% | 24% | 17% |

**Answer to Q2:**
1. **All-lag persistence.** Every option-return series shows strong persistence at *all* lags. This level effect is strongest in the illiquid tercile, where mid prices of wide markets carry a persistent name-specific component.
2. **Quarterly component only in illiquid names.** The quarterly-specific component appears only in the illiquid tercile. There, lags 3, 6 and 12 stand out and S0 beats NonQ (t 6.8 vs 0.9). In the liquid tercile the lag profile is flat and NonQ beats S0.
3. **Not a formation-noise artifact.** The illiquid-tercile effect survives a change of formation sample (S1, t 2.6 / 8.6). Pure measurement noise in the *formation* return does not explain it.
4. **Inseparable from the quote structure.**
   - It is strongest where option chains are widest, and S0 itself is a strong spread predictor.
   - It is stronger when the m+2 monthly is already listed. Listing cycles repeat every three months, which is exactly the periodicity of the signal.
   - Every executable version loses −16% to −21% per month in that tercile.
5. **Classification: real at mid, not harvestable.** We cannot prove that it is a pure mid-price artifact. It may be compensation for providing liquidity in thin, quarterly-cycle option chains. What we can show is that its *seasonal* part does not exist where a retail account can trade. Its non-seasonal part in liquid names is too small relative to the spread (see RETAIL_V2_RESULTS.md).

## 5. What Phase A implies for later phases

Charter: "Otherwise, mark the signal as mainly a mid/liquidity artifact; the later phases are then still run but expected to fail". Phases B–E were run as pre-registered, and all failed (RETAIL_V2_RESULTS.md).

## 6. Caveats

- The liquidity terciles use the V2 FRONT ATM spread at F 15:59. The illiquid tercile is mostly names with no V2 record, so its straddle-level outcomes cannot be measured. Only the paper-construction (equity-VIX) results are available there.
- Our panel is a PROXY of the authors' (correlation 0.78 on overlapping months). Inside LOU, 93.5% of names have a panel return.
- Skew needs both 25Δ legs within ±0.05 delta, so skew results use a smaller sample.
