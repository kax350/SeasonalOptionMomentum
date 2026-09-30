# PAPER_SPEC: Heston, Jones, Khorram, Li, Mo, "The Variance Premium and Seasonal Momentum in Option Returns" (RFS 2026)

Porting specification for the equity-VIX construction and the seasonal-momentum sort. Read-only audit; the only file written is this one.

---

## 1. Sources and precedence

| Rank | Source | Path | Notes |
|---|---|---|---|
| 1 (authority) | Final RFS replication package (SAS / Matlab / Stata) | `replication_package/code/` | This is the authority for the final version. `ReadMe.txt` L19–22: "Main sample used to generate the tables and figures are: simpson_return.sas7bdat, simpson_return_0_oi_bid.sas7bdat. Run "Table1&2.sas" to generate [both]". |
| 1a | Data files shipped with the package | `code/Figures/Figure 4/seas_1_12_3_.txt`, `seas_1_36_3_.txt` | These are **monthly H−L return series** keyed by `exdate_trade`. `seas_1_12_3_.txt`: 19961018–20201218, 291 rows. `seas_1_36_3_.txt`: 19980116–20201218, 276 rows. Column mapping from `Figures/Figure 4/Figure4.m`: L20/L23/L26 read cols 3/4/5 into `P1`/`P2`/`P3`; L66 `legend('All','Quarterly','Non-quarterly')`; L74 title "Panel A: Lags 1 to 12"; L79 title "Panel B: Lags 1 to 36". No script in the package writes these files, so calling them "the authors' H−L series" rests on the numbers matching. Recomputing them reproduces the WP Table 5/6/7 **mean, NW t, SD, Sharpe, skew and kurtosis exactly** (§4.3), so those formulas in §3(c) are numerically verified. **MaxDD is only consistent, not verified**: it needs the month-by-month `rf`, which the files do not contain (§4.3). |
| 2 | Working paper, "Seasonal Momentum in Option Returns", June 28, 2022 | `papers/HJKLM_SeasonalMomentum_WP_Jun2022.txt` | Page references are the `[PDF page N]` markers; the printed page number is N−1. Use it only where the code is silent. |
| 3 | Option Momentum (JF) versions | `papers/HJKLM_OptionMomentum_*.txt` | Background only. Not used for any rule below. |
| — | **Final RFS text** | **not available (paywalled)** | Final table numbers are inferred from code file names and comments (WP T5 → final T4, WP T6 → final T5, WP T7 → final T6). UNCERTAIN. |

**Rule: when they conflict, the FINAL replication code overrides the WP.**

**Abbreviations and line numbers**
- `T12` = `Tables/Table 1&2/Table1&2.sas`, 1705 lines (line numbers after stripping CRLF).
  - Holding sample: rows are built in L1–449 and are final at L444 (`if num_strikes>2;`; L445–449 only left-join `shrcd`). L452–831 only add columns by left join (L546 BS hedge, L698 half-strike price, L786 and L825 IV-grid interpolation) and drop no rows. The file is written at L835–836 (`here.simpson_return`).
  - Sorting sample: L1350–1700, written at L1699–1700 (`here.simpson_return_0_oi_bid`).
  - A diff (comments and whitespace stripped) of L1–836 vs L1350–1700 shows **three computational differences**: no `if open_interest>0;`, no `if best_bid=0 then delete;`, and `crsp.dsedist` (L1379) in place of `here.dsedist` (L63). Non-computational differences:
    - the sorting block does not rebuild `stock_prc` or `ZeroCouponYieldCurve`; it reuses the WORK tables built at L26–35 (later code only re-sorts `stock_prc`, L638 and L1271);
    - it has no BS hedge, half-strike or IV-grid steps, and keeps fewer output columns. L836 keeps `… BS_VIX_Return … num_strikes num_put num_call forward strike_min strike_max IV_avg VSR_Corridor_Interpolate`; L1700 keeps only `secid cusip permno shrcd date exdate exdate_trade VIX_Prc Monthly_RV Dynamic_VIX_Return VSR Dynamic_VIX_Return_Corridor VSR_Corridor Rf VIX_BA_percent mkt_cap`;
    - the holding block has extra statements that do not change results (L131, L134, L243–248).
  - The `crsp` libref (L872, L1379) is never assigned in T12; only `libname here` exists (L6).
  - **UNCERTAIN (code version).** `Figures/Figure 2/Figure2_step1.sas` L30–37 selects `BS_VIX_Return` `from here.simpson_return_0_oi_bid`, but L1700 does not keep `BS_VIX_Return` and the shipped sorting block never computes it. Likewise, Table 5 `Factors.sas` L21–23 and `Table 8/Table8_1.sas` L27–29 read `atmiv_termspread`, `slope`, `iv_hv`, `idiovol` from `here.simpson_return`, which L836 does not keep. So the datasets the authors actually used were produced by a code version that differs from the shipped T12. Whether the `crsp.` and `here.` dsedist copies are the same vintage is also unknown.
- `FH` = `SAS functions/form_hold_period_seas_2third.sas`
- `FH2` = `form_hold_period_2third.sas`
- `HL` = `HL_CS_HL_length.sas`
- `GMM` = `GMM.sas`
- `T4A` = `Tables/Table 4/Table4_PanelA.sas`
- `T4B` = `Tables/Table 4/Table4_PanelB.sas`
- `T5S` = `Tables/Table 5/Table5_Seasonal.sas`
- Line numbers are exact for the lines quoted, ±1 otherwise.

**What the package does not contain.** The upstream dataset `here.options` is not built anywhere in it. `T12` L13 describes it: "The data 'options' contain only individual stock options on the 3rd Friday whose maturities are the 3rd Friday next month. It is at firm-month frequency." `T12` L21 adds: "exdate_trade is created as the last trading day of option holding period."

---

## 2. Master table

Legend for the "Final vs WP" column:
- **SAME**: the code implements the WP rule.
- **CHANGED**: the code differs from the WP.
- **CODE-ONLY**: a detail the WP does not state.
- **PAPER-ONLY**: stated in the WP, absent from the code.
- **UNCERTAIN**: cannot be settled from the sources.

