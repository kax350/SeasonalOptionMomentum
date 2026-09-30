"""Build the monthly firm-level equity-VIX return panels (sorting + holding samples) for every
formation date whose OPRA close snapshot is available.

Output: $SOM_DATA/panel/vix_sort.parquet, vix_hold.parquet  (one row per root x formation date)
"""
import os, sys, glob, time, datetime as dt, warnings
import pandas as pd
warnings.filterwarnings("ignore")
sys.path.insert(0, os.path.dirname(__file__))
from equity_vix import StockData, RateCurve, select_chain, build_firm_months

DATA = os.environ.get("SOM_DATA", "/home/user/data")
OUT = os.path.join(DATA, "panel")
KEEP = ["root", "ticker", "date", "exdate", "exdate_trade", "days_expire", "St_start", "St_end", "Forward", "K0", "K1",
        "strike_min", "strike_max", "delta_min", "delta_max", "num_put", "num_call", "num_strikes", "sigma2", "sigma2_bid",
        "sigma2_ask", "sigma2_tick", "hedge_turnover", "VIX_Prc", "VIX_Prc_bid", "VIX_Prc_ask", "VIX_BA_percent", "Initial_delta", "IV_avg", "Rf", "rf",
        "linear_rate", "Static_VIX_Payoff", "Static_VIX_Return", "Delta_Hedge_payoff_Corridor",
        "Dynamic_VIX_Payoff_Corridor", "Dynamic_VIX_Return_Corridor", "Dynamic_VIX_Return", "Monthly_RV", "VSR",
        "RV_Corridor", "VSR_Corridor", "n_days", "n_opt", "sample"]


def main(snap_dir=os.path.join(DATA, "opra", "close_snap")):
    os.makedirs(os.path.join(OUT, "by_date"), exist_ok=True)
    stk, rates = StockData(), RateCurve()
    files = sorted(glob.glob(os.path.join(snap_dir, "20*.parquet")))
    for f in files:
        d = dt.date.fromisoformat(os.path.basename(f)[:10])
        outp = os.path.join(OUT, "by_date", f"{d}.parquet")
        if os.path.exists(outp):
            continue
        t = time.time()
        snap = pd.read_parquet(f)
        ch = select_chain(snap, d)
        parts = []
        for smp in ("sort", "hold"):
            fm = build_firm_months(d, ch, stk, rates, sample=smp)
            if len(fm):
                parts.append(fm[[c for c in KEEP if c in fm.columns]])
        if parts:
            pd.concat(parts, ignore_index=True).to_parquet(outp, index=False)
        print(d, "chain", len(ch), "firms", [len(p) for p in parts], f"{time.time()-t:.1f}s", flush=True)
    allp = [pd.read_parquet(p) for p in sorted(glob.glob(os.path.join(OUT, "by_date", "*.parquet")))]
    panel = pd.concat(allp, ignore_index=True)
    panel[panel["sample"] == "sort"].to_parquet(os.path.join(OUT, "vix_sort.parquet"), index=False)
    panel[panel["sample"] == "hold"].to_parquet(os.path.join(OUT, "vix_hold.parquet"), index=False)
    print("panel", panel.groupby("sample").size().to_dict())


if __name__ == "__main__":
    main(*(sys.argv[1:]))
