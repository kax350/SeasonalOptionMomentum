# RETAILIZATION V2 — FINAL REPORT

## Verdict: **NO RETAILIZABLE EDGE FOUND**

The seasonal option-return signal of Heston, Jones, Khorram, Li and Mo (RFS 2026) is real in the paper's construction at mid prices. It cannot be re-mapped into anything a $25,000 retail account can fill, carry and run at a profit.

Tested, all **pre-registered**:
- liquid single-name long volatility, with index, sector, universe and relative hedges (Phase B);
- same-name term structure (Phase C);
- sector, ETF and market compression (Phase D);
- cost-aware ranking with abstention (Phase E).

Every one of them **fails at C50**, the primary execution level (mid ± half of the half-spread):
- 39 families and 151 family × hedge cells;
- discovery 2014–2020, validation 2021–2023.

Most fail before any spread is paid:
- 22 families fail even at mid with no costs;
- 15 fail from commissions and hedge fees alone.

Phase A explains why. Inside the liquid option universe the *seasonal* part of the signal is **zero**: quarterly minus non-quarterly lags = −1.2%/month, t −0.28. What remains is generic option-return persistence, and that is much smaller than the spread.

Consequences of having no candidate:
- No candidate was frozen; `RETAIL_V2_FROZEN_CANDIDATE.json` does not exist.
- No $25k portfolio was simulated (Phase F).
- The 20 kill tests have no object (Phase G).
- The 2024–2026 FORWARD window was never used for V2.

This matches the earlier V1 result (V1_RETAIL_VERDICT.md: FAIL out of sample and in every kill test).

---

## 1. What to buy each month

**Nothing.** Every month is **NO TRADE** (100% of months).

No structure tested here has positive expected value after realistic retail costs:
- straddles, strangles, calendars, diagonals;
- index- or sector-hedged books;
- abstention filters.

## 2. Why: answers to the three questions

### Q1 — What does the signal predict? (RETAIL_V2_SIGNAL_DECOMPOSITION.md §3)

1. **A less negative variance risk premium.** That is realised variance relative to the option-implied price.
   - In the full paper universe, discovery period, it works mainly through **cheaper implied prices at formation**, not higher realised variance. FM slope on log implied price −0.25 (t −6.6); on log corridor RV −0.03 (t −0.8); on VRP +0.21 (t 19).
   - The realised variance it does predict is idiosyncratic.
2. **Not jumps, skew changes or the idiosyncratic share.** It does not predict jumps (t 1.3), changes in skew (t 1.3) or the idiosyncratic share of variance (t −0.9).
3. **Mainly a liquidity variable.** High-score names have far tighter option spreads (FM t ≈ −31 on the ATM spread and the portfolio bid-ask %).
4. **Inside liquid names it is a level/persistence variable.** High-score names have higher RV *and* higher IV, and IV falls into expiry.
   - With 2–12-month momentum controlled, the seasonal rank adds nothing (t −1.9 in DISCOVERY).
   - The tradable ATM straddle at mid earns nothing unhedged.

### Q2 — Why is it strongest in illiquid names? (§4)

- **The quarterly lag pattern is an illiquid-name phenomenon.**
  - In the most illiquid spread tercile, lags 3, 6 and 12 stand out, and the seasonal score beats non-seasonal lags (t 6.8 vs 0.9).
  - In the liquid tercile the lag profile is flat, and non-seasonal lags beat the seasonal score (t 3.5 vs 1.5).
- **Economic or artifact?**
  - It survives a change of formation sample (S1, t 2.6 / 8.6), so it is not just noise in the formation return.
  - But it lives where chains are widest, rides on a variable that predicts spreads, and is stronger when the m+2 monthly is already listed. Listing cycles repeat every three months, exactly the signal's periodicity.
  - Every executable version loses 16–21% per month in that tercile (C50).
- **Our classification: real at mid, not harvestable.** It is a property of mid prices in thin, quarterly-cycle option chains. That could be a liquidity premium, not necessarily a measurement error. Either way it does not exist where a retail account can trade.