| # | Component | Paper rule (WP Jun-2022, verbatim + PDF page) | Replication code (file:line + snippet) | Final vs WP | Our implementation decision |
|---|---|---|---|---|---|
| 1 | Data sources | p.19–20: "This paper uses data from the OptionMetrics Ivy DB database … daily closing bid and ask quotes for U.S. equity options. We use the T-bill rate of appropriate maturity (interpolated when necessary) from OptionMetrics as the risk-free rate. Finally, we obtain information about stock returns, dividends, and firm characteristics from CRSP and Compustat." | Inputs are `here.options` (OM), `here.ZeroCouponYieldCurve` (OM), `here.CRSP_stock_daily` and `here.dsedist` (CRSP) (T12 L14, L26, L33, L63). Also `crsp.dsedist` (L872 CBOE block, L1379 sorting block; libref never assigned) and `here.options_daily` (OM daily deltas/IVs, L456, used only for the BS hedge). None of these inputs is built in the package. `ReadMe.txt` L12–17 also lists IBES, Compustat and "Fama-French risk-free rates"; those are used only by other tables (e.g. Table 13 `ff_daily`). | SAME | **PROXY.** OptionMetrics is replaced by OPRA NBBO (Databento `cbbo-1m`); CRSP by DoltHub; the OM zero curve by FRED (see §6). |
| 2 | Sample period | p.19: "from January 1996 to November 2020". Captions: p.49 "spans between January 1996 to November 2020"; p.50 "spans the period from January 1996 to November 2020"; p.51 "spans the sample from January 1996 and November 2020." | There is no date filter in the code. The Figure 4 data files hold holding months (`exdate_trade`) ending **2020-12-18**; `seas_1_12_3_.txt` starts 1996-10-18 and `seas_1_36_3_.txt` starts 1998-01-16. The first non-missing values (All 1..12: 1996-10; Quarterly 3,6,9,12: 1996-11; Quarterly 3..36 and All 1..36: 1998-02) are exactly what the lag-count rules imply if the first holding month is Feb-1996. That matches formations from Jan-1996 (first `exdate_trade` Feb-1996) through Nov-2020. p.48 says "each of the 299 months" (Jan-96..Nov-20 = 299). | SAME (the final package data end at the same point) | **PROXY.** We only cover the OPRA-era overlap. OPRA via Databento is assumed to start 2013-04 (the `src/opra_download.py` default; UNCERTAIN). Validate against the overlap targets in §4.3. |
| 3 | Share codes | Table captions only, e.g. p.49: "The sample includes common shares (shares with share codes of 10 and 11)". The sentence appears in the captions of Tables 5, 6, 7, 8, 9, 11 and 12 (txt L2179, 2276, 2371, 2532, 2660, 2894, 3009). It is absent from Section 3 and from the Table 1–4 captions (pp.45–48), which describe the 221,157-observation sample. | T12 L84–89 (and L1398–1403): `select a.*, b.shrcd … on a.cusip=b.cusip and a.date=b.date;` then `if shrcd=10 \| shrcd=11;`. Measured on the formation date. | SAME | **PROXY.** Use DoltHub symbol metadata and keep US ordinary common stock only. Exclude ETFs/ETNs, ADRs, foreign-incorporated firms, closed-end funds, REITs (UNCERTAIN whether REITs are shrcd 18 in every case), units, preferreds and indices. |
| 4 | $5 filter | p.20: "exclude firm-month observations if the underlying stock price is less than $5 on the formation date" | T12 L75–81: `b.prc as St_start … a.date=b.date` then `if 5=<st_start;`. Here `prc=abs(prc)` (L34), i.e. the CRSP close. (That a negative CRSP `prc` denotes a bid/ask midpoint on no-trade days is CRSP vendor documentation, not shown in the package.) A missing price drops the firm-month. | SAME | **EXACT rule.** Data is PROXY (DoltHub raw, unadjusted close on the formation date). |
| 5 | OI > 0 | p.20: "we remove all observations for which the option open interest is equal to zero" | T12 L15: `if open_interest>0;`. **Holding sample only**; there is no OI filter at L1350–1356. A missing OI fails the test. | SAME | **PROXY / UNCERTAIN.** `cbbo-1m` has no OI. Primary plan: Databento OPRA `statistics` schema (open-interest stat) on formation dates only. Check the cost first; availability is UNCERTAIN. Fallback: holding sample without the OI filter, flagged as a deviation. |
| 6 | bid > 0 | p.20: "We discard options with zero bid prices" | T12 L17: `if best_bid=0 then delete;`. **Holding sample only**. A missing bid is **not** deleted by this line, nor by L18 (missing > ask is false) nor by the arbitrage checks L124/L126 (comparisons with missing are false). In SAS a missing-bid option is therefore kept in **both** samples: it counts toward ΔK, K0/K1 and the put/call counts, gets a payoff weight (L285–287), but adds nothing to `sigma2` or `sigma2_bid` because PROC MEANS skips the missing products (L219–220, L255–258). UNCERTAIN whether OM stores a no-bid quote as 0 or as missing. | SAME | **EXACT** on the NBBO bid. Map an undefined NBBO bid (INT64_MAX sentinel) to 0 **only** when the ask is defined; drop the contract if the ask is undefined. This is a deliberate deviation from SAS's keep-with-no-price treatment of a missing bid. |
| 7 | ask ≥ bid | p.20: "We delete all observations whose ask price is lower than the bid price" | T12 L18 / L1352: `if best_bid>best_offer then delete;`. Under SAS missing semantics, a missing ask with a valid bid is deleted. | SAME | **EXACT.** Drop crossed quotes; keep locked quotes (bid = ask). |
| 8 | IV/delta availability | p.20: "and with missing implied volatility or delta (which occurs for options with nonstandard settlement or for options with intrinsic value above the current mid price)" | T12 L16 / L1351: `if delta ne .;`. `impl_volatility` is **not** filtered. It is averaged into `IV_avg` (L187) and, in the holding sample only, used in the IV-grid interpolation (L717 keep list, L747 `select a.*, b.impl_volatility as IV`) that feeds the diagnostic `VSR_Corridor_Interpolate` (L822). | UNCERTAIN (the code tests delta only; whether OM IV and delta are always missing together is unverified) | **PROXY.** (a) Drop non-standard deliverables: OSI roots ending in a digit, and mini options. (b) Invert the Black-Scholes IV on the mid with `F`, `r`, τ = (exdate_trade − date)/365. Drop the option if there is no root, i.e. the mid is outside the European no-arbitrage bounds. |
| 9 | Arbitrage bounds | p.20: "eliminate options whose prices violate arbitrage bounds" | T12 L123–127, applied **after** OTM selection: `if cp_flag='P' and strike_price<best_bid then delete; if cp_flag='P' and best_offer<max(0,strike_price-st_start) then delete; if cp_flag='C' and st_start<best_bid then delete; if cp_flag='C' and best_offer<max(0,st_start-strike_price) then delete;`. Uses spot `St_start` with no discounting. | SAME (the code gives the specific bounds) | **EXACT.** |
| 10 | Dividend exclusion | p.20: "or if the stock has a split or pays a dividend during the remaining life of the option" | T12 L42–59: drop the firm-month if any `stock_prc` row has `divamt>0` (L43 `data dividend; set stock_prc; where divamt>0;`) with `a.date<b.date<=a.exdate_trade` (L48). The check runs only on rows that survive L34 (`if ret=.B \| ret=.C then delete;`) and L35 (`proc sort … nodupkey; by cusip date;`, first row per cusip-date). UNCERTAIN: `here.CRSP_stock_daily` (L33) is not built in the package (it carries `divamt` and `shrcd`, so it is not raw dsf); that its `date` on dividend rows is the ex-distribution date is an inference, not shown by the source. | SAME | **EXACT rule.** Data is PROXY: DoltHub dividend ex-dates in (date, exdate_trade]. |
| 11 | Split exclusion | same sentence, p.20 | T12 L62–72: `set here.dsedist; if FACSHR ne 0; split_flag=1;` joined on `a.cusip=b.cusip and a.date<b.exdt<=a.exdate_trade`. A missing FACSHR counts as ≠ 0. The sorting block uses `crsp.dsedist` (L1379). | SAME | **EXACT rule.** Data is PROXY: DoltHub split ex-dates in (date, exdate_trade], covering forward and reverse splits and stock dividends. |
| 12 | Min strikes and put+call | p.20: "We require at least three OTM options, including one put and one call, for each stock" | Counts use the final options after all option filters (T12 L164–180). `proc means … n=num_call` / `n=num_put`; `if num_call ne .;` (L179); `num_sum=num_put+num_call` (L180); `if num_strikes>2;` (L444). The firm-month needs n_put ≥ 1, n_call ≥ 1 and n_put + n_call ≥ 3. | SAME | **EXACT.** |
| 13 | VIX_Prc_bid > 0 | p.20: "We only keep observations with positive VIX prices calculated with option bid prices to avoid very small VIX." | T12 L348: `VIX_Prc_bid = sigma2_bid + (a)*St_start + (b)/Rf;`, then L351 `if VIX_Prc_bid>0;`. This **includes** the stock and bond terms. It applies to both samples (sorting-sample zero bids enter as 0). | SAME | **EXACT.** |
| 14 | Terminal stock price must exist | not stated | T12 L277–284: `b.prc as stock_prc_end … a.exdate_trade=b.date;` then `if stock_prc_end ne . ;` removes all the firm-month's option rows. `sigma2` (L255–258) was computed earlier, so the firm-month row survives until L300–316 leave `cusip`, `exdate_trade`, `St_start` and `St_end` missing (`identifier` has no row); `VIX_Prc_bid` is then missing and the firm-month is dropped at L351 (`if VIX_Prc_bid>0;`). This assumes `stock_prc` has no blank-cusip rows (PROC SQL matches missing keys to each other). | CODE-ONLY | **EXACT.** Require a DoltHub close on `exdate_trade`. |
| 15 | Formation date | p.21: "we establish option positions in equity-VIX portfolios on the third Friday of a month. When this date is a holiday, the portfolio formation is one day before." | Built upstream; comment at T12 L13 ("on the 3rd Friday"). Not coded in the package. | SAME | **EXACT.** Use the last XNYS session on or before the 3rd Friday (`src/calendar_utils.formation_dates`). |
| 16 | Maturity / `exdate_trade` | p.33: "By the time we include them in our sample, all options have one month until expiration." Table 1 ("Simulation study"), Panel B "Simulation parameters", p.45: time to expiration mean 0.08; the caption (txt L1652–1654) says the simulated panel matches "the actual sample described in Section 3 in terms of the numbers of options, strike prices, maturities, stock prices, and riskless rates." | T12 L13: "maturities are the 3rd Friday next month". T12 L21: `days_expire=exdate_trade-date; /*exdate_trade is created as the last trading day of option holding period.*/`. The Figure 4 dates confirm `exdate_trade` = 3rd Friday of the next month, or the previous session on Good Friday (2000-04-20, 2003-04-17, 2008-03-20, 2014-04-17, 2019-04-18), with exactly one date per month. | SAME | **EXACT.** Take the standard monthly expiry of month m+1: the OSI expiry is the Saturday after the 3rd Friday before Feb-2015 and the 3rd Friday after that (vendor/OCC convention, not verified from the package). Holiday expiries fall on the Thursday. `exdate_trade` = last XNYS session ≤ 3rd Friday of m+1. Exclude weeklies and other expiries. |
| 17 | De-duplication | not stated | T12 L23 `nodupkey by secid date exdate strike_price cp_flag`. L80 `nodupkey by secid date strike_price descending cp_flag` (the key omits `exdate`). L109 `nodupkey by cusip date` on the forward table. Each keeps the first row after a stable sort. | CODE-ONLY | **EXACT in spirit.** Keep one quote per (root, expiry, K, cp) and assert uniqueness. |
| 18 | Risk-free rate curve | p.19–20: "T-bill rate of appropriate maturity (interpolated when necessary) from OptionMetrics" | T12 L26–28: `proc expand … to=day; convert rate=linear_rate / method=spline(natural); id days; by date;`. This is a natural cubic spline in `days`, despite the name. Joined at `a.exdate_trade=b.date+b.days` (L102) and at `b.days=a.days_expire` (L269). The rate is treated as a continuously compounded percent on ACT/365. There is no extrapolation (UNCERTAIN: PROC EXPAND default). | SAME (source: both say OptionMetrics); CODE-ONLY (spline detail). UNCERTAIN (instrument): the code uses the OM `ZeroCouponYieldCurve`; from outside the local sources (OM documentation, not checkable here), that curve is built from LIBOR and Eurodollar futures rather than T-bills. If so, a FRED T-bill proxy runs below it, mostly before 2009. | **PROXY.** Use a FRED Treasury rate at tenor τ days, e.g. DTB4WK/DGS1MO, interpolated linearly toward DGS3MO. Convert to a continuously compounded percent. The alternative is French monthly rf (coarser). |
| 19 | Forward | fn.3 p.6: "The sum uses out-of-the-money options with respect to the forward value of the strike price, K(1+rf)^{T−t}." | T12 L111: `Forward=stock_prc_start*exp(linear_rate/100*days_expire/365);`. No put-call parity. `stock_prc_start` is the CRSP close on `date`. | SAME | **EXACT formula** with proxy inputs. |
| 20 | OTM selection | fn.3 p.6 (above); eq.(11) p.10 uses puts for K<F and calls for K>F | T12 L117–119: `if cp_flag="P" and strike_price>forward then delete; if cp_flag="C" and strike_price<=forward then delete;`. Puts have K ≤ F and calls K > F, giving **at most one option per strike**. | SAME | **EXACT.** Do not keep both a put and a call at one strike (see pitfall P5). |
| 21 | K0 / K1 | eq.(12) p.10: "where K0 is the closest strike price below-the-money." (quoted from the CBOE formula (12), not from the Simpson section). K1, p.10 (txt L410): "It treats K0 and the next higher strike price K1 asymmetrically". The Simpson rule (pp.11–12, eqs. 14 and 18) uses both. | K0 (T12 L137–139): `distance_toForward=Forward-strike_price; if distance_toForward<0 then delete;`, then the smallest distance, i.e. **the largest strike ≤ F** (always a put). K1 (L149–151): `strike_price-Forward`, keeping ≥ 0, i.e. **the smallest strike ≥ F**. Both are found after the arbitrage filter. Firm-months without them are dropped (`if K0 ne .`, `if K1 ne .`, L146, L158). | SAME | **EXACT.** |
| 22 | Simpson ΔK | eq.(11) p.10: "where ∆i = (Ki+1 −Ki−1)/2". Edges not stated. | T12 L208–210: `delta_K=(lead_strike_price-lagged_strike_price)/2; if first.secid \| first.date then delta_K=lead_strike_price-strike_price; if last.secid \| last.date then delta_K=strike_price-lagged_strike_price;`. **The edge ΔK is the full spacing, not half.** | SAME (interior); CODE-ONLY (edges) | **EXACT.** |
| 23 | Simpson weights | eq.(18) p.12: VIX²_S = VIX²_rect + (e^{rT}/3T)[(K1−K0−Δ0)/K0²·Put(K0) + (K1−K0−Δ1)/K1²·Call(K1)] + … | T12 L213: `Weight_eachoption=2*delta_K/(strike_price**2);`. L216: `if strike_price=K0 then Weight_eachoption = Weight_eachoption+(K1-K0-delta_K)/3/(K0**2);`. L217: `if strike_price=K1 then … +(K1-K0-delta_K)/3/(K1**2);`. The 1/T and e^{rT} factors are dropped. Price = Σ w·mid (L219, L255–258). | SAME (without 1/T, which is harmless for returns) | **EXACT.** |
| 24 | Stock/bond components; VIX price | p.13: "the second line of the simplified Simpson's formula (18) represents the forward value of ((K1−K0)/(3T)(1/K0² − 1/K1²) + 1/T(2/F − 1/K0 − 1/K1))S_T + (K1−K0)/(3T)(1/K1 − 1/K0) + 1/T(log(F/K0) + log(F/K1))" (equation garbled in the txt, rebuilt) | T12 L343: `VIX_Prc =sigma2 + ( (K1-K0)/3 * (1/K0**2 - 1/K1**2) + (2/Forward - 1/K0 - 1/K1) ) * St_start + ( (K1-K0)/3 * (1/K1 - 1/K0) + ( log(forward/K0) + log(forward/K1) ) ) / Rf;` with `Rf=exp(linear_rate/100*days_expire/365);` (L337). Bid/ask versions are at L348–349. | SAME | **EXACT.** The coefficients are signed; never take absolute values. |
| 25 | Terminal payoff | eq.(7) p.8: r_unhedged = [V(T;T) − V(t;T)]/V(t;T) | T12 L285–287: `option_payoff=max(stock_prc_end-strike_price,0)` (C) / `max(strike_price-stock_prc_end,0)` (P); `Option_TerminalPayoff=Weight_eachoption*option_payoff`. L340: `Static_VIX_Payoff = Option_TerminalPayoff + (a) * St_end + (K1-K0)/3 * (1/K1 - 1/K0) + ( log(forward/K0) + log(forward/K1) );`. S_T is the CRSP close on `exdate_trade`, **not** an option quote. | SAME | **EXACT.** Options are needed only on the formation date. |
| 26 | Model-free hedge (non-corridor) | p.7: "the delta-hedge of the log-portfolio buys 1/F(t) shares of stock for a price of S(t), and rebalances to maintains a constant hedge exposure of one dollar." eq.(8) p.8. | T12 L395: `Delta_Hedge_Reinvt=2/(Rf_daily**(exdate_trade-lag(date_daily)))*(1+stock_ret - Rf_daily**(date_daily-lag(date_daily)))*(Rf_daily**(exdate_trade-date_daily));` with `Rf_daily=exp(linear_rate/100/365)` (L383). L427: `Dynamic_VIX_Payoff=Static_VIX_Payoff-2*(St_end/St_start/Rf-1)+Delta_Hedge_payoff;` L394 comment: "Each day, the model-free hedge borrows $2/exp{rf*(T-t)} at Rf and invest in stock for 1 trading day; Reinvest the delta-hedged payoff next trading day to the expiration at Rf." Algebraically each L395 term equals 2·(1 + ret − R^gap)/R^gap (R = `Rf_daily`, gap = calendar days since the previous row), not 2·(r_S − r_f) as in eq.(8). | SAME in substance; CODE-ONLY detail (borrow at 2/R^(T−t_prev), reinvest to T, calendar-day compounding) | **EXACT** (compute it for diagnostics; it is not the sort variable). |
| 27 | Corridor barriers | p.17: "the values of KL is equal to the lowest strike price available minus one half of the distance between that strike price and the one above it. Similarly, KH is the highest strike plus one half the distance from the next highest." eq.(23) p.17 clips F. | T12 L230–239: `delta_min` = ΔK at `strike_min` (= K₂−K₁), `delta_max` = ΔK at `strike_max` (= Kₙ−Kₙ₋₁). L364–370 and L388–390: clip to `[strike_min-delta_min/2, strike_max+delta_max/2]`, inclusive. | SAME | **EXACT.** |
| 28 | Corridor hedge and `Dynamic_VIX_Return_Corridor` (the return used everywhere) | Table 5 caption p.49: "Dynamically hedged VIX returns with model-free corridor hedge ratios are used." p.17: "the hedge of the truncated portfolio … is 1/F̄(t)." | Daily panel T12 L378–382: CRSP rows with `a.date<=b.date<=a.exdate`. L384: `Forward_daily=St_daily_Corridor*exp(linear_rate/100*(exdate_trade-date_daily)/365);`. L398: `Delta_Hedge_Corridor = 2/lag(Forward_daily_Corridor)*lag(St_daily_Corridor) * (1+stock_ret- Rf_daily**(date_daily-lag(date_daily))) * Rf_daily**(exdate_trade-date_daily);`. L404: `if date_daily=date then delete;`. Summed with PROC MEANS `sum=` (L406–408). L431–432: `Dynamic_VIX_Payoff_Corridor = Static_VIX_Payoff - 2*(St_end/St_start/Rf-1) + Delta_Hedge_payoff_Corridor; Dynamic_VIX_Return_Corridor = Dynamic_VIX_Payoff_Corridor/VIX_Prc - 1;`. Like row 26, each L398 term is borrowed and reinvested to T (CODE-ONLY detail). The WP Fig. 2 caption (p.42) says "the return on the VIX portfolio hedged using Black-Scholes"; the WP text (p.28, txt L1146–1147) says "we use model-free hedge ratios with the corridor adjustment", and the final `Figures/Figure 2/Figure2_plot.m` panel (c) plots `varName='VIX_Return_MFcor'` (L47) with title 'Panel (c): Dynamic VIX return (Model-free corridor hedge)' (L58); `Figure2_step1.sas` L25/L36 defines `Dynamic_VIX_Return_Corridor as VIX_Return_MFcor`. | SAME (the WP caption differs from the WP text and the final code) | **EXACT formula.** `stock_ret` is PROXY (raw close-to-close, valid because the window has no dividends or splits). |
| 29 | Excess returns | Caption p.49: "returns are in excess of the risk-free rate" | T12 L835–836 / L1699: `Rf=Rf-1;`, so `rf` = exp(r·τ/365) − 1, the simple holding-period rate. T4A L31: `a.dynamic_vix_return_corridor - a.rf as vix_all, b.dynamic_vix_return_corridor - b.rf as vix_posoi`. Each sample uses its own row's `rf`. | SAME | **EXACT formula**, PROXY r. |
| 30 | Sorting (secondary) vs holding (primary) sample | p.20: "We use the primary sample to compute holding period returns … We therefore relax the positivity constraints on open interest and bid prices in a secondary sample, which we use solely for computing returns during the formation period." | T12 L1349: "The code is the same as before except that we keep options with 0 open interests or bid prices." The sorting sample is saved as `here.simpson_return_0_oi_bid` (L1699), the holding sample as `here.simpson_return` (L835). Joined at T4A L33–34: `from here.simpson_return_0_oi_bid as a left join here.simpson_return as b on a.secid = b.secid and a.exdate_trade= b.exdate_trade;`, so **the base universe is the sorting sample**. | SAME | **EXACT.** Build both samples from the same formation snapshot. |
| 31 | Month indexing | not stated | T4A L31: `a.exdate_trade as date_var`. FH L64–66: `intck("month", b.date_var, a.date_var) as num_lag … &form_minlag. <= intck(...) <= &form_maxlag.`. Lags are **calendar-month differences of `exdate_trade`**, not row offsets. | CODE-ONLY | **EXACT.** Key everything by the `Period('M')` of `exdate_trade`. |
| 32 | Seasonal lags {3,6,9,12} | p.28: "formation periods that only include lags that are multiples of three or 12, which respectively capture quarterly and annual seasonal momentum." | FH L70: `if num_lag/&seasonality_period ne int(num_lag/ &seasonality_period ) then delete;`. T4A L94: `%seas(1,12,3,2);` gives lags {3,6,9,12}. | SAME | **EXACT.** |
| 33 | Missing-data rule | Caption p.49: "Observations are included if at least two thirds of all months in the formation period are non-missing." | FH L77: `having n(var_lag) >= ((floor(&form_maxlag. / &seasonality_period) - ceil(&form_minlag. / &seasonality_period) + 1)* 2/3)`. K = 4 gives n ≥ 8/3, i.e. **at least 3 of the 4 lags**. In general need = ceil(2K/3): {3}: 1/1; {3..36}: 8/12; {12}: 1/1; {12,24,36}: 2/3; momentum 2–12 (FH2 L54): 8/11; 2–36: 24/35. A lag counts as missing if the stock has no sorting-sample row that month or its `vix_all` is missing. | SAME (the code gives exact counts) | **EXACT.** |
| 34 | Lag 1 excluded (momentum windows only) | fn.9 p.28: "Similar to the stock momentum literature, we exclude lag 1 because Heston et al. (2021) find some evidence that it is related to short-term reversal rather than momentum." The footnote is attached to the Table 5 Panel B sentence (txt L1158–1159: "Panel B examines formation periods in which all lags, starting with lag 2, …"). The WP itself **includes** lag 1 in Table 7: row labels "Non-quarterly (1,2,4,5, …)" and "Non-annual (1,…,11,13,…)", and p.30 (txt L1202–1205): 'The "All" row includes all 12, … while the "Non-annual" row includes lags 1 to 11.' | Automatic for the multiples of 3. Momentum uses `%mom(2,12,7); %mom(2,36,8);` (T4B L91–92), i.e. min lag 2. The final Table 6 windows starting at 1 include lag 1: "All" and "Non-quarterly" via `%seas(1,12,3,1);` (`Table6_all_to_non_annual.sas` L138) and "Non-annual" via `%seas(1,12,12,7);` (L145). | SAME | **EXACT.** Lag 1 is excluded only from Momentum 2..12 / 2..36. The §4.3 targets "All 1..12" = 0.1392 (13.64) and "Non-quarterly" = 0.1179 (8.99) include lag 1 under both the WP and the code. |
| 35 | Signal = mean of lagged returns | p.51: "portfolios formed on the basis of average lagged returns" | FH L74: `mean(var_lag) as fvar` (AVG branch; T4A L46 `form_ret_type= AVG`). This is the **arithmetic** mean of the available lagged **excess** returns `vix_all`. | CODE-ONLY (arithmetic, excess) | **EXACT.** |
| 36 | Holding period | p.29: "In all cases, the holding period is one month" | FH L106–116: `0 <= intck("month", a.date_var, b.date_var) <= &hold_period. -1` with `hold_period=1`, then `mean(var_lead) as hvar … having n(var_lead) = &hold_period`. `hvar` = `vix_posoi` of the same `exdate_trade` month. | SAME | **EXACT.** |
| 37 | Ranking universe | not stated | FH L136–147: `_s1` (all sorting-sample rows) inner-joined to `_s3` (valid `fvar`), then left-joined to `_s5` (`hvar`). HL L10: `proc rank data=&input (where=(missing(&sortvar)=0))`. **Stocks with a missing holding return are still ranked** (they set the breakpoints). The stock must also have a sorting-sample row in the holding month itself. | CODE-ONLY | **EXACT.** |
| 38 | Quintiles and ties | Caption p.49: "univariate quintile sorts". Breakpoints and ties not stated. | HL L10–18: `proc rank … ties=low groups=&ngroups; by &date; var &sortvar;`, then `&sortvar._r = &sortvar._r +1`. SAS GROUPS formula (SAS docs, not in the package): group = floor(rank·k/(n+1)), with rank = the minimum rank among ties (TIES=LOW) and n the number of non-missing values. Groups run 1..5 ascending; 1 = Low, 5 = High. | CODE-ONLY | **EXACT.** Use `r = fvar.rank(method='min')`; `q = (r*5)//(n+1) + 1` in integer arithmetic. Not `pd.qcut`. |
| 39 | Equal weighting | Caption p.49: "All portfolios are equally weighted" | HL L48: `mean(&depvar) as ew_ret` (mean of non-missing `hvar`). T4A L53 uses `depVar= ew_ret`. `vw_ret` is computed but unused. | SAME | **EXACT.** |
| 40 | H − L | Table 5 "High - Low" column, p.49 | HL L71: `_H_L= _&ngroups. - _1;` (Q5 − Q1). It is missing if either extreme has no holding returns that month. | SAME | **EXACT.** |
| 41 | Newey-West, 3 lags | Caption p.49: "T-statistics, in parentheses, are computed using Newey-West standard errors with three lags." | GMM L41–45: `proc model … instruments / intonly; &depVar=a; fit &depVar / gmm kernel=(bart,%eval(&lags+1),0) vardef=n …`, with `lags=3` (T4A L53). L60: `a=a/aVar**(1/2);`. This gives Bartlett weights 1−j/4 for j = 1..3 and divisor T. **Verified**: it reproduces 14.80, 13.64, 8.99 and 12.23 from the Figure 4 series. | SAME | **EXACT.** Use the explicit formula in §3(c). Do not rely on statsmodels defaults. |
| 42 | Sharpe ratio | p.29: "The seasonal momentum strategy based on lags 3, 6, 9, and 12 has a monthly Sharpe ratio of 0.956, or 3.31 annualized." | GMM L15: `mean(&depvar) / std(&depvar) as sharpe`. Monthly, with n−1 divisor, not annualized; T5S L54 keeps it. `sharpe_nw` (GMM L159) is unused. **Verified** 0.956 / 0.739. | SAME | **EXACT.** Report annualized ×√12 only as a secondary figure. |
| 43 | SD, skewness, kurtosis | Table 6 p.50: "All values are in monthly decimal terms." No definitions given. | T5S L47: `proc means data= CS3 mean std skew kurt;` (SAS defaults: G1 skew and **excess** kurtosis G2). **Verified**: pandas `.std()`, `.skew()` and `.kurt()` reproduce 0.149 / 1.024 / 7.80 and 0.184 / 2.363 / 20.45. | CODE-ONLY | **EXACT.** |
| 44 | Maximum drawdown | p.29 names MaxDD but does not define it. | T5S L57–58 comment: "defined as the largest fraction by which the cumulative value of a factor portfolio falls below its prior maximum". L60: `proc sort data= here.simpson_return_0_oi_bid out= ff_monthly (keep= exdate_trade rf) nodupkey; by exdate_trade;` (rf = the first row's `rf` per `exdate_trade`). L62–66: **inner** join to the H−L series by calendar month (`intnx("month",…,0,"e")`), so a month without an rf row is dropped. L70: `rr= sum(ew_ret_p, 1, rf);` on the **sign-flipped** series `ew_ret_p` (same in `Table5_Non_Seasonal.sas` L52). L78 and L88: cumulative product up to and including t. L96: `where a.date_var> b.date_Var` (the prior maximum uses strictly earlier months; the initial wealth of 1 is excluded). L101: `val= (cumret / priormax) -1;`. L105: `min(min (val) * -1,1)`, so the value is capped at 1. **Consistent only, not verified**: with rf = 0 the Figure 4 series give 0.3757 (3,6,9,12) and 0.4105 (3..36) vs published 0.373 / 0.406; see §4.3 for the rf levels needed. | CODE-ONLY | **EXACT.** |
| 45 | Sign flipping | Table 6 caption p.50: "Means and t-statistics for the long/short factors are identical to those in Table 1 except, in some cases, for the sign." ("Table 1" is a typo for Table 5.) | T5S L37–44: `mean(ew_ret) as mean from CS1; … if mean < 0 then ew_ret_p= ew_ret * -1; else ew_ret_p= ew_ret;` (full-sample mean). Used only in the risk table (final T5 = WP T6); Table 4 has no flip. | SAME | **EXACT.** This is ex-post; report it as done, and never use it in a holdout. |
| 46 | "#firms" column | Table 5 p.49, column "monthly # firms" | T4A L57–58: `select n(fvar) as num_firm from data3 where vix_posoi ne . and fvar ne . group by date_var;` then `mean(num_firm)` and `min(num_firm)` over months. | CODE-ONLY definition | **EXACT** definition. The level will differ (OPRA-era universe). |
| 47 | Momentum comparator | p.28: "Panel B examines formation periods in which all lags, starting with lag 2, and including lags out to 12 or 36 months." | FH2 L47–54 with `%mom(2,12,7)`: lags 2..12, at least 8 of 11. | SAME | **EXACT.** |
| 48 | BS-hedged return (not used in sorts) | Table 3 p.47, "Black-Scholes hedge" row | T12 L455–553. OM daily deltas, filled with the last available IV when missing. L528: `delta_daily = Σw·delta + a − 2/forward`. L538: `BS_Payoff_daily= -delta_daily*( St_NextDay - St_daily*exp(Rf_daily*days_change) )*exp(Rf_daily*(exdate_trade-next_trade_day));`. The comment at L552 ("unhedged") is wrong. | SAME | **NOT PORTED** (needs daily option deltas). Optional diagnostic only. |
| 49 | Risk-table (final T5 = WP T6) non-seasonal factors | Table 6 p.50 rows "Momentum (2-12)", "HV - IV", "Idiosyncratic vol", "Market cap", "IV term spread", "IV smile slope", "Short SPX VIX", "Short EW stock VIX". Not defined in the WP beyond citations. | Built by a **different pipeline** from the seasonal rows. `Tables/Table 5/Factors.sas`: L21–24 left-join as in T4A, but reads `atmiv_termspread slope iv_hv idiovol mkt_cap` from `here.simpson_return` (not kept by T12 L836; construction not in the package). L35–37 momentum via `%form_hold_period_2third(… form_minlag= 2, form_maxlag= 12 …)`. L81–82: `%factors(… factor_vars=slope mcap idiovol atmiv_termspread IV_HV mom, ret_var=vix_posoi, port_weight=mcap, ngroups=5);` which calls `%HL_CS` (L58; identical H−L arithmetic to `HL_CS_length` with `HL_length=1`). L91–95: `select a.*, (b.dynamic_vix_return - b.rf) * -1 as spx_vix … from data6 as a, data1_spx as b where a.date_var= b.exdate_trade;` — an **inner** join to `here.index_simpson_return` (L88, not built in the package) using the **non-corridor** return, so months with no SPX row are dropped for **every** factor. L100–104: `mean(vix_posoi) * -1 as ew_vix … from data2 group by date_var` (all rows), inner-joined at L106–110. Sign flip by full-sample mean in `Factors_psigned.sas` L33–42. Statistics in `Table5_Non_Seasonal.sas` (L25 `num_firm= 1;`, L29 moments, L33 GMM, L41–52 MaxDD on `ew_ret_p`). | CODE-ONLY | **NOT PORTED** except Momentum 2–12 via §3(b). Comparator rows are context only; the characteristic inputs are package gaps (P24). The sign of `iv_hv` is UNCERTAIN (see §4.2 note). |

---

## 3. Exact pseudo-code (Python-like, portable)

Conventions:
- `nan` behaves like SAS missing only where noted.
- All dates are session dates.
- `r_pct` is the zero rate in **percent**, continuously compounded, ACT/365, on the curve date `t0` at tenor `tau` days.

### (a) Equity-VIX price and corridor-hedged return per firm-month

```python
import numpy as np, math

def firm_month(opts, S0, ST, daily, r_pct, t0, exdate, exdate_trade, sample, fm_flags):
    """
    opts : option quotes on formation date t0 for ONE expiry (next month's standard monthly), one underlying.
           columns: cp in {'C','P'}, K (dollars), bid, ask, oi, has_delta (bool: IV/delta computable)
    S0   : stock close (CRSP prc, abs) on t0          [T12 L75-79]
    ST   : stock close on exdate_trade                 [T12 L280-284]  -> None drops firm-month
    daily: list of (d, close_d, ret_d) for every stock-data trading day d with t0 <= d <= exdate, sorted
           (ret_d = total return vs previous available close; window has no divs/splits by construction;
            close_d or ret_d may be NaN -- SAS missing semantics are reproduced below)
    r_pct: zero rate at tenor tau=(exdate_trade-t0).days on curve date t0 [T12 L102, L269]
    sample: 'holding' (primary) or 'sorting' (secondary)
    fm_flags: dict(div_in_window, split_in_window, shrcd_ok); div/split flags computed on (t0, exdate_trade]
              [T12 L48, L68]; shrcd_ok measured on t0 itself [T12 L84-89]
    returns dict or None (firm-month dropped)
    """
    # ---- firm-month filters (order irrelevant for the result) ----
    if fm_flags['div_in_window'] or fm_flags['split_in_window']:   # T12 L42-72; interval (t0, exdate_trade]
        return None
    if S0 is None or not (S0 >= 5):                                 # T12 L81  `if 5=<st_start`
        return None
    if not fm_flags['shrcd_ok']:                                    # T12 L89  shrcd in (10,11) on t0
        return None
    if r_pct is None or np.isnan(r_pct):                            # SAS: missing Forward deletes all puts -> K0 missing
        return None
    if ST is None or np.isnan(ST):                                  # T12 L284 (implicit drop)
        return None

    tau = (exdate_trade - t0).days                                  # days_expire, T12 L21
    Rf  = math.exp(r_pct/100 * tau/365)                             # T12 L337 (gross)
    F   = S0 * math.exp(r_pct/100 * tau/365)                        # T12 L111

    # ---- option-level filters ----
    o = opts.copy()
    if sample == 'holding':
        o = o[o.oi > 0]                                             # T12 L15 (NaN oi fails)
        o = o[~(o.bid == 0)]                                        # T12 L17 (NaN bid NOT dropped by SAS; we require bid defined anyway)
    o = o[o.has_delta]                                              # T12 L16 / L1351
    o = o[o.ask.notna() & o.bid.notna() & ~(o.bid > o.ask)]         # T12 L18 (+ port-safety: no missing quotes)
    o = o.drop_duplicates(['K','cp'])                               # T12 L23 (key incl. exdate) and L80 (strike, cp_flag only);
                                                                    #   assert none actually dropped
    o['mid'] = (o.bid + o.ask) / 2                                  # T12 L20 (sorting sample: bid=0 -> mid=ask/2)

    # OTM relative to forward                                       # T12 L118-119
    o = o[((o.cp == 'P') & (o.K <= F)) | ((o.cp == 'C') & (o.K > F))]
    # arbitrage bounds, spot-based, undiscounted                    # T12 L124-127
    put, call = o.cp == 'P', o.cp == 'C'
    bad = (put & (o.K < o.bid)) | (put & (o.ask < np.maximum(0, o.K - S0))) \
        | (call & (S0 < o.bid)) | (call & (o.ask < np.maximum(0, S0 - o.K)))
    o = o[~bad].sort_values('K').reset_index(drop=True)            # one option per strike guaranteed

    # K0, K1                                                        # T12 L137-158
    below = o.K[o.K <= F]; above = o.K[o.K >= F]
    if below.empty or above.empty: return None
    K0, K1 = below.max(), above.min()        # K0==K1 iff a put strike == F exactly: rare but reachable
                                             # (e.g. r_pct == 0 and S0 on a listed strike); keep SAS behaviour (P6)

    # counts                                                        # T12 L164-180, L444
    n_put, n_call = int((o.cp == 'P').sum()), int((o.cp == 'C').sum())
    if n_put < 1 or n_call < 1 or (n_put + n_call) <= 2: return None

    # Simpson Delta-K                                               # T12 L198-210
    K = o.K.to_numpy(); n = len(K)                                  # n >= 3 here
    dK = np.empty(n)
    dK[1:-1] = (K[2:] - K[:-2]) / 2
    dK[0]    = K[1] - K[0]                                          # FULL spacing at edges
    dK[-1]   = K[-1] - K[-2]
    w = 2 * dK / K**2                                               # T12 L213
    i0 = np.where(K == K0)[0]; i1 = np.where(K == K1)[0]
    w[i0] += (K1 - K0 - dK[i0]) / 3 / K0**2                         # T12 L216 (uses that option's own dK)
    w[i1] += (K1 - K0 - dK[i1]) / 3 / K1**2                         # T12 L217 (both applied if K0==K1)

    sigma2     = np.nansum(w * o.mid.to_numpy())                    # PROC MEANS sum skips missing
    sigma2_bid = np.nansum(w * o.bid.to_numpy())
    sigma2_ask = np.nansum(w * o.ask.to_numpy())

    a = (K1-K0)/3 * (1/K0**2 - 1/K1**2) + (2/F - 1/K0 - 1/K1)       # stock shares
    b = (K1-K0)/3 * (1/K1 - 1/K0) + (math.log(F/K0) + math.log(F/K1))  # bond face paid at T
    VIX_Prc     = sigma2     + a*S0 + b/Rf                          # T12 L343
    VIX_Prc_bid = sigma2_bid + a*S0 + b/Rf                          # T12 L348
    VIX_Prc_ask = sigma2_ask + a*S0 + b/Rf                          # T12 L349
    if not (VIX_Prc_bid > 0): return None                           # T12 L351
    VIX_BA_percent = (VIX_Prc_ask - VIX_Prc_bid) / VIX_Prc          # T12 L350

    # terminal payoff                                               # T12 L285-291, L340
    payoff = np.where(o.cp == 'C', np.maximum(ST - K, 0), np.maximum(K - ST, 0))
    static_payoff = np.sum(w * payoff) + a*ST + b

    # corridor barriers                                             # T12 L230-239, L364-370
    KL = K[0]  - dK[0]/2                                            # dK[0]  = K[1]-K[0]
    KH = K[-1] + dK[-1]/2                                           # dK[-1] = K[-1]-K[-2]
    clip = lambda x: min(max(x, KL), KH)

    # daily model-free corridor hedge                               # T12 L378-408
    R = math.exp(r_pct/100/365)                                     # gross 1-calendar-day factor, month's single rate
    T = exdate_trade
    rows = [(d, c, rt) for (d, c, rt) in daily if t0 <= d <= exdate] # SAS window uses exdate (see pitfall P3)
    assert rows and rows[0][0] == t0                                # the t0 row exists since S0 exists
    isna = lambda x: x is None or np.isnan(x)
    # SAS: missing close -> missing Forward_daily (L384) -> L388 `if Forward_daily<KL` is TRUE -> clipped to KL
    clip_sas = lambda x: KL if isna(x) else clip(x)
    H_corr = []; H_plain = []; theory = []
    for (d_prev, c_prev, _), (d, c, rt) in zip(rows[:-1], rows[1:]):
        F_prev = np.nan if isna(c_prev) else c_prev * math.exp(r_pct/100 * (T - d_prev).days/365)
        F_now  = np.nan if isna(c)      else c      * math.exp(r_pct/100 * (T - d).days/365)
        Fb_prev, Fb_now = clip_sas(F_prev), clip_sas(F_now)
        gap = (d - d_prev).days                                     # calendar days incl. weekends
        carry = R ** ((T - d).days)                                 # carry gain to T (exponent 0 on T)
        # each term is appended only when SAS would compute it non-missing (PROC MEANS skips missing)
        if not isna(rt):                                            # L395 needs ret only
            H_plain.append(2/(R**((T - d_prev).days)) * (1 + rt - R**gap) * carry)   # T12 L395
            if not isna(c_prev):                                    # L398 also needs lag(prc)
                H_corr.append(2/Fb_prev * c_prev * (1 + rt - R**gap) * carry)        # T12 L398
        if not isna(F_now):                                         # L401 needs prc(d), NOT ret;
            theory.append(2*(F_now/Fb_now)*(Fb_now/Fb_prev - 1))    # T12 L401 (Fb_prev = KL if prev close missing)
    hedge_corr = sum(H_corr) if H_corr else np.nan                  # PROC MEANS: all-missing -> missing
    hedge_plain = sum(H_plain) if H_plain else np.nan
    theory_sum = sum(theory) if theory else np.nan

    static_short = -2 * (ST/S0/Rf - 1)                              # zero-cost short of 2/F shares, t0..T
    dyn_corr_payoff = static_payoff + static_short + hedge_corr     # T12 L431
    ret_corr  = dyn_corr_payoff / VIX_Prc - 1                       # T12 L432  Dynamic_VIX_Return_Corridor
    ret_plain = (static_payoff + static_short + hedge_plain) / VIX_Prc - 1   # T12 L427-428
    rf = Rf - 1                                                     # T12 L835 `Rf=Rf-1`
    RV_corr = -2*math.log(clip(ST)/clip(F)) + theory_sum            # T12 L434 (diagnostic)
    return dict(exdate_trade=T, VIX_Prc=VIX_Prc, VIX_BA_percent=VIX_BA_percent,
                ret_corr=ret_corr, ret_plain=ret_plain, rf=rf,
                exret_corr=ret_corr - rf,                           # vix_all (sorting) / vix_posoi (holding)
                VSR_Corridor=RV_corr/VIX_Prc - 1,
                num_put=n_put, num_call=n_call, K0=K0, K1=K1, F=F, KL=KL, KH=KH)
```

Notes on (a):
- In the SAS code, `daily` rows are CRSP rows. Rows with `ret=.B` or `ret=.C` were deleted before this step (T12 L34), so their prices are unavailable too.
- A day missing from the stock file is skipped. The next day's `gap` then spans it. In our port `ret` is close/previous-available-close − 1. UNCERTAIN for SAS: `stock_ret` is CRSP's own `ret` (L380), whose base is CRSP's prior valid price, not necessarily the last row kept in `stock_prc` (e.g. when that row was deleted at L34 as `.B`/`.C`).
- A missing `ret` makes the `Delta_Hedge_Reinvt` (L395) and `Delta_Hedge_Corridor` (L398) terms missing, and PROC MEANS skips them. `Delta_Hedge_Corridor_Theory` (L401) does not use `ret` and is still included. The SAS `lag()` still advances, so the next term uses the true previous row; the loop over consecutive rows reproduces that. This affects only the diagnostic `RV_Corridor`/`VSR_Corridor`, not `ret_corr`.
- A missing daily close (`prc`) is clipped to K_L at L388 (SAS missing < any number). That day's L398 term is still computed if `ret` exists (it uses the previous row's close); the next day's L398 term is missing (`lag(St_daily_Corridor)` missing) and skipped, not NaN for the whole month; that day's L401 term is missing, and the next day's L401 term uses K_L as the lag (a spurious Theory term). The pseudo-code reproduces all of this.
- `num_put`/`num_call` are counted on the final option set, after the OTM, arbitrage and K0/K1 steps (T12 L164–180).

