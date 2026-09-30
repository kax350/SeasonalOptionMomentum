"""Underlying-stock panel built from the free DoltHub `post-no-preference/stocks` database
(raw, unadjusted daily OHLCV; dividends by ex-date; splits by ex-date; symbol metadata).

PROXY notes (vs CRSP in the paper):
  * identifiers are tickers (act_symbol), not PERMNO/CUSIP;
  * share codes 10/11 approximated from Nasdaq security names (see common_stock_flag);
  * daily 'ret' is the raw close-to-close price return; firm-months with dividends or splits
    inside the holding window are excluded exactly as in the replication code, so price return
    equals CRSP RET on every day that is actually used.
"""
import os, re
import numpy as np, pandas as pd

DATA = os.environ.get("SOM_DATA", "/home/user/data")
SDIR = os.path.join(DATA, "stocks")

_EXCL = re.compile(r"depositary|\bADRs?\b|\bADS\b|\bETF\b|\bETN\b|\bfund\b|closed.end|preferred|preference|"
                   r"\bpfd\b|warrant|\bunits?\b|\brights?\b|\bnotes?\b|debenture|\bbonds?\b|beneficial interest|"
                   r"limited partner|\bL\.?P\.?\b|\btrust\b|ordinary shares|index|when.issued|subordinate",
                   re.I)
_COMMON = re.compile(r"common stock|capital stock", re.I)
_REIT = re.compile(r"\bREIT\b|realty|real estate|properties\b|property trust", re.I)


def common_stock_flag(sym: pd.DataFrame) -> pd.Series:
    """1 = US common stock proxy for CRSP shrcd 10/11; 0 = excluded; NaN = no metadata."""
    nm = sym["security_name"].fillna("")
    ok = nm.str.contains(_COMMON) & ~nm.str.contains(_EXCL) & (sym["is_etf"].fillna(0) == 0) \
        & (sym["is_test_issue"].fillna(0) == 0)
    reit = nm.str.contains(_REIT)
    flag = pd.Series(np.where(ok & ~reit, 1.0, 0.0), index=sym.index)
    return flag


def load_symbols() -> pd.DataFrame:
    s = pd.read_parquet(os.path.join(SDIR, "symbol.parquet"))
    s["common"] = common_stock_flag(s)
    return s.set_index("act_symbol")


def load_ohlcv(start="2012-06-01") -> pd.DataFrame:
    df = pd.read_parquet(os.path.join(SDIR, "ohlcv.parquet"), columns=["date", "act_symbol", "close", "volume"])
    df["date"] = pd.to_datetime(df["date"])
    df["close"] = df["close"].astype("float64")      # DoltHub decimals load as nullable Float64
    df["volume"] = df["volume"].astype("float64")
    df = df[df["date"] >= pd.Timestamp(start)]
    df = df.sort_values(["act_symbol", "date"]).reset_index(drop=True)
    df["ret"] = df.groupby("act_symbol")["close"].pct_change()
    return df


def load_dividends() -> pd.DataFrame:
    d = pd.read_parquet(os.path.join(SDIR, "dividend.parquet"))
    d["ex_date"] = pd.to_datetime(d["ex_date"])
    d["amount"] = d["amount"].astype("float64")
    return d[d["amount"] > 0]


def load_splits() -> pd.DataFrame:
    s = pd.read_parquet(os.path.join(SDIR, "split.parquet"))
    s["ex_date"] = pd.to_datetime(s["ex_date"])
    return s


def detect_price_splits(ohlcv: pd.DataFrame, tol=0.06) -> pd.DataFrame:
    """Fallback split detector for dates not covered by the split table (it starts 2014-03):
    overnight price ratio close to a common split factor (2,3,4,1.5,1/2,1/3,...) with |log ret|>0.35."""
    x = ohlcv[["act_symbol", "date", "close"]].copy()
    x["prev"] = x.groupby("act_symbol")["close"].shift()
    x = x.dropna()
    r = x["prev"] / x["close"]
    big = np.abs(np.log(r)) > 0.35
    fac = np.array([2, 3, 4, 5, 1.5, 10, 1 / 2, 1 / 3, 1 / 4, 1 / 5, 2 / 3, 1 / 10, 1.25, 7, 8, 20])
    near = np.min(np.abs(r.values[:, None] / fac[None, :] - 1), axis=1) < tol
    out = x.loc[big & near, ["act_symbol", "date"]].rename(columns={"date": "ex_date"})
    return out


if __name__ == "__main__":
    s = load_symbols()
    print("symbols", len(s), "common proxy", int(s["common"].sum()))
    o = load_ohlcv()
    print(o.shape, o.date.min(), o.date.max())
    ps = detect_price_splits(o)
    print("price-detected split events", len(ps), ps[ps.ex_date < "2014-04-01"].shape)
