"""Download OPRA consolidated BBO (cbbo-1m) single-minute full-market snapshots
from Databento and convert to compact parquet of equity-option quotes.

Usage: python opra_download.py close 2013-04 2026-09   (snapshot at close-1min on formation dates)
       python opra_download.py at 15:45 2021-01 2026-09 (snapshot at a fixed ET time on formation dates)
The API key is read from DATABENTO_API_KEY (never stored in the repo).
"""
import os, sys, json, time, datetime as dt
from concurrent.futures import ThreadPoolExecutor
import numpy as np, pandas as pd
import databento as db
sys.path.insert(0, os.path.dirname(__file__))
from calendar_utils import formation_dates, close_time_utc, et_to_utc

DATA = os.environ.get("SOM_DATA", "/home/user/data")
LEDGER = os.path.join(DATA, "databento_pull_log.csv")


def parse_osi(sym: np.ndarray) -> pd.DataFrame:
    s = pd.Series(sym, dtype="string")
    root = s.str.slice(0, 6).str.strip()
    exp = pd.to_datetime(s.str.slice(6, 12), format="%y%m%d", errors="coerce")
    cp = s.str.slice(12, 13)
    strike = pd.to_numeric(s.str.slice(13, 21), errors="coerce") / 1000.0
    return pd.DataFrame({"root": root, "expiration": exp, "cp": cp, "strike": strike})


def to_parquet(dbn_path: str, out_path: str, snap_date: dt.date, max_days=80):
    store = db.DBNStore.from_file(dbn_path)
    arr = store.to_ndarray()
    # instrument_id -> raw symbol from metadata mappings
    maps = store.metadata.mappings
    iid2sym = {}
    for raw, lst in maps.items():
        for m in lst:
            iid2sym[int(m["symbol"])] = raw
    iid = arr["instrument_id"].astype(np.int64)
    syms = np.array([iid2sym.get(int(i), "") for i in iid], dtype=object)
    meta = parse_osi(syms)
    df = pd.DataFrame({
        "symbol": syms,
        "bid": np.where(arr["bid_px_00"] == np.iinfo(np.int64).max, np.nan, arr["bid_px_00"] / 1e9),
        "ask": np.where(arr["ask_px_00"] == np.iinfo(np.int64).max, np.nan, arr["ask_px_00"] / 1e9),
        "bid_sz": arr["bid_sz_00"].astype(np.int64),
        "ask_sz": arr["ask_sz_00"].astype(np.int64),
        "last_px": np.where(arr["price"] == np.iinfo(np.int64).max, np.nan, arr["price"] / 1e9),
        "ts_event": arr["ts_event"],
    })
    df = pd.concat([df, meta], axis=1)
    dte = (df["expiration"] - pd.Timestamp(snap_date)).dt.days
    df = df[(dte >= 0) & (dte <= max_days) & df["strike"].notna()]
    df["date"] = pd.Timestamp(snap_date)
    df.to_parquet(out_path, index=False)
    return len(arr), len(df), arr.dtype.itemsize * len(arr)


def fetch_minute(client, d: dt.date, t_utc: pd.Timestamp, tag: str, outdir: str):
    os.makedirs(outdir, exist_ok=True)
    pq = os.path.join(outdir, f"{d}.parquet")
    if os.path.exists(pq):
        return d, "cached", 0, 0, 0
    raw = os.path.join(outdir, f"{d}.dbn.zst")
    for attempt in range(5):
        try:
            client.timeseries.get_range(dataset="OPRA.PILLAR", schema="cbbo-1m", symbols="ALL_SYMBOLS",
                                        start=t_utc, end=t_utc + pd.Timedelta(minutes=1), path=raw)
            break
        except Exception as e:  # retry transient gateway errors
            print("retry", d, attempt, repr(e)[:200], flush=True)
            time.sleep(2 ** attempt * 5)
    else:
        return d, "failed", 0, 0, 0
    n_all, n_keep, nbytes = to_parquet(raw, pq, d)
    os.remove(raw)
    with open(LEDGER, "a") as f:
        f.write(f"{dt.datetime.utcnow().isoformat()},OPRA.PILLAR,cbbo-1m,ALL_SYMBOLS,{tag},{d},{t_utc},{n_all},{nbytes},{nbytes/1e9*2.0:.4f}\n")
    return d, "ok", n_all, n_keep, nbytes


