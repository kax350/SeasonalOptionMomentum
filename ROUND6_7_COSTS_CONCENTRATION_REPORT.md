# ROUND 6–7 REPORT — Transaction costs, concentration, and $25k feasibility of the paper portfolio

All numbers use the paper construction: Simpson equity-VIX portfolios with the corridor hedge, held to expiry. Label: PROXY (OPRA 15:59 NBBO).
- Cost levels follow RESEARCH_LEDGER A3. Fill = mid ± e × half-spread, with e = 0, 0.25, 0.5, 1 (natural). COST4 is natural ± one tick per option.
- **COST0 already includes 2 bps on every daily stock-hedge trade.** That is why its quintile mean (0.133) is below the pure-mid 0.162.
- Options are held to expiration, so there is no exit spread. This is the most favourable case.
- Long leg = buy Q5 VIX portfolios; short leg = sell Q1.

## Headline

**The paper's pre-cost edge does not survive realistic option transaction costs.**

- Full-universe quintile H−L, annualised Sharpe:
  - COST0: **2.27** (2014–20) and **3.00** (2021–26)
  - COST1 (paying 25% of the half-spread): **0.63** and **0.44**
  - COST2 (50%): **−1.65** and **−3.18**
  - Natural: about −3.7
- Cause: the equity-VIX portfolio's quoted spread is enormous relative to its price. Median full spread / price is 62% in Q1 and 26% in Q5, and the short leg (Q1) is the illiquid side.
- The most liquid names (Ltight quintile) are the only paper-level portfolios still positive at COST2: SR +0.12 (2014–20) and +0.27 (2021–26).
- **Answer to Q5:** the 3.31 pre-cost Sharpe (paper sample) becomes roughly 0.4–0.6 with near-institutional execution (e = 0.25) and is negative at e ≥ 0.5.

## Cost diagnostics by quintile (median)

| Quintile | Quoted full spread / VIX price | Stock-hedge turnover per unit | Options per portfolio | VIX price | 2 bps hedge cost / price |
|---|---|---|---|---|---|
| Q1 | 62% | 0.93 | 5.3 | 0.0197 | 0.97% |
| Q2 | 55% | 0.86 | 6.4 | 0.0152 | 1.12% |
| Q3 | 45% | 0.83 | 7.9 | 0.0134 | 1.23% |
| Q4 | 34% | 0.83 | 10.5 | 0.0127 | 1.30% |
| Q5 | 26% | 0.89 | 15.3 | 0.0142 | 1.24% |

## Cost ladder × concentration (EXTREME-RANK COMPRESSION, pre-registered K)

**Universe P** — cell = mean monthly H−L excess return (annualised Sharpe)

| Portfolio | Period | COST0_mid | COST1_e25 | COST2_e50 | COST3_natural | COST4_nat_1tick |
|---|---|---|---|---|---|---|
| quintile | 2014–20 | +0.133 (+2.27) | +0.034 (+0.63) | -0.081 (-1.65) | -0.666 (-3.80) | -0.670 (-5.52) |
| quintile | 2021–26 | +0.128 (+3.00) | +0.017 (+0.44) | -0.117 (-3.18) | -0.903 (-3.70) | -0.948 (-7.44) |
| K20 | 2014–20 | +0.176 (+1.84) | +0.072 (+0.78) | -0.046 (-0.51) | -0.554 (-3.29) | -0.625 (-3.94) |
| K20 | 2021–26 | +0.104 (+1.43) | -0.000 (-0.00) | -0.127 (-1.63) | -1.028 (-1.18) | -0.807 (-4.84) |
| K10 | 2014–20 | +0.160 (+1.49) | +0.058 (+0.55) | -0.060 (-0.57) | -0.623 (-2.48) | -0.667 (-3.49) |
| K10 | 2021–26 | +0.096 (+1.00) | -0.009 (-0.09) | -0.135 (-1.33) | -0.662 (-4.98) | -0.820 (-3.98) |
| K5 | 2014–20 | +0.171 (+1.11) | +0.070 (+0.46) | -0.045 (-0.30) | -0.594 (-1.37) | -0.567 (-2.15) |
| K5 | 2021–26 | +0.108 (+0.86) | +0.005 (+0.04) | -0.119 (-0.87) | -0.631 (-3.20) | -0.844 (-2.18) |
| K3 | 2014–20 | +0.206 (+0.98) | +0.109 (+0.53) | -0.002 (-0.01) | -0.665 (-0.94) | -0.579 (-1.44) |
| K3 | 2021–26 | +0.051 (+0.28) | -0.052 (-0.27) | -0.175 (-0.87) | -0.709 (-2.54) | -1.009 (-1.64) |
| K2 | 2014–20 | +0.188 (+0.88) | +0.094 (+0.45) | -0.012 (-0.06) | -0.785 (-0.80) | -0.597 (-1.26) |
| K2 | 2021–26 | +0.095 (+0.42) | -0.004 (-0.02) | -0.121 (-0.49) | -0.621 (-1.84) | -1.004 (-1.12) |
| K1 | 2014–20 | +0.091 (+0.27) | -0.010 (-0.03) | -0.127 (-0.38) | -1.187 (-0.67) | -0.618 (-1.46) |
| K1 | 2021–26 | +0.103 (+0.39) | +0.007 (+0.03) | -0.108 (-0.40) | -0.559 (-1.52) | -0.643 (-1.72) |

