"""RETAIL V2 — Phase A0 leg table (see RETAIL_V2_CHARTER.md §2–§5).

For every formation date F (15:59 ET OPRA snapshot) and every candidate underlying (US common stocks passing
a loose pre-screen + ETF list), for the FRONT (expires X) and BACK (next monthly) expiries, store the legs
ATM C/P, 25D, 20D, 15D, 10D C/P with entry quotes/greeks and exit quotes at X 15:59, plus per-contract
hedge P&L for H1 (entry-only) and H2 (daily, sticky-strike BS deltas on DoltHub closes).

Outputs ($SOM_DATA/v2/):
  legs/<F>.parquet      one row per leg
  roots/<F>.parquet     one row per root-month: features at F (spreads, IVs, HV, skew, term slope, ADV)
                        and realised outcomes over (F, X] (RV, idiosyncratic RV vs SPY, jump share)
  paths/<F>.parquet     daily close path per root (for H3 and audits)
"""
import os, sys, time, datetime as dt, warnings
import numpy as np, pandas as pd
from scipy.stats import norm

warnings.filterwarnings("ignore")
sys.path.insert(0, os.path.dirname(__file__))
from calendar_utils import formation_dates, third_friday, prev_session_on_or_before
from equity_vix import RateCurve, implied_vol, normalize_root, implied_spots

DATA = os.environ.get("SOM_DATA", "/home/user/data")
OUTD = os.path.join(DATA, "v2")
ETFS = ["SPY", "QQQ", "IWM", "XLB", "XLE", "XLF", "XLI", "XLK", "XLP", "XLU", "XLV", "XLY", "XLRE", "XLC"]
DELTAS = {"25": 0.25, "20": 0.20, "15": 0.15, "10": 0.10}


def monthly_expiry(year, month):
    tf = third_friday(year, month)
    return tf, prev_session_on_or_before(tf)


