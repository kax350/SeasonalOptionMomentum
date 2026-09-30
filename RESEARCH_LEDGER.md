# RESEARCH LEDGER — Seasonal Momentum in Option Returns (HJKLM, RFS 2026)

Anti-overfitting ledger. Every experiment, parameter, the time it was first defined, and whether
any holdout data had been seen at that time. **Entries in Section A were written on 2026-09-30
before any return, Sharpe, or P&L number of any strategy (paper-core or retail) was computed.**
Nothing may be edited in Section A after results are seen; changes create a new versioned entry
in Section C.

Labels: **EXACT** = paper data + paper rule (impossible here: no OptionMetrics/CRSP access) ·
**PROXY** = paper rule re-implemented on substitute data (OPRA NBBO, DoltHub prices) or a
paper-faithful approximation · **ADAPTATION** = deliberate change for a $25k manual account.

---------------------------------------------------------------------------------------------
## A. PRE-REGISTRATION (frozen 2026-09-30, before any results)

### A1. Data (all PROXY for OptionMetrics/CRSP)
| Item | Choice |
|---|---|
| Option quotes at formation | Databento OPRA.PILLAR `cbbo-1m`, consolidated NBBO as of 15:59:00 ET (1 min before close; early-close days: 1 min before early close) on each formation date |
| Intraday entry snapshots (retail) | `cbbo-1m` at 15:30, 15:45, 15:55 ET on formation dates (liquid universe only) |
| Open interest | OPRA `statistics` stat_type 9 (published ~06:30 ET = prior-close OI). Full-universe OI is too costly; OI>0 filter is **measured on a sample of dates** and applied only if it changes firm-month returns materially (decision rule: if corr(ret with OI filter, ret without) ≥ 0.98 and mean abs diff < 1% of VIX price, run without OI and document as PROXY deviation). |
| Underlying prices, dividends, splits | DoltHub `post-no-preference/stocks` raw daily OHLCV (2011+), dividends by ex-date, splits by ex-date (2014-03+; earlier splits by price-ratio detector) |
| Share codes 10/11 | proxy: Nasdaq security name contains "Common Stock"/"Capital Stock", not ETF/ADR/fund/preferred/units/trust/ordinary shares/REIT-name; unknown-metadata tickers included (sensitivity: excluded) |
| Risk-free | FRED DGS1MO/DGS3MO, interpolated at option horizon, converted to continuous |
| Sample | formation dates 2013-04-19 … 2026-08-21 (last holding period ends 2026-09-18) |

### A2. Paper-core rule (frozen = replication code; see PAPER_SPEC.md)
* Monthly return per firm = Dynamic_VIX_Return_Corridor − rf (Simpson equity-VIX portfolio, OTM puts+calls on next-month standard expiry, bought at mid on formation date, held to expiry, model-free corridor hedge daily at close).
* Formation variable from the **sorting sample** (keeps OI=0 / bid=0 options); holding variable from the **holding sample** (bid>0, [OI>0]).
* SeasonalScore = mean of returns at lags 3, 6, 9, 12 months; require ≥ 3 of 4 non-missing (code: n ≥ ceil((4)·2/3) → n ≥ 3). Lag 1 never used.
* Quintiles each month (PROC RANK groups=5, ties=low), equal-weighted, H−L = Q5 − Q1.
* Stats: mean, Newey-West(3) t, SD, monthly and annualised Sharpe (×√12), skew, kurtosis, MaxDD as in Table5_Seasonal.sas.
* Periods: PAPER-OVERLAP = holding months ending 2014-01 … 2020-11 (paper sample ends 2020-11); POST-SAMPLE = 2020-12 … 2026-09 (reported by calendar year; 2026 YTD).

### A3. Transaction-cost levels (paper-level H−L on equity-VIX portfolios)
Options bought (long leg) at P_buy = mid + e·(ask − bid)/2 and sold (short leg) at P_sell = mid − e·(ask − bid)/2, where e is the effective-to-quoted spread ratio (Goyal–Saretto 2009 convention):
* COST0 e = 0 (paper midpoint) · COST1 e = 0.25 · COST2 e = 0.50 · COST3 e = 1.00 (natural: buy ask / sell bid) · COST4 natural ± 1 tick (tick = $0.01 if price < $3 else $0.05; never below 0 when selling).
  (Clarified 2026-09-30 before any result: "25%/50% of spread adverse" = 25%/50% of the way from mid to natural.)
