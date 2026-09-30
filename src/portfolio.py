"""Step B: portfolio assembly from the per-unit position table (retail.py) + monthly scores.

Two sizing modes:
  * research (fractional): every position gets equal capital; position return = P&L / capital, where
    capital = max theoretical loss (defined-risk) or |entry premium| (naked research proxies).
  * account ($25k, integer): budget = risk% x NAV split equally, per-ticker cap $500 max loss,
    qty = floor(min(budget/N, cap) / max_loss_per_unit); P&L in dollars incl. commissions and hedge costs.
"""
import numpy as np, pandas as pd

COMM = 0.70
STK_COMM, STK_MIN, STK_SLIP = 0.005, 1.0, 0.0002


def select_names(scores: pd.DataFrame, F, universe_mask: pd.Series, K: int, available: set):
    """scores: rows for one F with columns root, score, pct. Extremes are taken within the trading
    universe among names whose structure is constructible (available). Ties broken by root."""
    s = scores[scores["root"].isin(available) & scores["root"].map(universe_mask).fillna(False)]
    s = s.sort_values(["score", "root"])
    low = s.head(K)
    high = s.sort_values(["score", "root"], ascending=[False, True]).head(K)
    return high, low


def position_pnl(row, cost_tag="e050", hedge="H0", comm=COMM, qty=1, borrow=True, stk_mult=1.0):
    """Dollar P&L for qty units of a position row (Series from the position table)."""
    opt = row[f"pnl_{cost_tag}"] - comm * row[f"ncontracts_{cost_tag}"]
    pnl = qty * opt
    if hedge != "H0":
        hp = row.get(f"hedge_pnl_{hedge}", np.nan)
        if not np.isfinite(hp):
            hp = 0.0
        sh = row.get(f"hedge_shares_{hedge}", 0.0) * qty
        ntr = row.get(f"hedge_trades_{hedge}", 0)
        notional = row.get(f"hedge_notional_{hedge}", 0.0) * qty
        # IBKR fixed: $0.005/share, min $1 per order, integer shares -> approximate per trade
        comm_stk = max(STK_MIN * ntr, STK_COMM * sh) * stk_mult if ntr > 0 else 0.0
        cost = comm_stk + STK_SLIP * notional * stk_mult + (row.get(f"hedge_borrow_{hedge}", 0.0) * qty if borrow else 0.0)
        pnl += qty * hp - cost
    return pnl


def research_returns(pos: pd.DataFrame, picks: pd.DataFrame, cost_tag="e050", hedge="H0", comm=COMM,
                     capital="max_loss"):
    """Equal-capital monthly returns of the selected positions. picks: rows (F, root, kind, side)."""
    m = picks.merge(pos, on=["F", "root", "kind", "side"], how="left")
    m = m[m[f"pnl_{cost_tag}"].notna()]
    cap = m["max_loss_nat"] if capital == "max_loss" else 100 * m["entry_nat"].abs()
    cap = cap.replace([np.inf, -np.inf], np.nan)
    m = m[cap.notna() & (cap > 0)]
    cap = cap[m.index]
    pnl = m.apply(lambda r: position_pnl(r, cost_tag, hedge, comm), axis=1)
    m = m.assign(ret=pnl / cap)
    return m


def account_month(rows: pd.DataFrame, nav=25000.0, risk_pct=0.04, cap_per_ticker=500.0, cost_tag="e050",
                  hedge="H0", comm=COMM, vega_match=False, max_contracts=24, stk_mult=1.0):
    """Integer sizing for one month. rows: selected positions (high side first, then low side), each
    with max_loss_nat, net_vega, n_legs. Returns dict with dollar P&L and diagnostics."""
    rows = rows[np.isfinite(rows["max_loss_nat"]) & (rows["max_loss_nat"] > 0)].copy()
    N = len(rows)
    if N == 0:
        return {"pnl": 0.0, "n_pos": 0, "traded": False}
    budget = risk_pct * nav
    per = min(budget / N, cap_per_ticker)
    rows["qty"] = np.floor(per / (rows["max_loss_nat"] + comm * rows["n_legs"])).astype(int)
    if vega_match:
        hi = rows[rows["side"] > 0]
        lo = rows[rows["side"] < 0]
        for (ih, h), (il, l) in zip(hi.iterrows(), lo.iterrows()):
            if rows.at[ih, "qty"] == 0 or abs(l["net_vega"]) < 1e-9:
                continue
            target = rows.at[ih, "qty"] * abs(h["net_vega"]) / abs(l["net_vega"])
            ql = int(max(0, round(target)))
            ql = min(ql, int(np.floor(cap_per_ticker / (l["max_loss_nat"] + comm * l["n_legs"]))))
            rows.at[il, "qty"] = ql
    # manual-execution cap on total contracts (entry legs); trim largest qty first
    while (rows["qty"] * rows["n_legs"]).sum() > max_contracts and rows["qty"].max() > 0:
        rows.loc[rows["qty"].idxmax(), "qty"] -= 1
    # risk budget check (sum of max losses)
    while (rows["qty"] * rows["max_loss_nat"]).sum() > budget and rows["qty"].max() > 0:
        rows.loc[rows["qty"].idxmax(), "qty"] -= 1
    rows = rows[rows["qty"] > 0]
    if rows.empty:
        return {"pnl": 0.0, "n_pos": 0, "traded": False}
    pnl = sum(position_pnl(r, cost_tag, hedge, comm, qty=int(r["qty"]), stk_mult=stk_mult) for _, r in rows.iterrows())
    fr_pnl = None
    return {
        "pnl": pnl, "n_pos": len(rows), "n_long": int((rows["side"] > 0).sum()), "n_short": int((rows["side"] < 0).sum()),
        "contracts": int((rows["qty"] * rows["n_legs"]).sum()), "max_loss_total": float((rows["qty"] * rows["max_loss_nat"]).sum()),
        "premium_total": float((rows["qty"] * rows["entry_nat"] * 100).sum()),
        "net_vega": float((rows["qty"] * rows["net_vega"]).sum()), "gross_vega": float((rows["qty"] * rows["net_vega"].abs()).sum()),
        "net_delta": float((rows["qty"] * rows["net_delta"]).sum()), "net_gamma": float((rows["qty"] * rows["net_gamma"]).sum()),
        "net_theta": float((rows["qty"] * rows["net_theta"]).sum()), "traded": True,
        "tickers": ",".join(f"{r['root']}{'+' if r['side'] > 0 else '-'}x{int(r['qty'])}" for _, r in rows.iterrows()),
    }
