# RETAILIZATION V2 — CHARTER (pre-registration)

Written 2026-10-01, **before any V2 result was computed**. The git commit timestamp of this file is the evidence. Changes after results are seen go to `RETAIL_V2_RESEARCH_LEDGER.md`, marked **POST-HOC**.

## 0. Mission and principle

- Question: can the validated seasonal option signal be re-mapped into an exposure a $25,000 retail account can actually fill, carry and run? The paper portfolio itself is not being shrunk.
- Default stance: try to kill every family. A family survives only if it is positive at **C50** (half the half-spread given up) after commissions and hedging, with integer contracts, in discovery **and** in later windows.
- Allowed answer: **NO RETAILIZABLE EDGE FOUND**.

Facts taken as given (not re-tested): see the user brief §0. In short:
- the paper effect is real before costs;
- our PROXY replication has corr 0.78 with the authors' series;
- the effect is strong gross in 2021–26;
- it dies at C50;
- the paper portfolio needs about $1.5M;
- Q1 sits in illiquid names;
- V1 retail mappings (ATM straddle / strangle / iron fly / strangle spread on extreme pairs) failed.

## 1. Information source (the only allowed alpha)

| Code | Signal | Definition (all known at the formation close F) |
|---|---|---|
| **S0** | Paper seasonal score | Mean of the sorting-sample equity-VIX excess return at calendar-month lags 3, 6, 9, 12 relative to the target holding month (≥ 3 of 4 present). Identical to the validated paper rule. |
| **S0₊₂** | Same score for the following month | Lags 3, 6, 9, 12 relative to month t+2. Those returns ended at or before F−1 month, so they are known at F. Used only for term-structure (Phase C). |
| **S1** | Liquid-return variant | Same lags, computed from **holding-sample** returns (bid > 0) instead of the sorting sample. Diagnostic for the mid-price artifact (Q2) and an allowed alternative ranking. It is the same seasonal concept, not a new alpha. |
| **S_sec** | Sector compression of S0 | Per SPDR sector, the equal-weighted mean (primary) or ADV-weighted mean of constituents' S0 percentile in the full cross-section. Sector membership = the SPDR sector ETF with the highest 252-day daily-return correlation (point-in-time, as V1 PAIR2). |
| **S_mkt** | Market compression | Equal-weighted mean S0 percentile of all names, and the share of names in the top quintile. |

No other predictor may be used to select direction. Phase E features (spread, IV, RV, skew, term structure, size) may only **filter or scale** trades whose direction comes from S0/S1. Phase E also reports which features matter.

## 2. Data, timing, samples

- **Quotes.** OPRA consolidated NBBO (`cbbo-1m`) at **15:59 ET** on every formation date F (3rd Friday, previous session if a holiday), 2013-04 … 2026-09.
  - Entry: F 15:59.
  - Exit: X 15:59, where X = next formation date = expiry of the FRONT month.
- **Expiries.**
  - FRONT = next standard monthly, held to its expiry day X and closed at X 15:59 at quotes.
  - BACK = the monthly after that; held one month and closed at X 15:59 with about 4 weeks left.
  - Unquoted expiring legs on X (2025+ feed) use the V1 conservative rule: ITM at intrinsic ± max($0.05, 1%·intrinsic), OTM at 0/$0.05.
- **Stocks.** DoltHub raw closes (hedging, realised vol); dividend/split windows excluded; quote-based validation as in the panel.
- **Samples** (by exit month X):

| Window | Months | Use |
|---|---|---|
| **DISCOVERY** | 2014-02 … 2020-12 | All strategy-family choices and model fitting. |
| **VALIDATION** | 2021-01 … 2023-12 | Confirms the discovery choice; no re-selection. |
| **FORWARD** | 2024-01 … 2026-09 | Final evaluation of frozen rules only. Paper-level aggregate results for this window are already known, so it is *not* psychologically blind. Treat it as a forward test, never as a tuning set. |

  - Phase E models are fitted **walk-forward**: expanding window, refit each January, predicting the next year. 2014–2016 is the burn-in; out-of-sample predictions start in 2017.

## 3. Liquid Option Universe (LOU) — defined BEFORE ranking

LOU is point-in-time at F 15:59. The signal is **re-ranked inside LOU**: the percentile among LOU names with a score. This is a different experiment from "rank everything, then delete illiquid names", which is reported separately as a contrast.

| Rule | LOU (primary) | LOU-tight (kill 15) | LOU-loose (kill 16) |
|---|---|---|---|
| US common stock proxy, no div/split in (F, X], passes quote validation | ✔ | ✔ | ✔ |
| Stock price at F close | ≥ $20 | ≥ $20 | ≥ $10 |
| FRONT ATM call and put: bid > 0, (ask−bid)/mid | ≤ 10% each | ≤ 5% | ≤ 20% |
| BACK ATM call and put: bid > 0, (ask−bid)/mid | ≤ 10% each | ≤ 5% | ≤ 20% |
| 20-session ADV rank among names passing the quote screens | ≤ 500 | ≤ 250 | ≤ 1000 |