**Universe L** — cell = mean monthly H−L excess return (annualised Sharpe)

| Portfolio | Period | COST0_mid | COST1_e25 | COST2_e50 | COST3_natural | COST4_nat_1tick |
|---|---|---|---|---|---|---|
| quintile | 2014–20 | +0.099 (+0.71) | +0.053 (+0.36) | +0.006 (+0.04) | -0.094 (-0.53) | -0.132 (-0.71) |
| quintile | 2021–26 | +0.021 (+0.12) | -0.039 (-0.23) | -0.104 (-0.60) | -0.258 (-1.39) | -0.295 (-1.56) |
| K20 | 2014–20 | +0.016 (+0.22) | -0.027 (-0.35) | -0.070 (-0.89) | -0.163 (-1.85) | -0.209 (-2.30) |
| K20 | 2021–26 | +0.073 (+1.05) | +0.021 (+0.31) | -0.034 (-0.52) | -0.160 (-2.42) | -0.192 (-2.89) |
| K10 | 2014–20 | +0.035 (+0.32) | -0.010 (-0.09) | -0.056 (-0.49) | -0.154 (-1.27) | -0.198 (-1.62) |
| K10 | 2021–26 | +0.079 (+0.93) | +0.026 (+0.32) | -0.029 (-0.36) | -0.159 (-1.96) | -0.191 (-2.34) |
| K5 | 2014–20 | +0.052 (+0.34) | +0.005 (+0.03) | -0.043 (-0.27) | -0.145 (-0.89) | -0.188 (-1.13) |
| K5 | 2021–26 | +0.103 (+0.87) | +0.049 (+0.42) | -0.009 (-0.08) | -0.148 (-1.27) | -0.180 (-1.54) |
| K3 | 2014–20 | +0.036 (+0.17) | -0.011 (-0.05) | -0.059 (-0.27) | -0.162 (-0.69) | -0.202 (-0.86) |
| K3 | 2021–26 | +0.121 (+0.77) | +0.067 (+0.43) | +0.008 (+0.05) | -0.134 (-0.84) | -0.167 (-1.05) |
| K2 | 2014–20 | +0.038 (+0.14) | -0.010 (-0.04) | -0.059 (-0.21) | -0.163 (-0.56) | -0.202 (-0.69) |
| K2 | 2021–26 | +0.098 (+0.48) | +0.044 (+0.21) | -0.015 (-0.07) | -0.153 (-0.74) | -0.188 (-0.91) |
| K1 | 2014–20 | +0.014 (+0.05) | -0.035 (-0.11) | -0.085 (-0.27) | -0.189 (-0.57) | -0.232 (-0.69) |
| K1 | 2021–26 | -0.001 (-0.00) | -0.058 (-0.18) | -0.119 (-0.36) | -0.257 (-0.79) | -0.294 (-0.91) |

**Universe Ltight** — cell = mean monthly H−L excess return (annualised Sharpe)