def expiry_after(d: dt.date, k: int):
    """k-th standard monthly expiry after formation date d (k=1 FRONT, k=2 BACK)."""
    m = d.month - 1 + k
    return monthly_expiry(d.year + m // 12, m % 12 + 1)


def pick_chain(snap, tf, last_trade):
    ok = {pd.Timestamp(tf), pd.Timestamp(tf + dt.timedelta(days=1))}
    if last_trade != tf:
        ok.add(pd.Timestamp(last_trade))
    ch = snap[snap["expiration"].isin(ok)].copy()
    return ch


def norm_chain(ch):
    ch = ch[ch["ask"].notna() & (ch["ask"] > 0)].copy()
    ch["bid"] = ch["bid"].fillna(0.0)  # 2025+ feed: undefined bid == zero bid
    ch = ch[ch["bid"] <= ch["ask"]].drop_duplicates(["root", "cp", "strike"])
    ch["mid"] = (ch["bid"] + ch["ask"]) / 2
    return ch


def bs_greeks(S, K, T, r, sig, cp):
    sq = sig * np.sqrt(T)
    d1 = (np.log(S / K) + (r + 0.5 * sig * sig) * T) / sq
    d2 = d1 - sq
    pdf = norm.pdf(d1)
    delta = np.where(cp == "C", norm.cdf(d1), norm.cdf(d1) - 1.0)
    gamma = pdf / (S * sq)
    vega = S * pdf * np.sqrt(T) / 100.0
    theta = np.where(cp == "C", -S * pdf * sig / (2 * np.sqrt(T)) - r * K * np.exp(-r * T) * norm.cdf(d2),
                     -S * pdf * sig / (2 * np.sqrt(T)) + r * K * np.exp(-r * T) * norm.cdf(-d2)) / 365.0
    return delta, gamma, vega, theta


def parity_forward(g, r, T):
    q = g[(g["bid"] > 0)]
    c = q[q["cp"] == "C"].groupby("strike")["mid"].first()
    p = q[q["cp"] == "P"].groupby("strike")["mid"].first()
    both = c.index.intersection(p.index)
    if len(both) == 0:
        return np.nan
    d = c.loc[both] - p.loc[both]
    k = d.abs().idxmin()
    return float(k + np.exp(r * T) * d.loc[k])


def select_legs(g, Fw, K_force=None):
    """Return dict tag -> row: ATM_C/ATM_P (strike nearest the forward, both listed), delta-targeted OTM legs
    C25/P25/C20/P20/C15/P15/C10/P10 (only if |delta - target| <= 0.05), and ATMF_C/ATMF_P at K_force
    (used on BACK = the FRONT ATM strike, for same-strike calendars)."""
    out = {}
    both = sorted(set(g[g["cp"] == "C"]["strike"]) & set(g[g["cp"] == "P"]["strike"]))
    if not both:
        return out
    Katm = min(both, key=lambda k: abs(k - Fw))
    out["ATM_C"] = g[(g["cp"] == "C") & (g["strike"] == Katm)].iloc[0]
    out["ATM_P"] = g[(g["cp"] == "P") & (g["strike"] == Katm)].iloc[0]
    if K_force is not None and K_force in both:
        out["ATMF_C"] = g[(g["cp"] == "C") & (g["strike"] == K_force)].iloc[0]
        out["ATMF_P"] = g[(g["cp"] == "P") & (g["strike"] == K_force)].iloc[0]
    calls = g[(g["cp"] == "C") & (g["strike"] > Fw) & g["delta"].notna()]
    puts = g[(g["cp"] == "P") & (g["strike"] < Fw) & g["delta"].notna()]
    for tag, t in DELTAS.items():
        if len(calls):
            c = calls.iloc[(calls["delta"] - t).abs().argsort().iloc[0]]
            if abs(c["delta"] - t) <= 0.05:
                out[f"C{tag}"] = c
        if len(puts):
            pp = puts.iloc[(puts["delta"] + t).abs().argsort().iloc[0]]
            if abs(pp["delta"] + t) <= 0.05:
                out[f"P{tag}"] = pp
    return out


def delta_path(K, cp, iv, r, t_marks, S_marks, exp_days):
    T = np.maximum((exp_days - t_marks) / 365.0, 1e-6)
    sq = iv * np.sqrt(T)
    d1 = (np.log(S_marks / K) + (r + 0.5 * iv * iv) * T) / sq
    return np.where(cp == "C", norm.cdf(d1), norm.cdf(d1) - 1.0) * 100.0  # shares of delta per contract


def hedge_from_path(D, S_marks, S_exit):
    """Hedge stats for a position with delta path D (shares) at marks S_marks, closed at S_exit.
    H1 = hedge only at entry; H2 = re-hedge at every mark. Turnover split so it can be netted at structure level:
    entry |D0|, exit |D_last| and the daily changes sum|dD|."""
    S_next = np.append(S_marks[1:], S_exit)
    h1 = -D[0] * (S_exit - S_marks[0])
    h2 = float(np.sum(-D * (S_next - S_marks)))
    chg_sh = float(np.sum(np.abs(np.diff(D))))
    chg_turn = float(np.sum(np.abs(np.diff(D)) * S_marks[1:]))
    return h1, h2, chg_sh, chg_turn


def h3_threshold(D, S_marks, S_exit, thr=25.0):
    """H3: re-hedge to zero only when |net delta + hedge| > thr shares. Returns pnl, shares traded, orders."""
    h, pnl, sh, orders = 0.0, 0.0, 0.0, 0
    for i in range(len(D)):
        if i > 0:
            pnl += h * (S_marks[i] - S_marks[i - 1])
        if i == 0 or abs(D[i] + h) > thr:
            tr = -D[i] - h
            if abs(tr) > 1e-9:
                sh += abs(tr); orders += 1
            h = -D[i]
    pnl += h * (S_exit - S_marks[-1])
    if abs(h) > 1e-9:
        sh += abs(h); orders += 1
    return pnl, sh, orders


def process_month(args):
    F, X, info = args
    out_legs = os.path.join(OUTD, "legs", f"{F}.parquet")
    if os.path.exists(out_legs):
        return F, "cached", 0
    t0 = time.time()
    rates = RateCurve()
    snapF = pd.read_parquet(os.path.join(DATA, "opra", "close_snap", f"{F}.parquet"))
    snapX = pd.read_parquet(os.path.join(DATA, "opra", "close_snap", f"{X}.parquet"))
    for s in (snapF, snapX):
        for c in ("root", "cp", "symbol"):
            s[c] = s[c].astype(str)
    roots_ok = set(info["candidates"]) | set(ETFS)
    snapF = snapF[snapF["root"].isin(roots_ok)]
    xq = snapX[snapX["ask"].notna()].assign(bid=lambda z: z["bid"].fillna(0.0)).groupby("symbol")[["bid", "ask"]].first()
    tfF, ltF = expiry_after(F, 1)
    tfB, ltB = expiry_after(F, 2)
    chF = norm_chain(pick_chain(snapF, tfF, ltF))
    chB = norm_chain(pick_chain(snapF, tfB, ltB))
    x_cov = float(chF["symbol"].isin(set(xq.index)).mean()) if len(chF) else np.nan
    tfX, ltX = expiry_after(X, 1)
    chX = norm_chain(pick_chain(snapX[snapX["root"].isin(roots_ok)], tfX, ltX))
    chX["exdate_trade"] = pd.Timestamp(ltX)
    refX = pd.Series({r_: info["closeX"].get(r_, np.nan) for r_ in chX["root"].unique()})
    spotX = implied_spots(chX, X, rates, ref_spot=refX)["S_impl_start"] if len(chX) else pd.Series(dtype=float)
    spotX = pd.to_numeric(spotX, errors="coerce").astype("float64")
    daysF = (pd.Timestamp(ltF) - pd.Timestamp(F)).days
    daysB = (pd.Timestamp(ltB) - pd.Timestamp(F)).days
    rF = float(rates.linear_rate(pd.Timestamp(F), [daysF])[0]) / 100
    rB = float(rates.linear_rate(pd.Timestamp(F), [daysB])[0]) / 100
    TF, TB = (daysF + 1 / 1440) / 365, (daysB + 1 / 1440) / 365
    hold_days = (pd.Timestamp(X) - pd.Timestamp(F)).days
    legs, roots = [], []
    gB_all = dict(tuple(chB.groupby("root")))
    for root, gF in chF.groupby("root"):
        is_etf = root in ETFS
        S_close_F = info["closeF"].get(root, np.nan)
        path = info["paths"].get(root)
        if path is None or not np.isfinite(S_close_F):
            continue
        FwF = parity_forward(gF, rF, TF)
        if not np.isfinite(FwF) or FwF <= 0:
            continue
        S0 = FwF * np.exp(-rF * TF)
        if abs(S0 / S_close_F - 1) > 0.05:          # start-side data validation (F information only)
            continue
        S_X = info["closeX"].get(root, np.nan)
        delisted = not np.isfinite(S_X)
        days = path[(path.index > pd.Timestamp(F)) & (path.index < pd.Timestamp(X))].astype(float)
        S_exit_h = S_X if not delisted else (float(days.iloc[-1]) if len(days) else S_close_F)
        sx_impl = spotX.get(root, np.nan) if len(spotX) else np.nan
        x_flag = bool(np.isfinite(sx_impl) and np.isfinite(S_X) and abs(sx_impl / S_X - 1) > 0.05)
        rec_root = {"F": pd.Timestamp(F), "X": pd.Timestamp(X), "root": root, "is_etf": is_etf, "S0": S0,
                    "S_close_F": S_close_F, "S_X": S_X, "delisted": delisted, "x_flag": x_flag, "x_cov": x_cov,
                    "rf_hold": rF * hold_days / 365}
        t_marks = np.concatenate([[16 / 24], (days.index - pd.Timestamp(F)).days.values + 16 / 24])
        S_marks = np.concatenate([[S_close_F], days.values])
        ok_root, K_front = True, None
        for tag_exp, g, r, T, exp_days in (("FRONT", gF, rF, TF, daysF + 16 / 24), ("BACK", gB_all.get(root), rB, TB, daysB + 16 / 24)):
            if g is None or g.empty:
                if tag_exp == "FRONT":
                    ok_root = False
                continue
            g = g.copy()
            Fw = parity_forward(g, r, T)
            S_e = Fw * np.exp(-r * T) if np.isfinite(Fw) and Fw > 0 else S0    # prepaid forward of this expiry
            if not np.isfinite(Fw):
                Fw = S0 * np.exp(r * T)
            iv = implied_vol(g["mid"].values, S_e, g["strike"].values, T, r, g["cp"].values)
            g["iv"] = iv
            ivf = np.where(np.isnan(iv), np.nanmedian(iv) if np.isfinite(iv).any() else 0.3, iv)
            d, gm, vg, th = bs_greeks(S_e, g["strike"].values, T, r, ivf, g["cp"].values)
            g["delta"], g["gamma"], g["vega"], g["theta"] = np.where(np.isnan(iv), np.nan, d), gm, vg, th
            sel = select_legs(g, Fw, K_force=K_front if tag_exp == "BACK" else None)
            if "ATM_C" not in sel:
                if tag_exp == "FRONT":
                    ok_root = False
                continue
            atm = (sel["ATM_C"], sel["ATM_P"])
            rs = max((a["ask"] - a["bid"]) / a["mid"] if a["bid"] > 0 else np.inf for a in atm)
            if tag_exp == "FRONT":
                K_front = float(atm[0]["strike"])
                if not is_etf and rs > 0.25:       # loose pre-screen (looser than any LOU variant)
                    ok_root = False
                    break
            rec_root[f"{tag_exp}_Fwd"] = Fw
            rec_root[f"{tag_exp}_atm_strike"] = float(atm[0]["strike"])
            rec_root[f"{tag_exp}_atm_iv"] = float(np.nanmean([atm[0]["iv"], atm[1]["iv"]]))
            rec_root[f"{tag_exp}_atm_rel_spread"] = float(rs)
            rec_root[f"{tag_exp}_atm_bid_ok"] = bool(all(a["bid"] > 0 for a in atm))
            rec_root[f"{tag_exp}_atm_min_size"] = float(min(min(a["bid_sz"], a["ask_sz"]) for a in atm))
            if "P25" in sel and "C25" in sel:
                rec_root[f"{tag_exp}_skew25"] = float(sel["P25"]["iv"] - sel["C25"]["iv"])
            Dpaths = {}
            for tag, row in sel.items():
                ivl = row["iv"] if np.isfinite(row["iv"]) else np.nanmedian(g["iv"])
                if not np.isfinite(ivl):
                    continue
                q = xq.loc[row["symbol"]] if row["symbol"] in xq.index else None
                xb, xa = (float(q["bid"]), float(q["ask"])) if q is not None else (np.nan, np.nan)
                missing = q is None
                if missing and tag_exp == "FRONT" and not delisted:   # conservative synthetic exit market
                    intr = max(S_X - row["strike"], 0) if row["cp"] == "C" else max(row["strike"] - S_X, 0)
                    if intr > 0:
                        h = max(0.05, 0.01 * intr)
                        xb, xa = max(intr - h, 0.0), intr + h
                    else:
                        xb, xa = 0.0, 0.05
                D = delta_path(float(row["strike"]), row["cp"], float(ivl), r, t_marks, S_marks, exp_days)
                Dpaths[tag] = D
                h1, h2, chg_sh, chg_turn = hedge_from_path(D, S_marks, S_exit_h)
                legs.append({"F": pd.Timestamp(F), "X": pd.Timestamp(X), "root": root, "exp": tag_exp, "tag": tag,
                             "symbol": row["symbol"], "cp": row["cp"], "strike": float(row["strike"]),
                             "bid": float(row["bid"]), "ask": float(row["ask"]), "bid_sz": float(row["bid_sz"]),
                             "ask_sz": float(row["ask_sz"]), "iv": float(ivl), "delta": float(row["delta"]) if np.isfinite(row["delta"]) else np.nan,
                             "gamma": float(row["gamma"]), "vega": float(row["vega"]), "theta": float(row["theta"]),
                             "x_bid": xb, "x_ask": xa, "x_missing": missing,
                             "D0": float(D[0]), "D_last": float(D[-1]), "S_hedge0": float(S_marks[0]), "S_hedge_exit": float(S_exit_h),
                             "h1_pnl": h1, "h2_pnl": h2, "chg_sh": chg_sh, "chg_turn": chg_turn, "n_marks": int(len(D))})
            # H3 (threshold 25 shares per unit) for the straddle unit of this expiry
            if "ATM_C" in Dpaths and "ATM_P" in Dpaths:
                Dst = Dpaths["ATM_C"] + Dpaths["ATM_P"]
                p3, sh3, o3 = h3_threshold(Dst, S_marks, S_exit_h)
                rec_root[f"{tag_exp}_straddle_h3_pnl"], rec_root[f"{tag_exp}_straddle_h3_sh"], rec_root[f"{tag_exp}_straddle_h3_orders"] = p3, sh3, o3
                rec_root[f"{tag_exp}_straddle_h2_orders"] = int(np.sum(np.abs(np.diff(Dst)) > 0.5)) + 2
        if ok_root:
            roots.append(rec_root)
    L = pd.DataFrame(legs)
    R = pd.DataFrame(roots)
    os.makedirs(os.path.join(OUTD, "legs"), exist_ok=True)
    os.makedirs(os.path.join(OUTD, "roots"), exist_ok=True)
    R.to_parquet(os.path.join(OUTD, "roots", f"{F}.parquet"), index=False)
    L.to_parquet(out_legs, index=False)
    return F, f"legs={len(L)} roots={len(R)} x_cov={x_cov:.2f}", time.time() - t0


def build_inputs(pairs):
    """Main-process preparation: candidate roots (stocks pass common/price/event screens), closes at F and X,
    daily paths (F..X), plus root-month features from DoltHub (ADV20, HV21, HV252, beta to SPY)."""
    from equity_vix import StockData
    stk = StockData()
    px = stk.px[["date", "act_symbol", "close", "volume", "ret"]].copy()
    px["root"] = normalize_root(px["act_symbol"].astype(str))
    px = px.drop_duplicates(["root", "date"])
    piv_close = px.pivot(index="date", columns="root", values="close")
    piv_ret = px.pivot(index="date", columns="root", values="ret")
    # remove split-day returns (raw, unadjusted DoltHub prices) from HV / beta / RV computations
    spl = stk.splits.copy()
    spl["root"] = normalize_root(spl["act_symbol"].astype(str))
    for r_, d_ in zip(spl["root"], spl["ex_date"]):
        if r_ in piv_ret.columns and d_ in piv_ret.index:
            piv_ret.at[d_, r_] = np.nan
    vol = px.pivot(index="date", columns="root", values="volume")
    dv = (piv_close * vol)
    jobs, feats = [], []
    dates = piv_close.index
    for F, X in pairs:
        Fts, Xts = pd.Timestamp(F), pd.Timestamp(X)
        if Fts not in dates or Xts not in dates:
            continue
        cF, cX = piv_close.loc[Fts], piv_close.loc[Xts]
        bad = stk.event_tickers(Fts, Xts)
        bad_roots = set(normalize_root(pd.Series(list(bad), dtype=str))) if bad else set()
        com = stk.common.copy()
        com.index = normalize_root(pd.Series(com.index.astype(str))).values
        com = com[~com.index.duplicated()]
        cand = [r for r in cF.index[(cF >= 10)] if r not in bad_roots and com.get(r, 1) == 1]
        cols = sorted(set(cand) | (set(ETFS) & set(piv_close.columns)))
        win = piv_close.loc[(dates >= Fts) & (dates <= Xts), cols]
        paths = {r: win[r].dropna() for r in win.columns}
        # features (strictly before F for ADV/HV; betas on prior 252 sessions vs SPY)
        hist = piv_ret.loc[(dates < Fts), cols].tail(252)
        hist21 = hist.tail(21)
        adv = dv.loc[(dates < Fts), cols].tail(20).mean()
        spy = hist["SPY"]
        hc = hist.sub(hist.mean())
        sc_ = spy - spy.mean()
        cov = hc.mul(sc_, axis=0).sum() / (hist.notna().sum() - 1)
        beta = (cov / spy.var()).where(hist.notna().sum() > 150)
        hv252 = np.log1p(hist).std() * np.sqrt(252)
        hv21 = np.log1p(hist21).std() * np.sqrt(252)
        # realised outcomes over (F, X]
        fut = piv_ret.loc[(dates > Fts) & (dates <= Xts), cols]
        lr = np.log1p(fut)
        rv = (lr ** 2).sum()
        resid = lr.sub(lr["SPY"].values[:, None] * beta.reindex(lr.columns).values[None, :])
        idio = (resid ** 2).sum(min_count=1).where(beta.reindex(lr.columns).notna())
        jump = (lr ** 2).max() / rv
        f = pd.DataFrame({"adv20": adv, "hv21": hv21, "hv252": hv252, "beta": beta, "rv": rv, "rv_idio": idio,
                          "jump_share": jump, "n_days": lr.notna().sum()})
        f = f[f.index.isin(set(cand) | set(ETFS))]
        f.index.name = "root"
        f = f.reset_index().assign(F=Fts, X=Xts)
        feats.append(f)
        jobs.append((F, X, {"candidates": cand, "closeF": cF.dropna().to_dict(), "closeX": cX.dropna().to_dict(),
                            "paths": paths}))
    return jobs, pd.concat(feats, ignore_index=True)


def main(start="2013-04", end="2026-08", workers=3):
    os.makedirs(OUTD, exist_ok=True)
    fds = formation_dates(start, pd.Period(end, "M") + 1)
    pairs = list(zip(fds[:-1], fds[1:]))
    jobs, feats = build_inputs(pairs)
    feats.to_parquet(os.path.join(OUTD, "root_features_dolthub.parquet"), index=False)
    print("jobs", len(jobs), "avg candidates", np.mean([len(j[2]["candidates"]) for j in jobs]), flush=True)
    import multiprocessing as mp
    with mp.get_context("spawn").Pool(workers) as pool:
        for F, msg, secs in pool.imap_unordered(process_month, jobs):
            print(F, msg, f"{secs:.0f}s", flush=True)


if __name__ == "__main__":
    main(*sys.argv[1:3])