### (b) Signal and quintile sort (WP Table 5 row "3,6,9,12" = final Table 4 Panel A `%seas(1,12,3,2)`)

```python
import math, numpy as np, pandas as pd

LAGS = (3, 6, 9, 12)                   # FH L70: keep num_lag % 3 == 0 within [1,12]
NEED = math.ceil(2*len(LAGS)/3)        # FH L77: n >= 2K/3  -> 3 of 4

# sort_panel: one row per (secid, exdate_trade) from the SORTING sample (no OI / zero-bid filters)
# hold_panel: one row per (secid, exdate_trade) from the HOLDING sample
sort_panel['ym'] = sort_panel.exdate_trade.dt.to_period('M')
sort_panel['vix_all'] = sort_panel.ret_corr - sort_panel.rf           # T4A L31 (own rf)
hold_panel['vix_posoi'] = hold_panel.ret_corr - hold_panel.rf

base = sort_panel.merge(hold_panel[['secid','exdate_trade','vix_posoi']],
                        on=['secid','exdate_trade'], how='left')      # T4A L33-34 (LEFT join from sorting)

# formation signal: calendar-month lags of exdate_trade, NOT row shifts
all_months = pd.period_range(base.ym.min(), base.ym.max(), freq='M', name='ym')   # name= is required:
                                      # reindex onto an unnamed index drops the 'ym' name and the merge below fails
wide = base.pivot(index='ym', columns='secid', values='vix_all').reindex(all_months)
lagged = [wide.shift(k) for k in LAGS]                                # shift on a COMPLETE monthly index
cnt  = sum(x.notna().astype(int) for x in lagged)
tot  = sum(x.fillna(0.0) for x in lagged)
fvar = (tot / cnt).where(cnt >= NEED)                                 # FH L74 mean of available lags
fvar = fvar.stack().rename('fvar').reset_index()                      # (ym, secid, fvar)

d3 = base.merge(fvar, on=['ym','secid'], how='inner')                 # FH L136-140: row must exist at t in sorting sample
d3 = d3[d3.fvar.notna()]

def month_sort(g):
    n = len(g)                                                        # N counts stocks even if vix_posoi is NaN
    r = g.fvar.rank(method='min').astype(int)                         # PROC RANK TIES=LOW
    q = (r*5) // (n+1) + 1                                            # SAS GROUPS=5 formula, groups 1..5
    ew = g.groupby(q).vix_posoi.mean()                                # HL L48 (NaN-skipping)
    out = {f'Q{k}': ew.get(k, np.nan) for k in range(1, 6)}
    out['HL'] = out['Q5'] - out['Q1']                                 # HL L71 (NaN if an extreme is empty)
    out['num_firm'] = int((g.vix_posoi.notna() & g.fvar.notna()).sum())   # T4A L57
    return pd.Series(out)

# SAS groups by exact date_var (= exdate_trade); one exdate_trade per month (verified on Fig.4 dates)
ports = d3.groupby('exdate_trade').apply(month_sort)                  # monthly series indexed by exdate_trade
```

