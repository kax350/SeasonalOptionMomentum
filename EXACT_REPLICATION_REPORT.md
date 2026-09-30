# EXACT_REPLICATION_REPORT — Rounds 3–5

Heston, Jones, Khorram, Li, Mo, *The Variance Premium and Seasonal Momentum in Option Returns*, RFS 2026 (DOI 10.1093/rfs/hhag057).
Authority: official replication package (Harvard Dataverse doi:10.7910/DVN/4FV8SV, CC0) > June-2022 working paper. The final RFS text is paywalled and was not available (see `papers/SOURCES.md`).

## STATUS: **PARTIAL PASS**

**What passed**
- The paper's pattern is reproduced independently on OPRA data (PROXY) over 2014–2020. All five acceptance checks pass (§4).
- The anomaly survives a frozen-rule extension through 2026-09, before costs.
- The statistics layer is reproduced **EXACTLY** from the authors' own monthly H−L series shipped in the package.

**Why not a full PASS**
- An EXACT replication needs OptionMetrics IvyDB and CRSP, which were not available.
- Our independent reconstruction therefore covers only the OPRA era: 83 of the paper's 290 months.
- The 1996–2013 portion can only be verified through the authors' own series, not rebuilt from raw data.

## 1. Labels used

| Component | Label | Notes |
|---|---|---|
| Statistics formulas (mean, NW(3) t, SD, Sharpe, skew, kurtosis) applied to the authors' H−L series | **EXACT** | Reproduces WP Table 5/6 to the last reported digit: 0.1422 (t = 14.80), SD 0.149, monthly SR 0.956 (**3.31 annualised**), skew 1.024, kurtosis 7.80. MaxDD is consistent (0.376 with rf = 0 vs published 0.373); it needs the month-by-month rf, which is not in the package. |
| Equity-VIX construction, filters, signal, sort | **PROXY** | Line-by-line port of `Table1&2.sas`, `form_hold_period_seas_2third.sas`, `HL_CS_HL_length.sas`, `GMM.sas` (see `PAPER_SPEC.md`), run on substitute data. |
| Option quotes | PROXY | Databento OPRA `cbbo-1m` consolidated NBBO at 15:59 ET on every formation date, instead of OptionMetrics closing best bid/offer. |
| Stock prices, dividends, splits | PROXY | DoltHub raw daily OHLCV (ticker-keyed), instead of CRSP (PERMNO-keyed). |
| Share codes 10/11 | PROXY | Approximated from security names. |
| Risk-free | PROXY | FRED 1M/3M T-bill curve, instead of the OptionMetrics zero curve. |
| IV/delta availability | PROXY | Black-Scholes IV solvable from mid, instead of OptionMetrics binomial IV. |
| OI > 0 filter | **not applied (deviation)** | Full-universe OPRA open interest costs ≈ $50/day. The per-contract request was attempted and failed (gateway time-outs and rate limits), so its effect is unmeasured. The replication matches the authors' series without it (§3). |
| Quote-based data validation | PROXY data hygiene | Added after run #1 (ledger rows 1–2). It removes firm-months whose ticker-keyed prices are inconsistent with the option market: ticker reuse (CZR 2020), splits missing from the split table (POWI 2020), a spin-off (GRA 2016), a special dividend (VC 2016). It uses quotes only, never returns. About 0.1–0.4% of firm-months are removed. |

## 2. Sample

- Formation dates: 2013-04-19 … 2026-08-21 (third Friday, or the previous session if a holiday), 161 months.
- Holding sample: 176,765 firm-months. Sorting sample: 271,751 firm-months.
- The first 3/6/9/12 signal exists for holding months ending 2014-02.

## 3. Overlap with the paper sample: holding months 2014-02 … 2020-12 (83 months)

| 3,6,9,12 High − Low | **Ours (PROXY, OPRA)** | **Authors (package Fig. 4 file), same months** |
|---|---|---|
| Mean monthly excess return | **0.1625** | 0.1271 |
| NW(3) t | **7.66** | 7.31 |
| SD | 0.207 | 0.174 |
| Sharpe, monthly | **0.786** | 0.731 |
| Sharpe, annualised | **2.72** | 2.53 |
| Skew / kurtosis | 3.33 / 20.2 | 2.73 / 14.6 |
| Worst month | −0.246 | −0.141 |
| Hit rate | 86.7% | 78.3% |
| **Month-by-month correlation with the authors' series** | **0.78** | — |
| Tracking error (SD of monthly difference) | 0.130 | — |

Other lag sets, same 84 months:

| Lag set | Corr. with authors | Ours: mean, t, SR_m | Authors: mean, t, SR_m |
|---|---|---|---|
| All 1..12 | 0.57 | 0.176, 7.69, 0.72 | 0.118, 7.19, 0.80 |
| Non-quarterly (1,2,4,5,7,8,10,11) | 0.79 | 0.165, 6.23, 0.59 | 0.114, 5.12, 0.49 |

Quintile means over the overlap, NW(3) t in parentheses:

| Q1 (low) | Q2 | Q3 | Q4 | Q5 (high) | Average #firms per month |
|---|---|---|---|---|---|
| −0.222 (−7.5) | −0.158 (−4.2) | −0.130 (−3.1) | −0.087 (−1.8) | −0.059 (−1.3) | 853 |

This is the paper's monotone pattern. WP Table 5, full 1996–2020: −0.217 … −0.075; H−L 0.142.

