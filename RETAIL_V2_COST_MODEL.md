# RETAIL V2 — COST MODEL

## Quote source
OPRA consolidated NBBO from Databento `cbbo-1m`. The record at 15:59:00 ET carries the BBO as of that instant (verified: every record's `ts_event` ≤ `ts_recv`). One snapshot is taken at entry (F 15:59) and one at exit (X 15:59). Kill tests use the 15:45 (entry) and 15:00 (exit) snapshots, available for 2019+.

## Option fills (per leg, per contract)
| Level | Buy price | Sell price | Use |
|---|---|---|---|
| MID | mid | mid | theoretical ceiling only; never a final result |
| C25 | mid + 0.25·(ask−mid) | mid − 0.25·(mid−bid) | optimistic retail |
| **C50** | mid + 0.50·(ask−mid) | mid − 0.50·(mid−bid) | **primary verdict level** |
| C100 | ask | bid | crossed spread / immediately executable |
| Stress ×1.25 / ×1.5 | quoted spread widened 25% / 50% around mid, then C50 | | kill tests 1–2 |

- Costs are paid at **entry and exit**. The FRONT leg is closed on its expiry day at 15:59 quotes, not left to exercise.
- Exit legs with no quote on the 2025+ feed are valued conservatively: ITM at intrinsic ± max($0.05, 1%·intrinsic); OTM at bid 0 / ask $0.05.
- Combo orders are priced as the sum of the legs. No combo price improvement is assumed.

## Fees
| Item | Base | Stress (kill 3) |
|---|---|---|
| Option commission + exchange/ORF/OCC/TAF | $0.70 per contract, per side | $1.40 |
| Stock/ETF hedge commission | $0.005/share, min $1 per order | ×2 |
| Stock/ETF hedge slippage | 2 bps of traded notional | ×2 |
| Short stock borrow | 0.25%/yr general collateral | — |

## What is NOT modelled (by design)
- **Passive / limit-order fills.** We have no trade prints, queue position or quote dynamics. Fill probability and adverse selection cannot be estimated, so no passive model is used. "Touch = fill" is forbidden.
- Price improvement on complex orders.
- Market impact beyond the quoted spread. Positions are ≤ a few contracts, inside the quoted size in nearly all cases (quoted sizes are reported).

## Cost diagnostics reported for every family
- Gross (MID) edge.
- Cost per round trip at C25 / C50 / C100.
- **Cost / gross-edge ratio.**
- Turnover (contracts, hedge shares).
- Average quoted spread of the traded legs.