Variants (NEED = ceil of the SAS `having` threshold; all thresholds are exact multiples of 1/3):
- Lag {3} (`%seas(1,3,3,1)`): `LAGS = (3,)`, `NEED = 1`.
- Lags 3..36 (`%seas(1,36,3,3)`): `LAGS = range(3,37,3)`, `NEED = 8`.
- Lag {12} (`%seas(1,12,12,4)`): `NEED = 1`.
- Lags {12,24,36} (`%seas(1,36,12,5)`): `NEED = 2`.
- Momentum 2..12: `LAGS = range(2,13)`, `NEED = 8` (FH2 L54: `(max-min+1)*2/3`). Momentum 2..36: `range(2,37)`, `NEED = 24`.
- Table 6 "All" 1..12 (`Table6_all_to_non_annual.sas` L41–43 via FH2 with `form_minlag=1`): `LAGS = range(1,13)`, `NEED = 8` (includes lag 1).
- Table 6 "Non-quarterly" 1..12 (`%seas(1,12,3,1)`, L138, via `form_hold_period_seas_other_2th.sas` L70/L77): `LAGS = (1,2,4,5,7,8,10,11)`, `NEED = 6`.
- Table 6 "Non-annual" (`%seas(1,12,12,7)`, L145, seas_other): `LAGS = range(1,12)`, `NEED = 8`.
- Table 6 "Quarterly non-annual" (`Table6_quarterly_not_annual.sas` L85 `%seas(1,11,3,1);`, FH): `LAGS = (3,6,9)`, `NEED = 2`.
- General non-seasonal rule (seas_other L77): K = (max−min+1) − (floor(max/p) − ceil(min/p) + 1) non-multiples of p in the window, `NEED = ceil(2*K/3)`.

