"""Open interest for specific OPRA contracts on a formation date (Databento OPRA.PILLAR statistics,
stat_type 9 = OPEN_INTEREST, published pre-open ~06:30 ET = OCC OI as of the previous close;
this matches OptionMetrics' open_interest convention on `date`).

Only the contracts actually needed (next-month expiry, OTM, candidate firms) are requested, in
chunks of <=2000 raw symbols, to keep cost minimal."""
import os, sys, time, datetime as dt
import numpy as np, pandas as pd
import databento as db

DATA = os.environ.get("SOM_DATA", "/home/user/data")
LEDGER = os.path.join(DATA, "databento_pull_log.csv")
OI_DIR = os.path.join(DATA, "opra", "oi")


def fetch_oi(client, date: dt.date, symbols, chunk=200):
    os.makedirs(OI_DIR, exist_ok=True)
    out = os.path.join(OI_DIR, f"{date}.parquet")
    if os.path.exists(out):
        return pd.read_parquet(out)
    st = pd.Timestamp(f"{date} 05:00", tz="America/New_York").tz_convert("UTC")
    en = pd.Timestamp(f"{date} 09:25", tz="America/New_York").tz_convert("UTC")
    syms = sorted(set(symbols))
    frames, nbytes = [], 0
    for i in range(0, len(syms), chunk):
        part = syms[i:i + chunk]
        for attempt in range(5):
            try:
                store = client.timeseries.get_range(dataset="OPRA.PILLAR", schema="statistics", symbols=part,
                                                    stype_in="raw_symbol", start=st, end=en)
                break
            except Exception as e:
                print("retry", date, attempt, repr(e)[:160], flush=True)
                time.sleep(5 * 2 ** attempt)
        else:
            raise RuntimeError(f"OI fetch failed {date}")
        arr = store.to_ndarray()
        nbytes += arr.dtype.itemsize * len(arr)
        if len(arr) == 0:
            continue
        iid2sym = {}
        for raw, lst in store.metadata.mappings.items():
            for m in lst:
                iid2sym[int(m["symbol"])] = raw
        a = arr[arr["stat_type"] == 9]
        df = pd.DataFrame({"instrument_id": a["instrument_id"].astype(np.int64), "open_interest": a["quantity"].astype(np.int64)})
        df["symbol"] = df["instrument_id"].map(iid2sym)
        frames.append(df.groupby("symbol", as_index=False)["open_interest"].max())
    res = pd.concat(frames, ignore_index=True) if frames else pd.DataFrame(columns=["symbol", "open_interest"])
    res = res.groupby("symbol", as_index=False)["open_interest"].max()
    # symbols with no OI record published -> OI = 0 (OCC publishes OI only for contracts with OI>0)
    missing = pd.DataFrame({"symbol": [s for s in syms if s not in set(res["symbol"])], "open_interest": 0})
    res = pd.concat([res, missing], ignore_index=True)
    res.to_parquet(out, index=False)
    with open(LEDGER, "a") as f:
        f.write(f"{dt.datetime.utcnow().isoformat()},OPRA.PILLAR,statistics,raw_symbols[{len(syms)}],oi,{date},{st},{0},{nbytes},{nbytes/1e9*11.0:.4f}\n")
    return res
