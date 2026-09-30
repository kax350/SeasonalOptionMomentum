"""Retail adaptation engine (ADAPTATION / PROXY instruments; see RESEARCH_LEDGER.md A5-A9).

Step A (this module, expensive): for every formation date F and every eligible name, build each
pre-registered structure from the entry snapshot (15:45 ET headline), value it at exit
(15:00 ET on the expiration day X = next formation date), and compute per-unit P&L at every cost
level plus the hedge P&L for H0/H1/H2. Result: one row per (F, name, kind, side).
Step B (portfolio.py, cheap): select names by seasonal rank, size in integer contracts, aggregate.

Units: 1 unit = 1 contract of every leg (x100 multiplier). All $ amounts are per unit.
"""
import os, sys, datetime as dt, warnings
import numpy as np, pandas as pd
from scipy.stats import norm

warnings.filterwarnings("ignore")
sys.path.insert(0, os.path.dirname(__file__))
from calendar_utils import formation_dates
from equity_vix import select_chain, implied_vol, RateCurve, next_standard_expiry

DATA = os.environ.get("SOM_DATA", "/home/user/data")
SNAP = {"1545": os.path.join(DATA, "opra", "snap_1545"), "1500": os.path.join(DATA, "opra", "snap_1500"),
        "close": os.path.join(DATA, "opra", "close_snap"), "1530": os.path.join(DATA, "opra", "snap_1530"),
        "1555": os.path.join(DATA, "opra", "snap_1555")}
KINDS = ["STRADDLE", "STRANGLE25", "IFLY10", "IFLY15", "SSPREAD"]
E_LEVELS = [0.0, 0.25, 0.5, 1.0]
COMM = 0.70          # $ per option contract, all-in (A3)
STK_COMM = 0.005     # $ per share, min $1 per order
STK_SLIP = 0.0002    # 2 bps of traded notional
BORROW = 0.0025      # 0.25%/yr on short stock notional
HOURS = {"1545": 15.75, "1530": 15.5, "1555": 15.917, "close": 15.983, "1500": 15.0}


def tick(p):
    return np.where(p < 3, 0.01, 0.05)


def _bs(S, K, T, r, sig, cp):
    sq = sig * np.sqrt(T)
    d1 = (np.log(S / K) + (r + 0.5 * sig ** 2) * T) / sq
    d2 = d1 - sq
    pdf = norm.pdf(d1)
    delta = np.where(cp == "C", norm.cdf(d1), norm.cdf(d1) - 1)
    gamma = pdf / (S * sq)
    vega = S * pdf * np.sqrt(T) / 100.0          # per 1 vol point
    theta_c = -S * pdf * sig / (2 * np.sqrt(T)) - r * K * np.exp(-r * T) * norm.cdf(d2)
    theta_p = -S * pdf * sig / (2 * np.sqrt(T)) + r * K * np.exp(-r * T) * norm.cdf(-d2)
    theta = np.where(cp == "C", theta_c, theta_p) / 365.0
    return delta, gamma, vega, theta


def load_chain(d: dt.date, when: str):
    p = os.path.join(SNAP[when], f"{d}.parquet")
    if not os.path.exists(p):
        return None
    snap = pd.read_parquet(p)
    ch = select_chain(snap, d)
    ch = ch[ch["bid"].notna() & ch["ask"].notna() & (ch["ask"] > 0) & (ch["bid"] <= ch["ask"])]
    ch["mid"] = (ch["bid"] + ch["ask"]) / 2
    return ch


def implied_forward(g: pd.DataFrame, r, T):
    c = g[g["cp"] == "C"].set_index("strike")["mid"]
    p = g[g["cp"] == "P"].set_index("strike")["mid"]
    both = c.index.intersection(p.index)
    if len(both) == 0:
        return np.nan
    diff = (c.loc[both] - p.loc[both])
    k = diff.abs().idxmin()
    return k + np.exp(r * T) * diff.loc[k]


def pick_delta(g, cp, target, side_of, K_atm):
    x = g[(g["cp"] == cp) & g["delta"].notna()]
    x = x[x["strike"] > K_atm] if side_of == "above" else x[x["strike"] < K_atm]
    if x.empty:
        return None
    return x.iloc[(x["delta"] - target).abs().argsort().iloc[0]]