* Options held to expiration → no option exit cost at paper level (payoff at intrinsic, as in paper). Retail: explicit exit (see A6).
* Stock hedge: every daily rebalance of the model-free corridor hedge charged 2 bps of traded notional (institutional) and, for retail, IBKR fixed $0.005/share (min $1/order) + 2 bps slippage.
* Options commissions: $0.65/contract IBKR + $0.05 exchange/ORF/OCC ≈ **$0.70/contract all-in**; stress = $1.40.
* Short-stock borrow: 0.25%/yr general collateral on short hedge notional (stress 2%).

### A4. Concentration (EXTREME-RANK COMPRESSION), frozen versions
A: top10/bottom10 · B: 5/5 · C: 3/3 · D: 2/2 · E: 1/1, ranks from the full eligible cross-section each month (score ties broken by ticker alphabetically). Also report the full quintile (≈ 1/5 of universe) and "20/20".
Reported diagnostics: percentile of selected names, score spread (mean top − mean bottom), rank dispersion.
**SKIP-MONTH rule:** skip when (mean score of top-K − mean score of bottom-K) is below the **20th percentile** of that spread's distribution over PAPER-OVERLAP months (2014-01…2020-11) for the same K and universe. Threshold computed once on training months; never re-estimated.

### A5. Universes (point-in-time, formation-date information only)
* **P** = paper full eligible universe (holding sample rules).
* **L** (liquid-options universe) = P ∩ {St_start ≥ $20} ∩ {K0 put and K1 call: bid > 0 and (ask−bid)/mid ≤ 10% at the 15:59 snapshot} ∩ {≥ 8 OTM strikes with bid > 0} ∩ {top 500 by 20-day average dollar volume (close×volume) among eligible stocks}.
* **L-tight** (kill test 19): same but spread ≤ 5% and top 250 by dollar volume.

### A6. Retail instruments (next-month standard expiration, same as paper)
Strikes chosen from quotes at entry: ATM = listed strike minimising |K − Forward|; Δ-targets use Black-Scholes delta from mid IV at entry, strike with delta closest to target.
* **PROXY A** ATM straddle; high score → long, low score → short (short = research only). Unhedged.
* **PROXY B** = A with daily delta hedge (H1).
* **PROXY C** 25Δ strangle (put Δ≈−0.25, call Δ≈+0.25); high long / low short (research only).
* **PROXY D10 / D15** iron fly: ATM straddle ± wings at 10Δ / 15Δ. High → LONG iron fly (buy ATM C+P, sell wings; max loss = debit). Low → SHORT iron fly (sell ATM C+P, buy wings; max loss = max wing width − credit).
* **PROXY E** strangle spread: high → long 25Δ strangle, short 10Δ strangle; low → reverse. Max loss defined.
* Entry: formation date at **15:45 ET (headline)**; 15:30, 15:55 and 15:59 (paper-close) are pre-declared sensitivities.
* Exit: all legs closed on the expiration day (= next formation date) at **15:00 ET** at quotes of that minute (never held into expiration/assignment); sensitivity: exit previous session 15:45 ET.
* Combo pricing: combo mid = Σ signed leg mids; combo natural = Σ signed natural leg prices; cost ladder COST0–COST3 applied at combo level with the same e (fill = combo mid ± e·(combo natural − combo mid)); stress = combo natural worse by $0.01 per combo (complex-order tick).

### A7. Hedge policies (retail)
* **H0** no hedge. **H1** once-daily hedge at 15:45 ET (daily close used as proxy where intraday stock data not pulled; 15:45 verified for the final candidate). **H2** threshold: hedge only when |net delta of a position| > 0.15 (or 0.25) × 100 shares per structure unit, checked daily.
* Deployment preference (frozen): H0 if its DEVELOPMENT-window after-cost Sharpe (COST = combo mid + 50% spread, $0.70/contract) is > 0.5; else H1; H2 only if both fail.