### Q3 — Can the information be moved to liquid securities? **No.**

| Route | Best evidence | Result |
|---|---|---|
| Re-rank inside liquid names (LOU) | Seasonal-specific H−L at mid −1.2% (t −0.28); top decile not better than LOU average | No information left |
| Liquid long vol with index or sector hedges (B2/B3) | Daily-hedged GROSS +5–7%/month in DISCOVERY, but mostly the index-vs-single-name variance spread. The seasonal increment (B4) is +1.7% (t 1.4), negative in VALIDATION. | Dies at MID from fees; at C50 −8% to −14%/month |
| Same-name calendars (C) | GROSS +0.6% to +0.7% (t < 1) | Dies at C50: −7%/month |
| Sector ETF straddles ranked by aggregated scores (D1/D2) | GROSS slope +2.1% (t 0.28) DISCOVERY, −12.5% VALIDATION | No information |
| SPY market timing (D3) | GROSS −0.7% | No information |
| Cost-aware abstention (E) | Best OOS rules: t 0.02 and 0.59 in DISCOVERY; VALIDATION +3.5% (t 0.53) and −7.1% | Spread is the dominant ridge feature; the seasonal rank is minor |

## 3. Cost per contract (LOU FRONT ATM straddle, 2014–2023, one call + one put)

| Item | Median |
|---|---|
| Premium | $593 (IQR $368–$1,060) |
| Quoted ATM spread (worse leg) | 6.1% of mid |
| Smallest quoted size | 10 contracts |
| Round-trip option cost at C50 (spread + 4 × $0.70) | **$25.85 = 4.1% of premium** |
| Same at C25 / C100 | 2.5% / 7.3% of premium |

Delta-hedging fees for one straddle at $0.005/share with a $1 minimum per order:

| Hedge policy | Fees as % of premium |
|---|---|
| Entry only (H1) | 0.4% |
| 25-share threshold (H3) | 1.7% |
| Daily (H2) | 4.7% |

Any long/short book doubles the option cost, to about 8% of premium per month at C50.

## 4. Sizing at $25k (why integer constraints make it worse)

- **Few positions fit.** The charter caps total premium at risk at 8% of NAV ($2,000). With a median straddle premium of $593, that is about 3 straddles per month.
  - Per-ticker max-loss limits of 2% / 4% / 8% ($500 / $1,000 / $2,000) allow 0 / 1 / 3 median straddles.
  - The 20-name top-decile book (B1a) would need about $12,000 of premium: 48% of NAV, six times the cap.
- **Fixed fees bite at this size.** At 1–3 contracts per name, the $1-per-order stock-hedge minimum and the per-contract option fees cannot be amortised. Daily hedging alone costs 5–12% of premium per month.
- **No sizing changes the sign.** The edge is negative before sizing, at C50 and in most cases at mid.

## 5. Worst loss (C50, DISCOVERY, per $ of long premium)

| Structure | Worst month |
|---|---|
| Top-decile long straddles (B1a) | −67% |
| Abstention rule (E2) | −96% |
| Long top-1 sector ETF straddle (D1-L) | −100% |
| Premium-neutral index-hedged books (B2) | −408% (SPY) / −562% (IWM), March 2020 |

Unhedged long straddles can lose all their premium in a month. Short index legs can lose several times the long premium.

## 6. Fill assumptions

- **Quotes.** OPRA consolidated NBBO (Databento `cbbo-1m`) at 15:59 ET.
  - Entry: the third Friday, F.
  - Exit: the next third Friday, X. The FRONT leg is closed at its expiry-day 15:59 quote, not exercised.
- **Fill prices.** C50 = mid ± ½ × half-spread on every leg, at entry and at exit. No combo price improvement.
- **Commissions and fees.** $0.70 per option contract per side. Stock: $0.005/share, $1 minimum per order, plus 2 bps slippage and 0.25% borrow.
- **Unquoted exits.** Expiring legs unquoted on the 2025+ feed: ITM at intrinsic ± max($0.05, 1%); OTM at 0/$0.05. Delisted names with no exit quote lose 100% on the long side.
- **No passive fills.** The data has no trade prints or queue information, so fill probability cannot be estimated. "Touch = fill" is not assumed.