def build_legs(g: pd.DataFrame, kind: str, side: int, F: float):
    """Return list of (row, sign) or None. side=+1 long vol, -1 short vol."""
    strikes_both = set(g[g["cp"] == "C"]["strike"]) & set(g[g["cp"] == "P"]["strike"])
    if not strikes_both:
        return None
    K_atm = min(strikes_both, key=lambda k: abs(k - F))
    atmC = g[(g["cp"] == "C") & (g["strike"] == K_atm)].iloc[0]
    atmP = g[(g["cp"] == "P") & (g["strike"] == K_atm)].iloc[0]
    if kind == "STRADDLE":
        return [(atmC, side), (atmP, side)]
    if kind == "STRANGLE25":
        c = pick_delta(g, "C", 0.25, "above", F)
        p = pick_delta(g, "P", -0.25, "below", F)
        return None if c is None or p is None else [(c, side), (p, side)]
    if kind in ("IFLY10", "IFLY15"):
        t = 0.10 if kind == "IFLY10" else 0.15
        c = pick_delta(g, "C", t, "above", K_atm)
        p = pick_delta(g, "P", -t, "below", K_atm)
        return None if c is None or p is None else [(atmC, side), (atmP, side), (c, -side), (p, -side)]
    if kind == "SSPREAD":
        ci = pick_delta(g, "C", 0.25, "above", F)
        pi = pick_delta(g, "P", -0.25, "below", F)
        if ci is None or pi is None:
            return None
        co = pick_delta(g, "C", 0.10, "above", ci["strike"])
        po = pick_delta(g, "P", -0.10, "below", pi["strike"])
        return None if co is None or po is None else [(ci, side), (pi, side), (co, -side), (po, -side)]
    raise ValueError(kind)


def payoff_extremes(legs):
    """Min and max of sum(sign*intrinsic(S_T)) over S_T in [0, inf). Returns (min, max, unbounded_loss)."""
    Ks = sorted({float(r["strike"]) for r, _ in legs})
    pts = [0.0] + Ks + [Ks[-1] * 10 + 1]
    vals = []
    for S in pts:
        v = 0.0
        for r, s in legs:
            v += s * (max(S - r["strike"], 0) if r["cp"] == "C" else max(r["strike"] - S, 0))
        vals.append(v)
    slope_inf = sum(s for r, s in legs if r["cp"] == "C")
    return min(vals), max(vals), slope_inf < 0


def fill(bid, ask, sign, e):
    """Price paid (+) or received for a leg with signed quantity; returns signed cash outflow per share."""
    mid = (bid + ask) / 2
    if sign > 0:
        return mid + e * (ask - mid)
    return -(mid - e * (mid - bid))


