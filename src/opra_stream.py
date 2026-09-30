"""Fast path for OPRA single-minute full-market snapshots: stream cbbo-1m ALL_SYMBOLS for one
minute (Databento timeseries), then map instrument_id -> OSI raw symbol with the free
symbology.resolve endpoint for the parents (roots) of interest.

Usage: python opra_stream.py close 2013-04 2026-09
       python opra_stream.py at 15:45 2021-01 2026-09 [--roots-from-panel]
"""
import os, sys, time, json, datetime as dt
from concurrent.futures import ThreadPoolExecutor
import numpy as np, pandas as pd
import databento as db

sys.path.insert(0, os.path.dirname(__file__))
from calendar_utils import formation_dates, close_time_utc, et_to_utc
from opra_download import parse_osi

DATA = os.environ.get("SOM_DATA", "/home/user/data")
LEDGER = os.path.join(DATA, "databento_pull_log.csv")
_PX = None


def candidate_roots(d: dt.date):
    """Normalized tickers (OSI-root style) of stocks trading >= $4 on date d (DoltHub)."""
    global _PX
    if _PX is None:
        px = pd.read_parquet(os.path.join(DATA, "stocks", "ohlcv.parquet"), columns=["date", "act_symbol", "close"])
        px["date"] = pd.to_datetime(px["date"])
        _PX = px[px["date"] >= "2013-01-01"]
    x = _PX[(_PX["date"] == pd.Timestamp(d)) & (_PX["close"] >= 4)]["act_symbol"].astype(str)
    roots = x.str.replace(".", "", regex=False).str.replace(" ", "", regex=False).str.replace("/", "", regex=False)
    roots = roots[roots.str.fullmatch(r"[A-Z]{1,6}")]
    return sorted(set(roots))


def resolve_parents(client, d: dt.date, roots, chunk=400, workers=4):
    iid2sym = {}
    chunks = [roots[i:i + chunk] for i in range(0, len(roots), chunk)]

    def one(part):
        for attempt in range(6):
            try:
                r = client.symbology.resolve(dataset="OPRA.PILLAR", symbols=[p + ".OPT" for p in part],
                                             stype_in="parent", stype_out="instrument_id",
                                             start_date=str(d), end_date=str(d + dt.timedelta(days=1)))
                out = {}
                for raw, lst in r["result"].items():
                    for m in lst:
                        out[int(m["s"])] = raw
                return out
            except Exception as e:
                print("resolve retry", d, attempt, repr(e)[:150], flush=True)
                time.sleep(3 * 2 ** attempt)
        raise RuntimeError("resolve failed")

    with ThreadPoolExecutor(max_workers=workers) as ex:
        for m in ex.map(one, chunks):
            iid2sym.update(m)
    return iid2sym


def snapshot(client, d: dt.date, t_utc: pd.Timestamp, tag: str, outdir: str, roots=None, max_days=80):
    os.makedirs(outdir, exist_ok=True)
    out = os.path.join(outdir, f"{d}.parquet")
    if os.path.exists(out):
        return d, "cached"
    raw = os.path.join(outdir, f"_{d}.dbn.zst")
    if not os.path.exists(raw):
        for attempt in range(6):
            try:
                client.timeseries.get_range(dataset="OPRA.PILLAR", schema="cbbo-1m", symbols="ALL_SYMBOLS",
                                            start=t_utc, end=t_utc + pd.Timedelta(minutes=1), path=raw)
                break
            except Exception as e:
                print("stream retry", d, attempt, repr(e)[:150], flush=True)
                time.sleep(5 * 2 ** attempt)
        else:
            return d, "stream-failed"
        arr0 = db.DBNStore.from_file(raw).to_ndarray()
        with open(LEDGER, "a") as f:
            nb = arr0.dtype.itemsize * len(arr0)
            f.write(f"{dt.datetime.utcnow().isoformat()},OPRA.PILLAR,cbbo-1m,ALL_SYMBOLS(stream),{tag},{d},{t_utc},{len(arr0)},{nb},{nb/1e9*2.0:.4f}\n")
    arr = db.DBNStore.from_file(raw).to_ndarray()
    roots = roots if roots is not None else candidate_roots(d)
    iid2sym = resolve_parents(client, d, roots)
    iid = arr["instrument_id"].astype(np.int64)
    sym = pd.Series(iid).map(iid2sym)
    keep = sym.notna().values
    a = arr[keep]
    syms = sym[keep].values
    meta = parse_osi(syms)
    mx = np.iinfo(np.int64).max
    df = pd.DataFrame({
        "symbol": syms,
        "bid": np.where(a["bid_px_00"] == mx, np.nan, a["bid_px_00"] / 1e9),
        "ask": np.where(a["ask_px_00"] == mx, np.nan, a["ask_px_00"] / 1e9),
        "bid_sz": a["bid_sz_00"].astype(np.int64), "ask_sz": a["ask_sz_00"].astype(np.int64),
        "last_px": np.where(a["price"] == mx, np.nan, a["price"] / 1e9), "ts_event": a["ts_event"],
    })
    df = pd.concat([df, meta], axis=1)
    dte = (df["expiration"] - pd.Timestamp(d)).dt.days
    df = df[(dte >= 0) & (dte <= max_days) & df["strike"].notna()]
    df["date"] = pd.Timestamp(d)
    df.to_parquet(out, index=False)
    os.remove(raw)
    return d, f"ok recs={len(arr)} mapped={int(keep.sum())} kept={len(df)} roots={len(roots)}"


def main():
    mode = sys.argv[1]
    client = db.Historical()
    if mode == "close":
        start, end = sys.argv[2], sys.argv[3]
        tag, outdir = "close-1m", os.path.join(DATA, "opra", "close_snap")
        jobs = [(d, close_time_utc(d) - pd.Timedelta(minutes=1)) for d in formation_dates(start, end)]
    else:
        hhmm, start, end = sys.argv[2], sys.argv[3], sys.argv[4]
        tag, outdir = f"at-{hhmm}", os.path.join(DATA, "opra", f"snap_{hhmm.replace(':', '')}")
        jobs = [(d, et_to_utc(d, hhmm)) for d in formation_dates(start, end)]
    if not os.path.exists(LEDGER):
        with open(LEDGER, "w") as f:
            f.write("utc,dataset,schema,symbols,tag,date,start_utc,records,bytes_uncompressed,est_usd\n")
    workers = int(os.environ.get("SOM_WORKERS", "2"))
    with ThreadPoolExecutor(max_workers=workers) as ex:
        for res in ex.map(lambda j: snapshot(client, j[0], j[1], tag, outdir), jobs):
            print(*res, flush=True)


if __name__ == "__main__":
    main()