### (c) Statistics (mean, NW t, SD, Sharpe, skew, kurtosis numerically verified on the package's Figure 4 series; MaxDD only consistent — needs the actual month-by-month rf)

```python
def nw_t(x, L=3):                         # GMM L45: kernel=(bart,L+1,0), vardef=n
    x = np.asarray(pd.Series(x).dropna()); T = len(x); e = x - x.mean()
    S = e @ e / T
    for j in range(1, L+1):
        S += 2 * (1 - j/(L+1)) * (e[j:] @ e[:-j]) / T
    return x.mean() / np.sqrt(S / T)      # reproduces 14.80 / 13.64 / 8.99 / 12.23

def sharpe_monthly(x):  x = pd.Series(x).dropna(); return x.mean() / x.std(ddof=1)   # GMM L15
def moments(x):         x = pd.Series(x).dropna(); return x.mean(), x.std(ddof=1), x.skew(), x.kurt()  # T5S L47 (excess kurt)

def sign_flip(x):       return -x if pd.Series(x).mean() < 0 else x                # T5S L43-44 (risk table only)

def max_drawdown(hl, rf):                 # T5S L60-107; hl and rf aligned by month of exdate_trade
    # hl = the SIGN-FLIPPED series ew_ret_p (T5S L70; Table5_Non_Seasonal L52), same series as moments/Sharpe.
    # rf = first row's rf per exdate_trade (T5S L60 nodupkey); months with no rf row are DROPPED (inner join L62-66).
    rr  = 1 + hl.fillna(0.0) + rf.fillna(0.0)          # SAS sum() ignores missing args
    cum = rr.cumprod().to_numpy()
    vals = [cum[t] / cum[:t].max() - 1 for t in range(1, len(cum))]   # strictly earlier peak, no initial 1
    return min(-min(vals), 1.0)
```