def evaluate_month(F_date: dt.date, X_date: dt.date, entry_when: str, rates: RateCurve, px_daily: pd.DataFrame,
                   names=None, exit_when="1500"):
    ch = load_chain(F_date, entry_when)
    ex = load_chain_exit(X_date, exit_when)
    if ch is None or ex is None:
        return pd.DataFrame()
    chx, spot_x = ex
    tf, exdate_trade = next_standard_expiry(F_date)
    T_entry = ((pd.Timestamp(exdate_trade) - pd.Timestamp(F_date)).days + (16 - HOURS[entry_when]) / 24) / 365
    r = float(rates.linear_rate(pd.Timestamp(F_date), [(pd.Timestamp(exdate_trade) - pd.Timestamp(F_date)).days])[0]) / 100
    if names is not None:
        ch = ch[ch["root"].isin(set(names))]
    exq = chx.set_index("symbol")[["bid", "ask"]]
    # implied spot at exit from the new next-month chain (15:00 on X)
    rows = []
    for root, g in ch.groupby("root"):
        g = g.copy()
        Fw = implied_forward(g[(g["bid"] > 0)], r, T_entry)
        if not np.isfinite(Fw) or Fw <= 0:
            continue
        S0 = Fw * np.exp(-r * T_entry)
        g["iv"] = implied_vol(g["mid"].values, S0, g["strike"].values, T_entry, r, g["cp"].values)
        ivf = g["iv"].fillna(g["iv"].median() if g["iv"].notna().any() else 0.3).values
        dlt, gam, veg, the = _bs(S0, g["strike"].values, T_entry, r, ivf, g["cp"].values)
        g["delta"], g["gamma"], g["vega"], g["theta"] = dlt, gam, veg, the
        g.loc[g["iv"].isna(), "delta"] = np.nan
        Sx = spot_x.get(root, np.nan) * np.exp(-r * 28 / 365)   # next-month forward at X 15:00 -> spot
        path = px_daily.get(root) if px_daily is not None else None
        for kind in KINDS:
            for side in (1, -1):
                legs = build_legs(g, kind, side, Fw)
                if legs is None:
                    continue
                ok = all((row["ask"] > 0) if s > 0 else (row["bid"] > 0) for row, s in legs)
                if not ok or len({row["symbol"] for row, _ in legs}) != len(legs):
                    continue
                pmin, pmax, unbounded = payoff_extremes(legs)
                rec = {"F": pd.Timestamp(F_date), "X": pd.Timestamp(X_date), "root": root, "kind": kind, "side": side,
                       "S0": S0, "Fwd": Fw, "T": T_entry, "r": r, "n_legs": len(legs),
                       "legs": "|".join(f"{'+' if s > 0 else '-'}{row['cp']}{row['strike']:g}" for row, s in legs),
                       "symbols": "|".join(row["symbol"] for row, _ in legs), "signs": "|".join(str(s) for _, s in legs)}
                mid_debit = sum(s * row["mid"] for row, s in legs)
                nat_debit = sum(fill(row["bid"], row["ask"], s, 1.0) for row, s in legs)
                rec["entry_mid"] = mid_debit
                rec["entry_nat"] = nat_debit
                rec["half_spread_combo"] = nat_debit - mid_debit
                rec["max_loss_mid"] = 100 * (mid_debit - pmin) if not unbounded else np.inf
                rec["max_loss_nat"] = 100 * (nat_debit - pmin) if not unbounded else np.inf
                rec["max_gain_nat"] = 100 * (pmax - nat_debit)
                rec["net_delta"] = 100 * sum(s * row["delta"] for row, s in legs)
                rec["net_gamma"] = 100 * sum(s * row["gamma"] for row, s in legs)
                rec["net_vega"] = 100 * sum(s * row["vega"] for row, s in legs)
                rec["net_theta"] = 100 * sum(s * row["theta"] for row, s in legs)
                rec["atm_iv"] = float(np.nanmean([row["iv"] for row, s in legs[:2]]))
                rec["atm_rel_spread"] = float(np.mean([(row["ask"] - row["bid"]) / row["mid"] for row, s in legs[:2]]))
                # exit valuation
                missing = 0
                exit_vals = {}
                for row, s in legs:
                    q = exq.loc[row["symbol"]] if row["symbol"] in exq.index else None
                    if q is None or not np.isfinite(q["bid"]) or not np.isfinite(q["ask"]):
                        missing += 1
                        intr = (max(Sx - row["strike"], 0) if row["cp"] == "C" else max(row["strike"] - Sx, 0)) \
                            if np.isfinite(Sx) else np.nan
                        # unquoted on the exit snapshot (2025+ feed omits unquoted expiring series):
                        # value at intrinsic with a one-tick market around it
                        b, a = max(intr - 0.01, 0.0), intr + 0.01
                    else:
                        b, a = float(q["bid"]), float(q["ask"])
                    exit_vals[row["symbol"]] = (b, a, s)
                for e in E_LEVELS + ["tick"]:
                    ee = 1.0 if e == "tick" else e
                    ent = sum(fill(row["bid"], row["ask"], s, ee) for row, s in legs)
                    if e == "tick":
                        ent += 0.01  # combo natural worsened by one complex-order tick
                    exv, n_tr = 0.0, 0
                    for sym, (b, a, s) in exit_vals.items():
                        if s > 0:  # we sell our long leg: receive mid - e*(mid-bid); abandon if bid==0
                            if b > 0:
                                exv += (b + a) / 2 - ee * ((b + a) / 2 - b)
                                n_tr += 1
                        else:      # buy back short leg: pay mid + e*(ask-mid)
                            exv -= (b + a) / 2 + ee * (a - (b + a) / 2)
                            n_tr += 1
                    if e == "tick":
                        exv -= 0.01
                    tag = "tick" if e == "tick" else f"e{int(e * 100):03d}"
                    rec[f"pnl_{tag}"] = 100 * (exv - ent)                       # before commissions
                    rec[f"ncontracts_{tag}"] = len(legs) + n_tr                  # entry + exit contracts
                rec["exit_missing_legs"] = missing
                rec["Sx"] = Sx
                if path is not None:
                    rec.update(hedge_sim(legs, g, S0, Sx, path, F_date, X_date, exdate_trade, r, entry_when))
                rec["exit_mid_value"] = sum(((b + a) / 2) * s for b, a, s in exit_vals.values())
                rows.append(rec)
    return pd.DataFrame(rows)


def load_chain_exit(X_date: dt.date, when: str):
    """All quotes on the exit date (any expiry), plus implied spot per root from its next-month chain."""
    p = os.path.join(SNAP[when], f"{X_date}.parquet")
    if not os.path.exists(p):
        return None
    snap = pd.read_parquet(p)
    for c in ("root", "cp", "symbol"):
        snap[c] = snap[c].astype(str)
    snap = snap[snap["bid"].notna() & snap["ask"].notna()]
    nxt = select_chain(snap, X_date)
    nxt = nxt[(nxt["bid"] > 0) & (nxt["ask"] > 0)]
    nxt["mid"] = (nxt["bid"] + nxt["ask"]) / 2
    tf, et = next_standard_expiry(X_date)
    T = ((pd.Timestamp(et) - pd.Timestamp(X_date)).days + 1 / 24) / 365
    spot = {}
    for root, g in nxt.groupby("root"):
        f = implied_forward(g, 0.0, T)
        if np.isfinite(f):
            spot[root] = f
    return snap, spot


