"""Step A driver: per-unit P&L table for all pre-registered structures on the candidate names of
every month (formation 2019-06 ... 2026-08; entry 15:45 ET, exit 15:00 ET on the expiration day).

Candidates per month = liquid universe L_base (all names, needed for benchmarks B3/B4/B5)
                     ∪ top/bottom 25 names of the eligible universe P by seasonal, momentum, HV-IV.
Output: $SOM_DATA/retail/positions_<entry>.parquet and universe_<entry>.parquet
"""
import os, sys, glob, time, datetime as dt, warnings
from multiprocessing import Pool
import numpy as np, pandas as pd
warnings.filterwarnings("ignore")
sys.path.insert(0, os.path.dirname(__file__))
from calendar_utils import formation_dates
from equity_vix import RateCurve, StockData, normalize_root
from retail import evaluate_month, load_chain
from signals_universe import score_grid, adv20

DATA = os.environ.get("SOM_DATA", "/home/user/data")
OUTD = os.path.join(DATA, "retail")
TOPN = 25


def month_universe(F, X, stk: StockData, scores_F: pd.DataFrame, entry_when: str, px_roots: pd.DataFrame):
    ch = load_chain(F, entry_when)
    if ch is None:
        return None
    ch = ch.copy()
    ch["ticker"] = stk.root_to_ticker(ch["root"])
    ch = ch[ch["ticker"].notna()]
    bad = stk.event_tickers(pd.Timestamp(F), pd.Timestamp(X))       # dividends/splits in (F, X]
    prev_close = stk.close_on(stk.px[stk.px["date"] < pd.Timestamp(F)]["date"].max())
    u = ch.groupby("root").agg(ticker=("ticker", "first")).reset_index()
    u["common"] = u["ticker"].map(stk.common).fillna(stk.unknown_common_default)
    u["no_event"] = ~u["ticker"].isin(bad)
    u["prev_close"] = u["ticker"].map(prev_close)
    # ATM quote quality and OTM strike count at entry
    q = []
    for root, g in ch.groupby("root"):
        S = u.loc[u["root"] == root, "prev_close"].iloc[0]
        if not np.isfinite(S):
            q.append((root, np.nan, 0)); continue
        both = sorted(set(g[g["cp"] == "C"]["strike"]) & set(g[g["cp"] == "P"]["strike"]))
        if not both:
            q.append((root, np.nan, 0)); continue
        k = min(both, key=lambda x: abs(x - S))
        a = g[g["strike"] == k]
        ok = (a["bid"] > 0).all()
        rs = ((a["ask"] - a["bid"]) / a["mid"]).max() if ok else np.inf
        n_otm = int((((g["cp"] == "P") & (g["strike"] < S)) | ((g["cp"] == "C") & (g["strike"] > S)))[g["bid"] > 0].sum())
        q.append((root, rs, n_otm))
    q = pd.DataFrame(q, columns=["root", "atm_rel_spread", "n_otm_bid"])
    u = u.merge(q, on="root", how="left")
    adv = adv20(px_roots, F)
    u["adv20"] = u["root"].map(adv)
    u["eligible_P"] = (u["common"] == 1) & u["no_event"] & (u["prev_close"] >= 5)
    base = u["eligible_P"] & (u["prev_close"] >= 20) & (u["atm_rel_spread"] <= 0.10) & (u["n_otm_bid"] >= 8)
    u["adv_rank"] = u["adv20"].where(base).rank(ascending=False)
    u["L"] = base & (u["adv_rank"] <= 500)
    baset = u["eligible_P"] & (u["prev_close"] >= 20) & (u["atm_rel_spread"] <= 0.05) & (u["n_otm_bid"] >= 8)
    u["adv_rank_t"] = u["adv20"].where(baset).rank(ascending=False)
    u["Ltight"] = baset & (u["adv_rank_t"] <= 250)
    u = u.merge(scores_F[["root", "seasonal", "mom_2_12", "lag1", "pct_seasonal"]], on="root", how="left")
    u["F"], u["X"] = pd.Timestamp(F), pd.Timestamp(X)
    return u