Missing months: `nw_t` drops NaN months and treats the rest as consecutive. That this matches PROC MODEL's handling is UNCERTAIN. The published series have no interior gaps, so it is untested there.

---

## 4. Published target numbers

### 4.1 WP Table 5, p.49 (final Table 4): quintile sorts, mean monthly excess return (NW3 t), average monthly #firms

| Formation lags | Low | 2 | 3 | 4 | High | **H−L** | #firms |
|---|---|---|---|---|---|---|---|
| 3 | −0.1990 (−13.77) | −0.1594 (−9.98) | −0.1291 (−6.86) | −0.0980 (−5.10) | −0.0815 (−4.49) | **0.1175 (13.06)** | 692.5 |
| **3,6,9,12** | −0.2167 (−12.99) | −0.1616 (−9.48) | −0.1257 (−6.82) | −0.0975 (−4.73) | −0.0745 (−3.99) | **0.1422 (14.80)** | 666.0 |
| 3,6,…,36 | −0.2084 (−12.16) | −0.1667 (−9.58) | −0.1221 (−6.23) | −0.0990 (−4.59) | −0.0724 (−3.32) | **0.1360 (12.23)** | 597.9 |
| 12 | −0.1676 (−9.35) | −0.1493 (−7.66) | −0.1270 (−6.81) | −0.1052 (−5.37) | −0.0830 (−4.47) | **0.0846 (9.39)** | 650.1 |
| 12,24,36 | −0.1781 (−10.11) | −0.1481 (−7.49) | −0.1204 (−6.30) | −0.1034 (−4.62) | −0.0859 (−4.25) | **0.0922 (9.33)** | 606.5 |
| Mom 2,…,12 | −0.2270 (−12.86) | −0.1598 (−10.20) | −0.1298 (−7.46) | −0.0978 (−5.19) | −0.0834 (−4.52) | **0.1436 (13.90)** | 543.2 |
| Mom 2,…,36 | −0.2086 (−11.86) | −0.1515 (−8.86) | −0.1259 (−6.61) | −0.0958 (−4.90) | −0.0903 (−4.26) | **0.1183 (9.35)** | 463.5 |
| Short-term momentum (Panel C) | −0.1921 (−15.04) | −0.1410 (−9.78) | −0.1264 (−7.91) | −0.0944 (−5.24) | −0.1084 (−5.76) | **0.0836 (7.38)** | 595.6 |

The txt scrambles the cell labels. The values are present in the txt (L2001–2104) and their labels were mapped using PDF word coordinates (re-checked for the Panel C rows: PDF p.49 reads "Short-term momentum -0.1921 -0.1410 -0.1264 -0.0944 -0.1084 0.0836 595.6"). The code for the Short-term momentum row is **not in the package** (T4A has only `%seas` calls, T4B only `%mom(2,12,7); %mom(2,36,8);`); that it is a lag-1 sort (FH2 with min = max = 1, NEED = 1) is UNCERTAIN. The H−L values for {3,6,9,12} and {3..36} were re-derived exactly from the package data (§4.3).

### 4.2 WP Table 6, p.50 (final Table 5): H−L risk and return, monthly decimals

| Strategy | Mean (t) | SD | Sharpe | Skew | Kurt (excess) | MaxDD |
|---|---|---|---|---|---|---|
| **Seasonal mom 3,6,9,12** | 0.1422 (14.80) | 0.149 | 0.956 | 1.024 | 7.80 | 0.373 |
| Seasonal mom 3,…,36 | 0.1360 (12.23) | 0.184 | 0.739 | 2.363 | 20.45 | 0.406 |
| Momentum 2–12 | 0.1436 (13.90) | 0.155 | 0.927 | 0.038 | 1.06 | 0.611 |
| HV − IV | 0.1375 (9.96) | 0.188 | 0.732 | 2.621 | 19.60 | 0.378 |
| Idiosyncratic vol (sign-flipped) | 0.0403 (2.18) | 0.307 | 0.132 | 8.731 | 116.01 | 0.982 |
| Market cap | 0.0603 (2.53) | 0.400 | 0.151 | 9.488 | 128.10 | 0.996 |
| IV term spread | 0.0918 (7.34) | 0.195 | 0.471 | 4.794 | 46.60 | 0.525 |
| IV smile slope | 0.0182 (2.61) | 0.112 | 0.163 | 0.103 | 1.64 | 0.861 |
| Short SPX VIX | 0.1709 (1.74) | 1.695 | 0.101 | −13.857 | 217.80 | > 1 (code caps at 1) |
| Short EW stock VIX | 0.1232 (7.20) | 0.280 | 0.439 | −4.267 | 34.32 | > 1 |

Text on p.29: "monthly Sharpe ratio of 0.956, or 3.31 annualized". The abstract (p.1) calls it an "annualized pre-cost Sharpe ratio of 3.31".

Notes on this table:
- The two seasonal rows come from T5S; every other row comes from the `Factors.sas` → `Factors_psigned.sas` → `Table5_Non_Seasonal.sas` pipeline (row 49), whose sample is restricted to months present in `here.index_simpson_return`.
- **HV − IV sort direction.** The designated WP copy labels the row "HV - IV" (txt L2191, L2283), with Table 5 H−L +0.1375 (9.96). The SSRN copy (`papers/HJKLM_SeasonalMomentum_WP_Jun2022_SSRNcopy.txt`) labels it "IV-HV" / "IV - HV" (L2239, L2332) with Table 5 H−L −0.1375 (−9.96) (L2158, L2165); both copies print the same flipped risk-table values. The WP text p.29 (txt L1183) says "The IV-HV difference". The code variable is `iv_hv` (Factors.sas L81), whose definition is not in the package. The sort direction is therefore UNCERTAIN; the sign-flipped risk-table row is the same either way.

**WP Table 7, p.51 (final Table 6), lags 1–12 column, H−L (t):**
- All: 0.1392 (13.64)
- Quarterly: 0.1422 (14.80)
- Non-quarterly: 0.1179 (8.99)
- Annual: 0.0846 (9.39)
- Non-annual: 0.1438 (11.88)
- Quarterly non-annual (3,6,9): 0.1366 (14.55)

**Firm-month level targets:**
- Sample: 221,157 firm-months; 1,464,062 contracts; 6.62 options per portfolio (p.20). Table 1 ("Simulation study") Panel B "Simulation parameters" (p.45, stated to match the actual sample): 3.06 calls and 3.56 puts on average.
- WP Table 3 Panel C (p.47), Simpson "model-free corridor hedge" return, monthly %: mean −11.30, SD 84.93, P10 −68.29, median −29.45, P90 56.63.
- WP Table 4 (p.48), Panel C "Simpson's", row "Corr(VIX portfolio with model-free corridor hedge, Corridor variance swap)": mean 0.92, median 0.99 (txt L1981–1986). The CBOE and Rectangle panels give 0.77 / 0.82.

### 4.3 Targets on OUR data window, derived from the package's Figure 4 series

Source: `code/Figures/Figure 4/seas_1_12_3_.txt`.
- Columns: yyyymmdd, date9, All(1..12), Quarterly(3,6,9,12), Non-quarterly.
- Full-sample check with the §3(c) formulas:
  - Quarterly: N = 290, 0.1422 (14.80), SD 0.149, SR 0.956, skew 1.024, kurt 7.80. This is an **exact** match to WP Tables 5 and 6.
  - All: 0.1392 (13.64).
  - Non-quarterly: 0.1179 (8.99).