## 7. Cost share of gross edge

- **Cost share of gross edge, by family** (DISCOVERY, chosen hedge, families with positive gross P&L):
  - Signal-based families: from 70% (long top-1 sector ETF straddle, D1-L ADV-weighted) and 78–79% (B2-IWM gamma, unranked LOU-average long) up to several hundred percent for relative books.
  - The non-signal benchmark "always long SPY straddle" is 48%. Its C50 return is +1.5% (t 0.12) in DISCOVERY and −10.7% in VALIDATION.
- **Daily-hedged books: costs are 2.5× to more than 10× the gross edge.** Option costs of 5–10% of premium plus hedge fees of 6–12%, against a gross edge of 2–7%.
- **The charter requires costs below 50% of gross edge. No family comes close.**

## 8. No-trade months

All months. There is no rule to switch on in "good" months either: the abstention models (Phase E) chose 3–18 trades per month and still lost in VALIDATION.

## 9. Bot feasibility

Technically easy, but pointless:
- one decision per month at the 15:59 close on expiration Friday;
- a few dozen option quotes;
- optional end-of-day hedges.

Running the signal properly is not easy: it needs 12 months of equity-VIX corridor returns for about 2,000 names, built from full OPRA chains every month (the paper construction). That costs data and engineering. With no positive expected value at retail costs, **no bot should be built and no orders placed.** No IBKR API was connected and no orders were sent.

## 10. Anti-overfitting record

- **Pre-registration and freeze discipline.** The charter (RETAIL_V2_CHARTER.md) was committed before any V2 computation. Fourteen audit fixes (ledger row 2) and every implementation choice (row 3) were fixed before results.
- **One run per phase.** Each phase was run once (row 4).
- **One post-result change, toward FAIL.** D2 had been evaluated at the wrong hedge policy and looked like a PASS through a fee artifact. It was corrected back to the charter's H1, turning it into a FAIL (row 5).
- **No result was tuned on 2024–2026.** FORWARD stayed hidden.

## 11. Limitations

- **PROXY panel.** It is ours, not the authors'; correlation 0.78 with their long–short series on overlapping months. Stock data is DoltHub, not CRSP.
- **Snapshot quotes.** One-minute NBBO snapshots, not trades. Fill quality between C25 and C100 is unknown, and C50 is a convention.
- **Hedge prices.** Delta hedges use daily DoltHub closes as a proxy for 15:59 prices, and Black-Scholes deltas at sticky entry IV.
- **Research units.** One contract per leg. Larger accounts would amortise the per-order minimum. But even with **free** stock hedging the best C50 cell is t 0.49 and a short-index crash book (RETAIL_V2_KILL_TESTS.md).
- **Not every formulation was tested.** "Target versus previous expiry" calendars cannot be built from monthly-only data, so they were not tested. Weekly options and 0DTE were outside the pre-registered scope.

## 12. Files

| File | Content |
|---|---|
| RETAIL_V2_CHARTER.md | Pre-registration (signals, LOU, samples, costs, hedges, families, verdict rules) |
| RETAIL_V2_RESEARCH_LEDGER.md | Append-only ledger, rows 0–5 |
| RETAIL_V2_COST_MODEL.md | Execution and fee model |
| RETAIL_V2_SIGNAL_DECOMPOSITION.md | Phase A: Q1/Q2, verdict A |
| RETAIL_V2_RESULTS.md | Phases B–E: all families, cost decomposition, cost reference |
| RETAIL_V2_KILL_TESTS.md | Why Phase G has no object; kill record; robustness of the FAIL |
| V1_RETAIL_VERDICT.md | Earlier V1 adaptation: FAIL |
| `src/v2_legs.py`, `src/v2_universe.py`, `src/v2_phaseA.py`, `src/v2_strategies.py` | Code |
| `results/v2/` | Grids, monthly series, verdict tables (aggregated; no raw quotes) |