def submit_batch(client, jobs, tag, outdir, workers=8):
    """Submit one Databento batch job per (date, minute), concurrently. Batch output carries the
    instrument_id -> raw symbol mappings (the streaming endpoint does not for ALL_SYMBOLS)."""
    import threading
    os.makedirs(outdir, exist_ok=True)
    reg_path = os.path.join(outdir, "_jobs.json")
    reg = json.load(open(reg_path)) if os.path.exists(reg_path) else {}
    lock = threading.Lock()
    todo = [(d, t) for d, t in jobs if str(d) not in reg and not os.path.exists(os.path.join(outdir, f"{d}.parquet"))]

    def one(dt_):
        d, t = dt_
        for attempt in range(6):
            try:
                j = client.batch.submit_job(dataset="OPRA.PILLAR", symbols="ALL_SYMBOLS", schema="cbbo-1m",
                                            start=t, end=t + pd.Timedelta(minutes=1), encoding="dbn", compression="zstd")
                with lock:
                    reg[str(d)] = {"job_id": j["id"], "start_utc": str(t), "tag": tag}
                    json.dump(reg, open(reg_path, "w"), indent=1)
                print("submitted", d, j["id"], flush=True)
                return
            except Exception as e:
                print("submit retry", d, repr(e)[:200], flush=True); time.sleep(2 ** attempt * 5)
        print("SUBMIT FAILED", d, flush=True)

    with ThreadPoolExecutor(max_workers=workers) as ex:
        list(ex.map(one, todo))
    print("submitted/registered", len(reg), flush=True)
    return reg


def collect_batch(client, outdir, snap_dates):
    reg_path = os.path.join(outdir, "_jobs.json")
    reg = json.load(open(reg_path))
    pending = {k: v for k, v in reg.items() if not os.path.exists(os.path.join(outdir, f"{k}.parquet"))}
    while pending:
        done_ids = {j["id"] for j in client.batch.list_jobs(states=["done"], since="2026-09-29")}
        for k, v in list(pending.items()):
            if v["job_id"] not in done_ids:
                continue
            tmp = os.path.join(outdir, "_tmp_" + k)
            paths = client.batch.download(job_id=v["job_id"], output_dir=tmp)
            dbn = [str(p) for p in paths if str(p).endswith(".dbn.zst")][0]
            d = dt.date.fromisoformat(k)
            n_all, n_keep, nbytes = to_parquet(dbn, os.path.join(outdir, f"{k}.parquet"), d)
            with open(LEDGER, "a") as f:
                f.write(f"{dt.datetime.utcnow().isoformat()},OPRA.PILLAR,cbbo-1m,ALL_SYMBOLS,{v['tag']},{k},{v['start_utc']},{n_all},{nbytes},{nbytes/1e9*2.0:.4f}\n")
            import shutil; shutil.rmtree(tmp, ignore_errors=True)
            print(k, "ok", n_all, n_keep, nbytes, flush=True)
            pending.pop(k)
        if pending:
            print("waiting on", len(pending), flush=True); time.sleep(30)


def main():
    mode = sys.argv[1]
    if mode == "close":
        start, end = sys.argv[2], sys.argv[3]
        tag, outdir = "close-1m", os.path.join(DATA, "opra", "close_snap")
        jobs = [(d, close_time_utc(d) - pd.Timedelta(minutes=1)) for d in formation_dates(start, end)]
    elif mode == "at":
        hhmm, start, end = sys.argv[2], sys.argv[3], sys.argv[4]
        tag, outdir = f"at-{hhmm}", os.path.join(DATA, "opra", f"snap_{hhmm.replace(':','')}")
        jobs = [(d, et_to_utc(d, hhmm)) for d in formation_dates(start, end)]
    else:
        raise SystemExit("mode must be close|at")
    if not os.path.exists(LEDGER):
        with open(LEDGER, "w") as f:
            f.write("utc,dataset,schema,symbols,tag,date,start_utc,records,bytes_uncompressed,est_usd_at_2_per_GB\n")
    client = db.Historical()
    submit_batch(client, jobs, tag, outdir)
    collect_batch(client, outdir, [d for d, _ in jobs])

if __name__ == "__main__":
    main()