- `seas_1_36_3_.txt`, Quarterly(3..36): 0.1360 (12.23), SD 0.184, SR 0.739, skew 2.363, kurt 20.45. **Exact** match.
- File coverage: `seas_1_12_3_.txt` 19961018–20201218 (291 rows; Quarterly N = 290, first value 19961115). `seas_1_36_3_.txt` 19980116–20201218 (276 rows; All and Quarterly 3..36 N = 275, first value 19980220).
- MaxDD is **not** reproduced exactly. With rf = 0: 0.3757 (3,6,9,12; peak 2002-06-21, trough 2002-08-16 via monthly H−L −0.357560 and −0.028262) and 0.4105 (3..36; single month 2007-02-16 → 2007-03-16, H−L −0.410498). Published: 0.373 and 0.406. Both 28-day months need a per-month rf of 0.137%–0.199% (≈1.79–2.59%/yr cont. comp., if equal in both months) to round to 0.373, and the 2007 month needs 0.400%–0.500% (≈5.20–6.50%/yr) to round to 0.406. Each published value sits near a rounding boundary. UNCERTAIN until checked against the actual OM-level rf for those months.
- The col-3 "All" values in the 1_36 file (mean 0.1233) are lags 1..36: `Figure4.m` L79 titles Panel B "Lags 1 to 36" and L66 labels col 3 "All"; the WP Fig. 4 caption (p.44, txt L1557–1560) says "Panel B uses 36 months. In each panel, we show the strategy based on all lags …"; and the first value on 19980220 is what 24-of-36 lags 1..36 implies from a Feb-1996 start (lags 2..36 would first appear in 1998-03). No published number exists for it, so it is not a validated target.

Subsample targets, by holding months (`exdate_trade`), computed from these files:

| Window (holding months) | Series | N | Mean | NW3 t | SD | SR (monthly) |
|---|---|---|---|---|---|---|
| 2014-02 … 2020-12 (first month a {3,6,9,12} signal can exist if OPRA starts 2013-04) | Quarterly 3,6,9,12 | 83 | 0.1271 | 7.31 | 0.174 | 0.731 |
| same | All 1..12 | 83 | 0.1217 | 7.39 | 0.144 | 0.843 |
| same | Non-quarterly (1..12) | 83 | 0.1187 | 5.35 | 0.228 | 0.521 |
| 2013-05 … 2020-12 | Quarterly 3,6,9,12 | 92 | 0.1221 | 7.33 | 0.171 | 0.712 |
| 1996-10 … 2013-04 (pre-OPRA) | Quarterly 3,6,9,12 | 198 | 0.1515 | 13.16 | 0.136 | 1.112 |
| 2016-01 … 2020-12 | Quarterly 3,6,9,12 | 60 | 0.1308 | 5.93 | 0.191 | 0.686 |
| 2016-01 … 2020-12 | Quarterly 3..36 | 60 | 0.1157 | 3.60 | 0.260 | 0.445 |
| 2014-02 … 2020-12 | Quarterly 3..36 (our signal will not exist this early) | 83 | 0.1222 | 4.84 | 0.237 | 0.515 |

These files also give **month-by-month** targets for the overlap months. Report the correlation of our monthly H−L with the published one, and the mean difference.

---

## 5. Known pitfalls for porting

**SAS semantics**
- **P1. Missing values.** SAS missing sorts below every number.
  - `strike_price>forward` with a missing forward is TRUE, so all puts are deleted and the firm-month drops.
  - `best_bid>best_offer` with a missing ask deletes the row; with a missing bid it keeps the row.
  - `best_bid=0` keeps a missing bid. A missing-bid option then keeps its strike weight and payoff but contributes no price to `sigma2`/`sigma2_bid` (row 6).
  - A missing daily close is clipped to K_L at L388; the next day's L398 term is missing and skipped, and the next day's L401 Theory term uses K_L as the lag (§3(a) notes).
  - In Python, drop missing rates, forwards and quotes explicitly, or reproduce the SAS behaviour where §3(a) says so.
- **P2. `lag()` without BY reset** (T12 L395–401). It is correct only because the `date_daily=date` row is deleted afterwards (L404). Port it as consecutive-row differences within (secid, date), starting from the t0 row.
- **P3. Two daily windows.**
  - The model-free and corridor hedges and RV use `date <= d <= exdate` (L382).
  - The BS hedge uses `exdate_trade` (L466).
  - OM `exdate` is a Saturday before Feb-2015 (OM/OCC vendor convention, not verified from the package). The windows are equal as long as no session lies in (exdate_trade, exdate]; assert this.
  - The carry exponent is `exdate_trade − d` in **calendar** days.
- **P7. `nodupkey`** keeps the first row after a stable sort. At L109 (`by cusip date`), two secids sharing a cusip lose one secid's forward.
- **P8. Zero curve.** It is a natural cubic spline in days (`linear_rate` is misnamed). There are three rate conventions:
  - `exp(r·τ/365)` over the holding period;
  - `exp(r/365)` per calendar day in the hedge;
  - `log(1+r/36500)` in the BS hedge.
- **P9. PROC MEANS `sum`** skips missing terms; a group that is all missing gives missing.

**Portfolio construction**
- **P4. ΔK at the edges** is the full spacing (L209–210). The corridor then adds half of that edge ΔK.
- **P5. One option per strike.** The put/call OTM split (K ≤ F put, K > F call) guarantees it. Keeping both a put and a call at one strike (CBOE-style) breaks the lead/lag ΔK logic.
- **P6. K0 = K1** occurs only when a put strike exactly equals F. Both Simpson extras then land on one option and K1 − K0 = 0. Nothing in L111 or L137–151 rules it out: it is rare but reachable whenever F equals a listed strike exactly, e.g. a zero interpolated rate with S0 on a strike. Replicate the SAS behaviour, and count the cases in the port. UNCERTAIN: how often it occurs, and how often the chosen FRED series prints exactly 0 in 2013–2020.
- **P10. Stock/bond terms.** `a` and `b` are signed.
  - The static short `−2(S_T/(S0·Rf) − 1)` cancels the `2/F` part of `a` exactly, because F = S0·Rf uses the same r. Do not drop either piece.
  - `VIX_Prc_bid > 0` is tested **with** these terms included.
- **P11. Zero bids in the sorting sample.** They enter with mid = ask/2 and bid = 0 in `sigma2_bid`. The sorting sample can therefore **lose** firm-months that are in the holding sample, because a different option set changes K0/K1, ΔK and `VIX_Prc_bid`. Those holding returns are then **never used**: the base is a left join **from** the sorting sample.

**Signal and sort**
- **P12. Breakpoint universe.** Stocks with a valid signal but no holding return are ranked and set the breakpoints (FH L136–147, HL L10). Do not filter to `vix_posoi.notna()` before ranking.
- **P13. Calendar-month lags.** Lags are calendar months of `exdate_trade`. Use a complete monthly index before shifting; row-based `shift()` on a gappy panel is wrong.
- **P14. Required count.** It is `ceil(2K/3)`: 3 of 4 for {3,6,9,12}, not "2/3 rounded down".
- **P15. Quintiles are not `qcut`.** Use `floor(rank_min·5/(n+1)) + 1`. With small n the group sizes are uneven, e.g. n = 7 gives 1/2/1/2/1.
- **P16. Month labels.** The observation month is the **holding-period end month** (`date_var = exdate_trade`). The formation date is about one month earlier. Lag 1 is the return that ends *on* the formation date.

**Statistics**
- **P17. NW.** Bartlett weights 1 − j/(L+1), L = 3, divisor T, no small-sample correction. The statsmodels HAC defaults may differ, so use the explicit formula (verified).
- **P18. Monthly statistics.** Sharpe is monthly with ddof = 1. Kurtosis is **excess**. MaxDD compounds `1 + ret + rf`, peaks come from strictly earlier months, and the value is capped at 1.
- **P19. Sign flip** uses the full-sample mean (look-ahead) and applies only to the risk table. Never apply it in out-of-sample or holdout work.

**OPRA and data specifics**
- **P20. Expiry selection.**
  - Weeklies are present in OPRA. Select only the standard monthly expiry of month m+1.
  - OSI dates for monthlies are Saturdays before Feb-2015 (vendor/OCC convention, not verified from the package).
  - On Good Friday, expiry and formation both move to Thursday.
  - Adjusted/non-standard roots (a digit suffix) and mini options must be excluded. OM excludes them through a missing delta.
- **P21. Quote timing.** OM "closing" quotes vs our 15:59 ET `cbbo-1m` snapshot.
  - OM's exact snapshot time is UNCERTAIN. It may be 15:59 before March 2008 and 16:00 after; unverified.
  - The Databento `cbbo-1m` timestamp convention (interval start vs end) must be verified before use. UNCERTAIN.
  - The stock close is 16:00, one minute after the option snapshot.
- **P22. Sentinels.** Databento prices of INT64_MAX (undefined) are converted to NaN by `src/opra_download.py`. For the sorting sample, map an undefined bid to 0 when the ask is defined. UNCERTAIN whether OM stores a no-bid quote as 0 or as missing; the package does not say. In SAS a missing bid is kept in both samples with no price contribution (row 6), so this mapping is a deliberate deviation.
- **P23. Linking.** CRSP links are by CUSIP (T12 L48, L79, L102). We link OSI root to ticker. Watch for root≠ticker cases (class shares, ticker changes) and for delistings (no close on `exdate_trade` drops the firm-month, as in the code).
- **P24. Package gaps.** Not in the package: the construction of `here.options`, `here.options_daily`, `here.CRSP_stock_daily`, `here.ZeroCouponYieldCurve`, `here.dsedist`/`crsp.dsedist`; the Table 5 non-seasonal characteristics (`atmiv_termspread`, `slope`, `iv_hv`, `idiovol` read from `here.simpson_return` although T12 L836 does not keep them); `here.index_simpson_return` (SPX VIX return, Factors.sas L88); the Table 5 Panel C short-term momentum code; the script that writes the Figure 4 `.txt` files; and the `transaction_cost` data. Anything relying on them is out of scope or PROXY.

---

## 6. Data substitution plan (placeholder)

OptionMetrics, CRSP and Compustat are **unavailable**. The substitutes are:
- **OPRA NBBO**: Databento `OPRA.PILLAR` `cbbo-1m`, one minute at 15:59 ET on formation dates only.
- **DoltHub stocks**: raw daily OHLCV, dividends, splits and symbol metadata.
- **Risk-free rate**: FRED, or Ken French rf as a fallback.

**Cost note.** Option quotes are needed **only on formation dates**. The payoff uses the stock close on `exdate_trade`, and the hedge uses daily stock closes, so no option data is needed after formation. That means one `cbbo-1m` minute per month. Optional OI comes from the `statistics` schema on the same dates. Call `metadata.get_cost` before every pull and log it to `databento_pull_log.csv` (the existing ledger in `src/opra_download.py`).