def hedge_sim(legs, g, S0, Sx, path: pd.Series, F_date, X_date, exdate_trade, r, entry_when):
    """Per-unit stock-hedge P&L for H1 (daily) and H2 (threshold 0.15 / 0.25 delta per unit).
    Deltas: Black-Scholes with each leg's entry IV (sticky strike), spot = daily close (PROXY for
    15:45), entry at the 15:45 implied spot, exit at the 15:00 implied spot on X (fallback: close of X)."""
    Ks = np.array([row["strike"] for row, _ in legs], float)
    cps = np.array([row["cp"] for row, _ in legs])
    sg = np.array([s for _, s in legs], float)
    ivs = np.array([row["iv"] if np.isfinite(row["iv"]) else np.nan for row, _ in legs], float)
    if np.isnan(ivs).any():
        med = np.nanmedian(g["iv"]) if g["iv"].notna().any() else 0.3
        ivs = np.where(np.isnan(ivs), med, ivs)
    expiry = pd.Timestamp(exdate_trade) + pd.Timedelta(hours=16)

    def D(S, t):
        T = max((expiry - t).total_seconds() / 86400 / 365, 1e-6)
        d, _, _, _ = _bs(S, Ks, T, r, ivs, cps)
        return 100 * float(np.sum(sg * d))   # shares of delta per unit

    days = path[(path.index > pd.Timestamp(F_date)) & (path.index < pd.Timestamp(X_date))]
    S_exit = Sx if np.isfinite(Sx) else path.get(pd.Timestamp(X_date), np.nan)
    t0 = pd.Timestamp(F_date) + pd.Timedelta(hours=HOURS[entry_when])
    marks = [(t0, S0)] + [(t + pd.Timedelta(hours=16), float(v)) for t, v in days.items()]
    out = {}
    if not np.isfinite(S_exit):
        for pol in ("H1", "H2_15", "H2_25"):
            out.update({f"hedge_pnl_{pol}": np.nan})
        return out
    for pol, thr in (("H1", 0.0), ("H2_15", 15.0), ("H2_25", 25.0)):
        h, pnl, traded_sh, traded_notional, n_tr, borrow = 0.0, 0.0, 0.0, 0.0, 0, 0.0
        prev_S, prev_t = None, None
        for i, (t, S) in enumerate(marks):
            if prev_S is not None:
                pnl += h * (S - prev_S)
                if h < 0:
                    borrow += -h * prev_S * BORROW * max((t - prev_t).days, 1) / 365
            Dt = D(S, t)
            expo = Dt + h
            rebalance = True if thr == 0.0 else abs(expo) > thr   # H1: every mark; H2: only beyond threshold
            if rebalance:
                trade = -Dt - h
                if abs(trade) > 1e-9:
                    traded_sh += abs(trade); traded_notional += abs(trade) * S; n_tr += 1
                h = -Dt
            prev_S, prev_t = S, t
        # close hedge at exit
        pnl += h * (S_exit - prev_S)
        if h < 0:
            borrow += -h * prev_S * BORROW * 1 / 365
        if abs(h) > 1e-9:
            traded_sh += abs(h); traded_notional += abs(h) * S_exit; n_tr += 1
        out[f"hedge_pnl_{pol}"] = pnl
        out[f"hedge_shares_{pol}"] = traded_sh
        out[f"hedge_notional_{pol}"] = traded_notional
        out[f"hedge_trades_{pol}"] = n_tr
        out[f"hedge_borrow_{pol}"] = borrow
    return out


def daily_paths(roots, start, end):
    """root -> Series of DoltHub closes indexed by date (raw, split/dividend windows excluded upstream)."""
    from equity_vix import normalize_root
    px = daily_paths._px
    if px is None:
        px = pd.read_parquet(os.path.join(DATA, "stocks", "ohlcv.parquet"), columns=["date", "act_symbol", "close"])
        px["date"] = pd.to_datetime(px["date"])
        px["root"] = normalize_root(px["act_symbol"].astype(str))
        daily_paths._px = px
    x = px[(px["date"] >= pd.Timestamp(start)) & (px["date"] <= pd.Timestamp(end)) & px["root"].isin(set(roots))]
    return {r: g.set_index("date")["close"].sort_index() for r, g in x.groupby("root")}


daily_paths._px = None