def hv_iv(u, px_roots, F, panel_close):
    w = px_roots[(px_roots["date"] < pd.Timestamp(F)) & (px_roots["date"] >= pd.Timestamp(F) - pd.Timedelta(days=370))]
    w = w.sort_values(["root", "date"])
    lr = np.log(w["close"]).groupby(w["root"]).diff()
    hv = lr.groupby(w["root"]).std() * np.sqrt(252)
    iv = panel_close.set_index("root")["IV_avg"]
    return np.log(u["root"].map(hv)) - np.log(u["root"].map(iv))


def _work(args):
    F, X, entry_when, names, paths = args
    cache = os.path.join(OUTD, f"by_month_{entry_when}", f"{F}.parquet")
    if os.path.exists(cache):
        return F, pd.read_parquet(cache), 0.0
    rates = RateCurve()
    t = time.time()
    df = evaluate_month(F, X, entry_when, rates, paths, names=names)
    if len(df):
        os.makedirs(os.path.dirname(cache), exist_ok=True)
        df.to_parquet(cache, index=False)
    return F, df, time.time() - t


def main(entry_when="1545", start="2019-06", end="2026-08", workers=3):
    os.makedirs(OUTD, exist_ok=True)
    fds = formation_dates(start, pd.Period(end, "M") + 1)
    pairs = list(zip(fds[:-1], fds[1:]))
    uni_path = os.path.join(OUTD, f"universe_{entry_when}.parquet")
    px = pd.read_parquet(os.path.join(DATA, "stocks", "ohlcv.parquet"), columns=["date", "act_symbol", "close"])
    px["date"] = pd.to_datetime(px["date"])
    px = px[px["date"] >= pd.Timestamp(start) - pd.Timedelta(days=400)]
    px["close"] = px["close"].astype("float64")
    px["root"] = normalize_root(px["act_symbol"].astype(str))
    if os.path.exists(uni_path):
        uni = pd.read_parquet(uni_path)
        print("loaded cached universe", uni["F"].nunique(), "months", flush=True)
    else:
        stk = StockData()
        pxs = stk.px.copy()
        pxs["root"] = normalize_root(pxs["act_symbol"].astype(str))
        sc = score_grid([F for F, _ in pairs], [X for _, X in pairs])
        sort_panel = pd.read_parquet(os.path.join(DATA, "panel", "vix_sort.parquet"))
        unis = []
        for F, X in pairs:
            if not os.path.exists(os.path.join(DATA, "opra", "snap_1500", f"{X}.parquet")):
                print("no exit snapshot yet", X, flush=True); continue
            u = month_universe(F, X, stk, sc[sc["F"] == pd.Timestamp(F)], entry_when, pxs)
            if u is None:
                print("no entry snapshot", F, flush=True); continue
            u["hv_iv"] = hv_iv(u, pxs, F, sort_panel[sort_panel["date"] == pd.Timestamp(F)])
            unis.append(u)
        uni = pd.concat(unis, ignore_index=True)
        uni.to_parquet(uni_path, index=False)
        del stk, pxs
    jobs = []
    for F, X in pairs:
        u = uni[uni["F"] == pd.Timestamp(F)]
        if u.empty:
            continue
        P = u[u["eligible_P"]]
        cand = set(u.loc[u["L"], "root"]) | set(u.loc[u["Ltight"], "root"])
        for col in ("seasonal", "mom_2_12", "hv_iv"):
            z = P[P[col].notna()].sort_values(col)
            cand |= set(z["root"].head(TOPN)) | set(z["root"].tail(TOPN))
        win = px[(px["date"] >= pd.Timestamp(F)) & (px["date"] <= pd.Timestamp(X)) & px["root"].isin(cand)]
        paths = {r: g.set_index("date")["close"].sort_index() for r, g in win.groupby("root")}
        jobs.append((F, X, entry_when, sorted(cand), paths))
    del px
    print("jobs", len(jobs), "avg names", np.mean([len(j[3]) for j in jobs]), flush=True)
    import multiprocessing as mp
    outs = []
    with mp.get_context("spawn").Pool(workers) as pool:   # spawn: workers do not inherit parent memory
        for F, df, secs in pool.imap_unordered(_work, jobs):
            print(F, "positions", len(df), f"{secs:.0f}s", flush=True)
            if len(df):
                outs.append(df)
    pos = pd.concat(outs, ignore_index=True)
    pos.to_parquet(os.path.join(OUTD, f"positions_{entry_when}.parquet"), index=False)
    print("positions", pos.shape, flush=True)


if __name__ == "__main__":
    main(*sys.argv[1:2])