| SAS field (source) | Used for | Our source / construction | Status |
|---|---|---|---|
| `secid`, `cusip` (OM / CRSP link) | firm identity, CRSP merge | OSI root → ticker via DoltHub symbol metadata; drop roots with a digit suffix | PROXY |
| `date` | formation date | last XNYS session ≤ 3rd Friday | EXACT |
| `exdate` | OM expiry | OSI expiration field of the selected monthly | EXACT |
| `exdate_trade` | holding end, τ, S_T, `date_var` | last XNYS session ≤ 3rd Friday of m+1 (matches the Fig. 4 dates, including Good Fridays) | EXACT |
| `cp_flag`, `strike_price` | OTM, weights | OSI symbol (strike/1000 already applied in `parse_osi`) | EXACT |
| `optionid` | only to merge daily OM deltas for the BS hedge (T12 L248, L456–503); **not** a de-dup key (de-dup keys: L23, L80) | OSI symbol | EXACT (equivalent) |
| `best_bid`, `best_offer` | mid, filters, `VIX_Prc_bid` | `cbbo-1m` bid_px_00 / ask_px_00 at 15:59 ET | PROXY (timing, consolidation) |
| `open_interest` | holding-sample OI > 0 | Databento OPRA `statistics` open interest on the formation date (UNCERTAIN availability and cost), else omit the filter | PROXY / UNCERTAIN |
| `delta`, `impl_volatility` | availability filter, `IV_avg`, IV-grid interpolation for the diagnostic `VSR_Corridor_Interpolate` (holding sample only, L717–822) | BS inversion on the mid with F and r; missing if no root | PROXY |
| `prc` (S0, S_T, daily S) | $5, forward, payoff, hedge | DoltHub raw (unadjusted) close | PROXY (vendor; CRSP's no-trade bid/ask midpoint, per CRSP documentation, is not replicated) |
| `ret` (daily) | hedge terms, RV | raw close_t / close_{t−1} − 1. Valid inside windows with no dividends or splits by construction. | PROXY (≈ EXACT given the filters) |
| `divamt` (dsf) | dividend exclusion | DoltHub dividend ex-dates in (date, exdate_trade] | PROXY (coverage) |
| `FACSHR`, `exdt` (dsedist) | split exclusion | DoltHub split ex-dates in (date, exdate_trade] | PROXY (coverage; CRSP counts other FACSHR≠0 events too) |
| `shrcd` | common shares 10/11 | DoltHub metadata: US common stock only | PROXY |
| `shrout` / `mkt_cap` | `mkt_cap` (T12 L309) is `vw_ret` weight (unused in EW sorts), the `mcap` regressor in the Table 8 FM regressions (`Table8_1.sas` L28, L36, L54), the first sort variable in the Table 10 double sorts (e.g. `Table10_size.sas` `sortvar1= mcap`), the "Market cap" factor in the risk table (Factors.sas L81), and carried as `mcap= mkt_cap` in Tables 6, 7 and 13 | DoltHub close × shares outstanding if those tables are ported; not needed for the 3,6,9,12 sort | N/A for the core sort |
| `ZeroCouponYieldCurve` | F, Rf, rf, hedge carry | FRED daily Treasury (DTB4WK/DGS1MO, interpolated to τ), as a continuously compounded percent | PROXY |
| `rf` for MaxDD | drawdown compounding | same rf per `exdate_trade` month | PROXY |

**EXACT.** Every formula and rule in §3:
- calendar and expiry selection;
- OTM, K0/K1, Simpson weights, stock/bond components;
- payoff, corridor hedge, excess returns;
- lags, missing-data rule, ranking, H−L;
- NW, Sharpe, moments, MaxDD.

**PROXY.** Every data input:
- quotes (timing and venue consolidation);
- OI;
- IV/delta availability;
- stock prices and corporate actions;
- share-code classification;
- risk-free rate;
- sample period, which covers only the OPRA-era overlap, about 2013-04 → 2020-11 formations, plus any extension.

Validate by comparing our monthly H−L with the §4.3 overlap targets and with the month-by-month Figure 4 series.

---

## 7. Verification log

Each issue raised by the three adversarial reports was re-checked against the source (T12 with CRLF stripped; SAS functions; Table 4/5/6/8/10 scripts; `Figures/Figure 2` and `Figure 4` files; WP txt and PDF word coordinates). "Fixed" means the spec now says what the source shows.

**Construction report (T12)**

| # | Issue | Verdict | Where / reason |
|---|---|---|---|
| F1 | Missing `ret` branch also dropped the L401 Theory term | **Fixed** | L401 has no `stock_ret`. §3(a) loop and notes rewritten; Theory kept when `ret` is missing. |
| F2 | No handling of a missing daily close | **Fixed, with a correction** | L384/L388/L398/L401 traced. The report said that day's L398 term is missing; it is missing only if `ret` is also missing (L398 uses the previous row's close). The next day's L398 term is missing; the next day's L401 term uses K_L. §3(a) loop, notes, P1. |
| F3 | Holding/sorting blocks differ in more than three ways; code-version question | **Fixed** | Own comment-stripped diff confirms: keep lists (L836 vs L1700), reused WORK tables, extra no-op statements, rows final at L444, output at L835–836, `crsp` libref unassigned. `Figure2_step1.sas` L30–37 reads `BS_VIX_Return` from the sorting file → UNCERTAIN code version (§1). Also added the same point for Factors.sas / Table8_1.sas characteristic columns. |
| F4 | Dividend check scope; ex-date claim unsupported | **Fixed** | L33–35, L43 confirmed; row 10 now scoped and marked UNCERTAIN. |
| F5 | `impl_volatility` also used in IV-grid interpolation | **Fixed** | L717, L747, L822 confirmed; row 8 and §6. |
| F6 | `optionid` is not a de-dup key | **Fixed** | Keys are L23/L80; `optionid` only at L248, L456–503. §6. |
| F7 | De-dup citation should include L80 | **Fixed** | §3(a) comment. |
| F8 | "SAME" overstates match to eq.(8) hedge | **Fixed** | L395 algebra checked: 2(1+ret−R^gap)/R^gap. Rows 26, 28. |
| F9 | K0 = K1 rare, not unreachable | **Fixed** | Nothing in L111/L137–151 excludes it. P6 and §3(a) comment. |
| F10 | "OM records no bid as 0" unsourced; missing-bid consequences undocumented | **Fixed** | L17–18, L124/126, L219–220, L285–287 traced. Row 6, P1, P22. |
| F11 | Vendor facts (OSI Saturday expiry; CRSP bid/ask midpoint) unsourced | **Fixed** | Labelled as vendor documentation in rows 4, 16, P3, P20, §6. |
| F12 | Row 14 names the wrong drop line | **Fixed** | Drop happens at L351 via missing `VIX_Prc_bid`. Row 14. |
| F13 | Base of CRSP `ret` across a gap is unverified | **Fixed** | Marked UNCERTAIN in §3(a) notes. |
| F14 | K0 quote context; "K1 is defined only by the code" | **Partly fixed, partly rejected** | Context added. Rejected the K1 claim: WP p.10 (txt L410) says "the next higher strike price K1"; quoted in row 21. |
| F15 | Calling the Fig. 2 caption a "typo" is an inference | **Fixed** | `Figure2_plot.m` L47/L58 and WP p.28 text quoted; row 28 reworded. |
| F16 | `mkt_cap` is not "VW only" | **Fixed** | Table8_1 L36/L54, Table10_size `sortvar1= mcap`, Factors.sas L81, Tables 6/7/13. §6. |
| F17 | Missing inputs; `shrcd_ok` docstring | **Fixed** | Row 1 adds `here.options_daily`, `crsp.dsedist`; §3(a) docstring. |

**Signal-and-stats report**

| # | Issue | Verdict | Where / reason |
|---|---|---|---|
| S1 | `reindex` onto unnamed PeriodIndex drops `ym` → merge KeyError | **Fixed** | Reproduced on pandas 3.0.6 (columns `level_0, secid, fvar`); `name='ym'` added in §3(b). |
| S2 | MaxDD called exactly verified | **Fixed, thresholds refined** | Recomputed rf=0: 0.3757 / 0.4105. Solved the rounding thresholds myself: ≈1.79%/yr (report said ≈1.75%) and ≈5.20%/yr (report said ≈5.21%). §1, row 44, §3(c), §4.3. |
| S3 | `seas_1_36_3_.txt` starts 19980116 | **Fixed** | §1, row 2, §4.3. |
| S4 | Stronger support for column labels / All 1..36 | **Fixed** | Figure4.m L20–26, L66, L74, L79; no writer script in the package. |
| S5 | Risk-table non-seasonal factors come from a different pipeline | **Fixed** | Factors.sas L58, L81–82, L88–110; Factors_psigned L33–42; Table5_Non_Seasonal L25. New row 49; P24. |
| S6 | Table 6 variant thresholds missing | **Fixed** | Table6_all_to_non_annual L41–43, L138, L145; Table6_quarterly_not_annual L85; seas_other L77. Also added Non-quarterly NEED = 6. §3(b), row 34. |
| S7 | MaxDD input is the sign-flipped series | **Fixed** | T5S L70; also documented the L60 nodupkey rf and L62–66 inner join. §3(c), row 44. |
| S8 | "Number of firms" misquote | **Fixed** | Header is "monthly # firms" (txt L2000). Row 46. |

**Paper-text report**

| # | Issue | Verdict | Where / reason |
|---|---|---|---|
| 1 | Figure 4 file date ranges | **Fixed** | Same as S3. |
| 2 | MaxDD "exact" | **Fixed** | Same as S2. |
| 3 | Scope of lag-1 exclusion | **Fixed** | fn.9 anchored at txt L1159 (Panel B sentence); WP Table 7 / p.30 include lag 1. Row 34. |
| 4 | p.51 caption not verbatim | **Fixed** | Row 2 quotes all three captions. |
| 5 | Share-code caption locations | **Fixed** | Row 3. |
| 6 | "monthly # firms"; "High - Low" | **Fixed** | Rows 40, 46. |
| 7 | txt line range L2006 → L2001 | **Fixed** | §4.1 note. |
| 8 | Short-term momentum row omitted | **Fixed** | Label confirmed from PDF p.49 word coordinates; added to §4.1. Its code is not in the package; construction marked UNCERTAIN. |
| 9 | Table 4 correlation panel | **Fixed** | Panel C "Simpson's", txt L1981–1986. §4.2. |
| 10 | Table 1 Panel B is "Simulation parameters" | **Fixed** | Panel B header at txt L1597, caption L1652–1654 (report's line numbers slightly off). Row 16, §4.2. |
| 11 | HV−IV vs IV−HV across WP copies | **Fixed** | Both PDFs checked by word coordinates. Note added to §4.2; direction UNCERTAIN. |
| 12 | Evidence for All 1..36 | **Fixed** | Merged with S4 in §4.3; still no published target. |
| 13 | OM zero curve may be LIBOR/Eurodollar-based | **Fixed as UNCERTAIN** | Not checkable from local files; row 18 flags it. |

No reported issue was rejected in full. One sub-claim was rejected (F14's "K1 defined only by the code"), and three were corrected in detail (F2 same-day term; S2 thresholds; paper-text 10 line numbers).