- ATM = the listed strike nearest the parity-implied forward (both C and P listed).
- ETF universe: SPY, QQQ, IWM, and the SPDR sectors XLB, XLE, XLF, XLI, XLK, XLP, XLU, XLV, XLY, XLRE (from 2015-10) and XLC (from 2018-06).

## 4. Execution / cost model (details in `RETAIL_V2_COST_MODEL.md`)

- Fill = mid ± e·half-spread per leg:
  - **MID** (e = 0): theoretical ceiling only.
  - **C25** (e = 0.25).
  - **C50** (e = 0.5): **the primary verdict level**.
  - **C100** (e = 1): crossed / immediately executable.
- Both entry and exit pay the cost.
- Options: $0.70 per contract all-in, $1.40 in the stress test.
- Stock/ETF hedges: $0.005/share (min $1 per order) plus 2 bps slippage, and 0.25%/yr borrow on short stock.
- A **passive-fill model is NOT used**. We have 1-minute NBBO snapshots only, with no trade or queue data. Fill probability and adverse selection therefore cannot be estimated, and assuming touch = fill is forbidden. This is reported as a limitation, not filled in with guesses.
- **Rule:** profitable at MID but ≤ 0 at C50 ⇒ **not retailizable**.

## 5. Hedge policies (fixed; no threshold mining)

| Policy | Rule |
|---|---|
| **H0** | No hedge. |
| **H1** | Delta-neutral at entry only, using stock/ETF, held to exit. |
| **H2** | Once-daily delta hedge at the close. Black-Scholes deltas with sticky entry IV; DoltHub close as the 15:45/16:00 proxy. |
| **H3** | Threshold: re-hedge at the close only when \|position delta\| > 25 shares per straddle-equivalent unit. **Single preset value.** |

P&L is always reported in four parts: option P&L, hedge P&L, transaction costs, total.

## 6. Phases, families and pre-registered variants

Unless stated otherwise, structures are **ATM straddles**, the selection set is **within LOU**, and weighting is **equal premium** per position. Returns are per $ of gross long premium, except where a section defines its own unit.

### PHASE A — Liquid-universe reconstruction + cost model + decomposition (Q1/Q2)

- **A0.** Build LOU and the per-leg table (FRONT/BACK: ATM C/P, 25Δ, 20Δ, 15Δ, 10Δ C/P), with entry/exit quotes and H1/H2 hedge P&L.
- **A1.** **Decomposition (Q1)**, Fama-MacBeth on the S0 rank with lag-1 and momentum-2-12 controls. Outcomes for the holding month:
  - log RV;
  - log IV (equity-VIX price and FRONT ATM IV);
  - VRP = log(RV/IV);
  - idiosyncratic RV (residuals on SPY, betas from the prior 252 days) vs systematic RV;
  - jump share (max squared daily return / RV);
  - skew (25Δ put IV − 25Δ call IV) level at F and its change to X;
  - liquidity (VIX_BA_percent, ATM spread).

  Run on the full P universe and inside LOU.
- **A2.** **Mid-artifact tests (Q2)**:
  - (i) seasonal × liquidity double sort (liquidity terciles by FRONT ATM spread), H−L at MID and at C50;
  - (ii) quarterly-specific component, {3,6,9,12} vs non-quarterly lags, inside each liquidity tercile;
  - (iii) S0 vs S1 (sorting- vs holding-sample formation);
  - (iv) persistence of the illiquid names' mid-return level at *all* lags (a level effect means artifact; quarterly-only means seasonality).
- **Verdict A:** PASS if the seasonal-specific (quarterly − non-quarterly) component is significantly positive (t > 2) **inside LOU** in DISCOVERY. Otherwise, mark the signal as mainly a mid/liquidity artifact; the later phases are then still run but expected to fail.

### PHASE B — Liquid long-vol + liquid hedge (no illiquid short leg)

- **B1 long-only:** long FRONT ATM straddles on the LOU top decile (B1a) and top quintile (B1b), held to X. **B1c** = the same with BACK straddles held one month.
- **B2 index hedge:** B1a + short SPY ATM straddle (B2-SPY) or IWM (B2-IWM), FRONT. Four sizings, each a separate pre-registered variant:
  - vega-neutral;
  - dollar-gamma-neutral;
  - premium-neutral;
  - equal-risk (hedge leg premium = ½ long premium).
- **B3 sector hedge:** B1a, with each name hedged by short ATM straddles on its sector-proxy ETF, using the same four sizings.
- **B4 universe hedge:** B1a vs short ATM straddles on the **LOU equal-weight average**, vega-neutral.
- **B5 single-name relative (direction 2, both legs in LOU):** each pair is long the first group and short the second, vega-neutral:
  - Q5 vs Q4;
  - Q5 vs Q3;
  - top decile vs the median deciles (5–6);
  - top 5% vs LOU average.
- **Contrast (not a candidate):** the same B1a computed on "rank in P, then keep LOU names".
- **Verdict B (per family, at C50, H policy chosen in DISCOVERY among H0–H3):**