### A8. $25k sizing
* NAV $25,000; risk budgets CONSERVATIVE 4% ($1,000), MODERATE 8% ($2,000), AGGRESSIVE-RESEARCH 12% ($3,000) = sum of max theoretical losses; per-ticker max theoretical loss ≤ 2% NAV ($500).
* Budget split equally across selected positions; qty = floor(min(budget/N, $500) / maxloss_per_unit); qty = 0 ⇒ position skipped (counted and reported).
* No naked short options live. Integer contracts only; report integer-discretisation error vs fractional.
* Total option contracts across all legs ≤ 24 (manual-execution cap).

### A9. Pairs and vega matching
* **PAIR1** simple: k-th highest vs k-th lowest in the universe.
* **PAIR2** within-sector: sector proxy = the SPDR sector ETF (XLB, XLE, XLF, XLI, XLK, XLP, XLU, XLV, XLY, XLRE from 2015-10, XLC from 2018-06) with the highest correlation of daily returns over the prior 252 sessions (point-in-time). Within each sector pick highest vs lowest score; choose the K sectors with the widest within-sector score spread; skip if fewer than K sectors have ≥ 5 eligible names.
* **EQUAL-CONTRACT** vs **VEGA-MATCHED** (low-side quantity scaled so |vega_long| ≈ |vega_short|, integer rounding, error reported).

### A10. Windows for the retail adaptation (frozen)
* DEVELOPMENT 2021-01 … 2023-12 (holding months): selection among the pre-defined proxies only, by the hierarchy in A11.
* HOLDOUT 2024-01 … 2025-12: frozen, no modification.
* EXTERNAL 2026-01 … 2026-09: frozen.
* Paper-overlap months (2014–2020) may be used for thresholds (skip rule) and for reporting, not for choosing the retail structure.

### A11. Live-candidate selection hierarchy (frozen)
1. Executable inside the chosen risk budget (4% preferred, 8% allowed) with integer contracts in ≥ 80% of DEVELOPMENT months.
2. Defined risk only (D10, D15, E, long-only straddle).
3. Universe L.
4. ≥ 2 long + ≥ 2 short positions preferred to 1+1 → K = 3 if total contracts ≤ 24 and budget allows, else K = 2, else K = 1.
5. ≤ 24 option contracts total.
6. Hedge policy per A7 (no intraday hedging ever).
7. Among structures surviving 1–6: highest DEVELOPMENT after-cost Sharpe (combo mid + 50% spread, $0.70/contract); ties → fewer legs. PAIR1 vs PAIR2 and EQUAL vs VEGA are chosen by the same rule.
Everything is then frozen for HOLDOUT/EXTERNAL.

### A12. Benchmarks (same instrument / universe / sizing as the candidate)
B1 T-bills · B2 SPY buy-and-hold · B3 EW long vol (long structure on all of L) · B4 EW short defined-risk vol (short structure on all of L) · B5 random high/low assignment (1,000 draws) · B6 standard option momentum (mean of lags 2–12, ≥ 2/3 non-missing) · B7 HV−IV (Goyal-Saretto: log(HV_252d / IV_ATM)) · B8 seasonal 3/6/9/12.

### A13. PASS criteria (user spec §29, unchanged)
HOLDOUT+EXTERNAL (2024-01 … 2026-09) after-cost Sharpe > 1.0; ≥ 2 of {2024, 2025, 2026 YTD} positive; MaxDD < 12%; worst month > −6%; total defined max risk ≤ budget; natural-fill expectancy > 0; natural + 1 tick not destroyed; remove-best-3-months cumulative > 0; bootstrap support. Sharpe 0.5–1.0 with good risk = WEAK PASS; after-cost ≤ 0 = FAIL.

---------------------------------------------------------------------------------------------
## B. EXPERIMENT LOG (append-only)

| # | Date | Experiment | Label | Parameters | Holdout seen? | Result |
|---|---|---|---|---|---|---|
| 0 | 2026-09-30 | Data acquisition & pipeline smoke test (2024-01-19 only: count of firm-months, VIX bid-ask %) | PROXY | — | No returns examined beyond pipeline sanity | 1,449 hold / 2,055 sort firm-months; VIX_BA_percent mean 0.54 |

---------------------------------------------------------------------------------------------
## C. VERSIONED CHANGES (after results)
(none yet)