| Portfolio | Period | COST0_mid | COST1_e25 | COST2_e50 | COST3_natural | COST4_nat_1tick |
|---|---|---|---|---|---|---|
| quintile | 2014–20 | +0.063 (+0.66) | +0.037 (+0.39) | +0.011 (+0.12) | -0.043 (-0.45) | -0.076 (-0.79) |
| quintile | 2021–26 | +0.106 (+1.24) | +0.065 (+0.78) | +0.021 (+0.27) | -0.078 (-1.11) | -0.117 (-1.70) |
| K20 | 2014–20 | -0.025 (-0.31) | -0.054 (-0.65) | -0.083 (-0.96) | -0.142 (-1.55) | -0.198 (-2.07) |
| K20 | 2021–26 | +0.025 (+0.40) | -0.017 (-0.26) | -0.061 (-0.92) | -0.160 (-2.15) | -0.196 (-2.58) |
| K10 | 2014–20 | -0.024 (-0.22) | -0.053 (-0.47) | -0.082 (-0.71) | -0.142 (-1.16) | -0.196 (-1.56) |
| K10 | 2021–26 | +0.080 (+1.01) | +0.037 (+0.47) | -0.008 (-0.11) | -0.111 (-1.35) | -0.148 (-1.79) |
| K5 | 2014–20 | -0.067 (-0.36) | -0.098 (-0.52) | -0.130 (-0.67) | -0.196 (-0.98) | -0.252 (-1.22) |
| K5 | 2021–26 | +0.040 (+0.33) | -0.002 (-0.02) | -0.047 (-0.39) | -0.149 (-1.24) | -0.185 (-1.54) |
| K3 | 2014–20 | -0.066 (-0.32) | -0.099 (-0.47) | -0.133 (-0.61) | -0.205 (-0.89) | -0.261 (-1.10) |
| K3 | 2021–26 | +0.002 (+0.02) | -0.040 (-0.29) | -0.084 (-0.61) | -0.190 (-1.30) | -0.226 (-1.54) |
| K2 | 2014–20 | -0.052 (-0.27) | -0.086 (-0.44) | -0.121 (-0.61) | -0.194 (-0.96) | -0.250 (-1.20) |
| K2 | 2021–26 | -0.008 (-0.05) | -0.049 (-0.31) | -0.093 (-0.59) | -0.197 (-1.20) | -0.232 (-1.42) |
| K1 | 2014–20 | -0.012 (-0.05) | -0.047 (-0.20) | -0.084 (-0.34) | -0.161 (-0.61) | -0.215 (-0.79) |
| K1 | 2021–26 | -0.024 (-0.11) | -0.063 (-0.30) | -0.105 (-0.49) | -0.200 (-0.90) | -0.238 (-1.07) |

**Leg decomposition, universe P quintiles** (mean monthly excess return of the long-Q5 leg / the Q1 leg that is shorted; H−L = Q5 − Q1)

| Cost | Period | Q5 (long) | Q1 (shorted) | H−L |
|---|---|---|---|---|
| COST0_mid | 2014–20 | -0.076 | -0.209 | +0.133 |
| COST0_mid | 2021–26 | -0.126 | -0.253 | +0.128 |
| COST1_e25 | 2014–20 | -0.109 | -0.142 | +0.034 |
| COST1_e25 | 2021–26 | -0.161 | -0.178 | +0.017 |
| COST2_e50 | 2014–20 | -0.138 | -0.057 | -0.081 |
| COST2_e50 | 2021–26 | -0.192 | -0.075 | -0.117 |
| COST3_natural | 2014–20 | -0.190 | +0.477 | -0.666 |
| COST3_natural | 2021–26 | -0.245 | +0.658 | -0.903 |
| COST4_nat_1tick | 2014–20 | -0.204 | +0.466 | -0.670 |
| COST4_nat_1tick | 2021–26 | -0.255 | +0.692 | -0.948 |

**Pre-registered SKIP-MONTH rule** (skip when top-K minus bottom-K score spread < 20th pct of its 2014–2020 distribution), universe L, COST1