| Verdict | DISCOVERY | VALIDATION |
|---|---|---|
| **PASS** | mean > 0 with NW(3) t > 2 | mean > 0 |
| **WEAK** | mean > 0, t in (1, 2] | mean > 0 |
| **FAIL** | anything else | — |

  The idiosyncratic-vs-market question (Q3) is read from B2/B3 vs B1.

### PHASE C — Same-name term structure

- Calendar signal **CS = S0(t+1) − S0₊₂(t+2)**, re-ranked within LOU names that have both scores.
- **C1 reverse calendar:** top decile of CS. Long FRONT ATM straddle, short BACK ATM straddle at the same strike, vega-neutral. Not defined-risk (flagged).
- **C2 calendar:** bottom decile of CS. Long BACK, short FRONT straddle, vega-neutral. Debit, defined risk.
- **C3 = C1 + C2 combined.**
- **C4 sizing variant:** 1:1 contracts instead of vega-neutral.
- **C5 diagonal:** same direction as C1/C2, but the BACK leg uses the 25Δ strangle.
- Hold to X. Both legs are the same ticker.
- "Target vs previous expiry" cannot be expressed with monthly-only data and is reported as not tested.
- Verdict rule as Phase B.

### PHASE D — Sector / ETF compression

- **D1:** monthly cross-section of 9–11 SPDR sector ETFs ranked by S_sec (EW primary, ADV-weighted secondary).
  - Long the FRONT ATM straddle of the top sector.
  - Short the bottom sector's straddle, vega-neutral (D1-LS).
  - Also long-only top-1 (D1-L).
  - Also top-2 vs bottom-2.
- **D2:** pooled panel regression of each ETF's straddle return (H1) on its S_sec rank.
- **D3 (market timing):** long SPY FRONT straddle when S_mkt is in the top tercile of its DISCOVERY distribution, else flat.
- Verdict rule as Phase B.

### PHASE E — Cost-aware ranking and abstention

- Target: long FRONT ATM straddle H1 return at C50 (net), for LOU names.
- **E1 cell model:** S0 decile × LOU spread tercile cell means.
- **E2 ridge:** ridge on pre-listed features:
  - S0 rank and S0 × spread;
  - S0 × log IV;
  - FRONT ATM spread;
  - log price, log ADV;
  - IV/HV21;
  - term slope (BACK − FRONT ATM IV);
  - 25Δ skew.

  α = 10 fixed (features z-scored per month).
- Both models are fitted walk-forward.
- Trade rule: long the straddle when predicted net edge > k × estimated round-trip C50 cost, for **k ∈ {1, 1.5, 2, 3}**. FLAT otherwise; abstention is allowed.
- Verdict rule as Phase B, on the k with the best DISCOVERY OOS (2017–2020) result. That k is then frozen.

### PHASE F — $25k integer-contract portfolio
Run only for families that are PASS or WEAK.
- Start: NAV $25,000.
- Per-ticker max theoretical loss: 2% / 4% / 8% tested.
- Caps:
  - total premium at risk ≤ 8% NAV;
  - \|portfolio delta\| ≤ 0.2 × NAV / S per name;
  - net vega ≤ $250 per vol point.
- Integer contracts only; commissions, fees, hedge costs and idle cash are all included.
- A month where the position cannot be built is recorded as **NO TRADE**.
- The candidate is frozen in `RETAIL_V2_FROZEN_CANDIDATE.json` **before** the FORWARD window is evaluated.

### PHASE G — Kill tests (on the frozen candidate)
1. spread ×1.25
2. spread ×1.5
3. commission ×2
4. entry delay (15:45 snapshot, 2019+)
5. exit early (X 15:00, 2019+)
6. one strike worse
7. remove best month
8. remove best year
9. remove top-5 P&L names
10. COVID removed
11. 2022 isolated
12. 2025 tariff shock (2025-03…2025-05) isolated
13. high-VIX regime
14. low-VIX regime (SPY 30-day IV above/below its DISCOVERY median)
15. LOU-tight
16. LOU-loose
17. capital $10k
18. capital $25k
19. capital $50k
20. block and stationary bootstrap CIs

Plus:
- full tail statistics;
- cost / gross-alpha ratio;
- turnover;
- a concentration audit (best month, best year, top-5 trades, top-5 tickers as shares of total profit).

## 7. Success criteria (all required for a candidate)
- Buildable at $25k with integer contracts.
- Positive expectancy at C50 after all costs. No dependence on MID, and no Q1 illiquid options.
- Same sign in DISCOVERY, VALIDATION and FORWARD.
- Not dominated by a few months.
- Reasonable drawdown.
- Costs < 50% of gross edge.
- Rules frozen before the FORWARD evaluation.

Simplicity and low turnover are preferred over in-sample Sharpe.

## 8. Phase verdicts stop families
A FAIL verdict ends work on that family: no further variants or parameter searches. If all families fail, the project ends with **NO RETAILIZABLE EDGE FOUND**.