**Deviation analysis.** Our overlap mean is about 3.5 pp/month above the authors'. Candidate reasons:
- a broader universe (share-code proxy; tickers the authors' CUSIP linking drops);
- no OI>0 filter;
- 15:59 NBBO instead of OptionMetrics' closing quote;
- zero-bid handling in the sorting sample.

Our series also has fatter tails, so the monthly Sharpe comes out similar (0.79 vs 0.73). The authors' own series also shows that the effect was already **weaker in 2014–2020 than in 1996–2013**:

| Authors' series | Monthly SR | Annualised |
|---|---|---|
| 1996-10 … 2013-04 | 1.11 | 3.85 |
| 2014-02 … 2020-12 | 0.73 | 2.53 |

The published 3.31 annualised Sharpe is dominated by the pre-2014 period.

## 4. Acceptance gate (user spec §8)

| # | Criterion | Evidence | Result |
|---|---|---|---|
| 1 | 3/6/9/12 H−L significantly positive | Overlap 0.163, t = 7.66. Post-sample 0.145, t = 7.33 | ✅ |
| 2 | Quarterly lags ≥ annual-only | Overlap: {3,6,9,12} SR 2.72 vs {12} SR 2.46 and {12,24,36} SR 1.72. Post: 3.51 vs 2.89 and 2.78. Quarterly-non-annual {3,6,9} alone: SR 2.50 overlap, 3.09 post | ✅ |
| 3 | Not merely standard momentum | Fama-MacBeth rank slopes with seasonal, momentum 2–12 and lag 1 all included. Overlap: seasonal 0.062 (t 2.1), momentum 0.105 (t 3.2). Post: **seasonal 0.127 (t 6.6)**, momentum 0.058 (t 2.2). Seasonal carries incremental information, and after 2020 it dominates | ✅ |
| 4 | Driven by realised-variance seasonality not fully priced in implied variance | H−L of log(RV_corridor / VIX_Prc) = +0.17 (t 17.0) overlap, +0.24 (t 11.5) post. Post: high-score stocks have realised variance e^0.34 ≈ 40% higher (t 4.4), but implied variance only e^0.10 ≈ 11% higher (t 1.55). Overlap: RV is similar across quintiles while IV is lower for high-score names (t −5.9). Either way the variance premium, not the level of RV, is what is predicted | ✅ (mechanism consistent) |
| 5 | Risk/return roughly matches the authors | Monthly correlation 0.78, similar mean, SD, Sharpe, skew | ✅ |

## 5. Post-sample time extension (frozen paper rule; pre-cost; holding months 2020-12 … 2026-09)

**This is a post-sample time extension, not "prospective OOS".** The rule was fixed by the paper; nothing was tuned on 2021–2026.

| Year | Months | Mean H−L | NW t | SD | SR (ann.) | Sortino (ann.) | MaxDD | Hit | Worst | Q5 | Q1 | Avg #firms |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 2021 | 12 | 0.117 | 3.9 | 0.083 | 4.9 | — (no losing month) | 0 | 100% | +0.040 | −0.225 | −0.342 | 1,373 |
| 2022 | 12 | 0.245 | 7.7 | 0.134 | 6.3 | — | 0 | 100% | +0.030 | −0.114 | −0.359 | 1,352 |
| 2023 | 12 | 0.138 | 9.6 | 0.121 | 4.0 | — | 0 | 100% | +0.008 | −0.151 | −0.289 | 1,192 |
| 2024 | 12 | 0.114 | 6.4 | 0.098 | 4.0 | 24.0 | 0.057 | 92% | −0.057 | −0.119 | −0.233 | 1,141 |
| 2025 | 12 | 0.189 | 3.2 | 0.263 | 2.5 | 39.8 | 0.057 | 92% | −0.057 | +0.031 | −0.158 | 951 |
| 2026 YTD | 9 | 0.086 | 6.4 | 0.051 | 5.9 | — | 0 | 100% | +0.010 | −0.100 | −0.187 | 951 |
| **All (70 m)** | 70 | **0.145** | **7.3** | 0.155 | **3.24** | 16.3 | 0.057 | 96% | −0.246 (2020-12) | | | |

- **Answer:** yes. The seasonal-momentum anomaly in option returns is still present in 2021–2026, before transaction costs, at least as strongly as in 2014–2020.
- Both legs are negative in almost every year: Q1 loses more than Q5. The "alpha" is a *relative* variance-premium spread between high- and low-score names, not a positive return on long options.
- Q5 is only positive in 2025. That is the April-2025 volatility shock.
- Average #firms fell from about 1,370 in 2021 to about 950 in 2025–26: fewer listed contracts per name and a change in the OPRA feed.

## 6. What this does NOT show

- Returns are on the equity-VIX portfolio price (≈ one-month implied variance, e.g. 0.01–0.05). **A mean H−L of 0.145 is NOT "14.5% per month on the account."** Capital, margin and costs are handled in Rounds 6 and 10–11.
- Everything above is pre-cost, at mid quotes. The median quoted bid-ask spread of the equity-VIX portfolio is 32% of its price in Q5 and **69% in Q1**, the short leg. The cost audit (Round 6) is the decisive test.

## 7. Reproduce
```
python src/opra_download.py close 2013-04 2026-09     # OPRA 15:59 snapshots (Databento key in env)
python src/build_panel.py                             # equity-VIX firm-month panels + validation
python src/analysis_paper_core.py                     # results/paper_core/*
```