| K | Period | no skip | with skip |
|---|---|---|---|
| K10 | 2014–20 | -0.010 (-0.09) | -0.024 (-0.20) n=66 |
| K10 | 2021–26 | +0.026 (+0.32) | +0.030 (+0.35) n=63 |
| K5 | 2014–20 | +0.005 (+0.03) | -0.012 (-0.07) n=66 |
| K5 | 2021–26 | +0.049 (+0.42) | +0.054 (+0.45) n=62 |
| K3 | 2014–20 | -0.011 (-0.05) | -0.037 (-0.16) n=66 |
| K3 | 2021–26 | +0.067 (+0.43) | +0.065 (+0.40) n=61 |
| K2 | 2014–20 | -0.010 (-0.04) | -0.045 (-0.15) n=66 |
| K2 | 2021–26 | +0.044 (+0.21) | +0.043 (+0.20) n=60 |
| K1 | 2014–20 | -0.035 (-0.11) | -0.109 (-0.33) n=66 |
| K1 | 2021–26 | -0.058 (-0.18) | -0.038 (-0.11) n=58 |

**Selected-name diagnostics** (universe P, all months): average full-cross-section percentile of selected names and score spread

| K | avg pct high | avg pct low | avg score spread |
|---|---|---|---|
| quintile | 0.901 | 0.120 | 0.888 |
| K20 | 0.992 | 0.054 | 2.011 |
| K10 | 0.996 | 0.036 | 2.506 |
| K5 | 0.998 | 0.024 | 3.165 |
| K3 | 0.999 | 0.019 | 3.769 |
| K2 | 1.000 | 0.015 | 4.295 |
| K1 | 1.000 | 0.012 | 5.084 |

## Reading
1. **Concentration destroys Sharpe even before costs.** Universe P, COST0, annualised Sharpe (2014–20 / 2021–26):

   | Portfolio | Sharpe |
   |---|---|
   | Quintile (≈180 names per side) | 2.3 / 3.0 |
   | K20 | 1.8 / 1.4 |
   | K10 | 1.5 / 1.0 |
   | K5 | 1.1 / 0.9 |
   | K3 | 1.0 / 0.3 |
   | K1 | 0.3 / 0.4 |

   Single equity-VIX returns are extremely noisy (heavy right tails), so diversification across hundreds of names is what produces the paper's Sharpe.
2. **The liquid universe L carries much less of the pre-cost edge.** L quintile SR is 0.71 (2014–20) and 0.12 (2021–26). In 2021–26 the concentrated L portfolios (K3 to K10, pre-cost SR 0.8–0.9) are better than the L quintile. With 69–83 months, these K-level Sharpes have standard errors of about ±0.4.
3. **The SKIP-MONTH rule** (score spread below the 2014–20 20th percentile) does not rescue anything material; see its table.
4. **Answer to Q6 (which leg).** Both legs have negative excess returns: long options lose money on average, the variance risk premium.
   - The spread comes from Q1 losing much more than Q5.
   - After costs the short leg is the problem. Selling Q1 portfolios at the bid in wide-spread names forfeits most of the premium.

## Is the paper portfolio feasible for $25,000? No.

| Per month (Q1 + Q5 equity-VIX portfolios, each scaled so its smallest-weight option = 1 contract) | 5th pct | Median | Mean | 95th pct |
|---|---|---|---|---|
| Names (Q1+Q5) | 222 | 366 | 365 | 519 |
| Option contracts | 2,576 | 6,498 | 8,760 | 18,505 |
| Long premium paid (Q5), $ | 236,537 | 1,114,637 | 1,721,188 | 4,774,527 |
| Short-option margin (Q1, ≈15% of underlying per short + premium), $ | 66,541 | 305,907 | 494,630 | 1,461,277 |
| **Minimum capital (long premium + short margin), $** | **307,976** | **1,552,040** | 2,215,818 | 6,142,849 |
| Daily-hedge stock turnover over the month, $ | 18,909,016 | 76,490,453 | 92,784,031 | 221,982,502 |

Per single equity-VIX portfolio at minimum integer scale: median 10 contracts, median premium $867 (95th pct $15,610), median monthly hedge turnover $53,837.

Even at the smallest integer scale, a single monthly rebalance requires hundreds of names, thousands of contracts and about $1.5M of capital at the median. The $25k account is 1–2 orders of magnitude too small, before considering the manual effort of more than 6,000 contracts. **Exact replication of the paper portfolio at $25k is impossible; only a compressed, defined-risk ADAPTATION can be tested (Rounds 8–13).**
