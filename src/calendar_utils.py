"""Formation-date calendar following the replication code:
formation on the 3rd Friday of each month (previous trading day if holiday);
options held to the last trading day of the next month's standard expiration."""
import datetime as dt
import pandas as pd
import exchange_calendars as xc

_XNYS = xc.get_calendar("XNYS")


def third_friday(year: int, month: int) -> dt.date:
    d = dt.date(year, month, 1)
    offset = (4 - d.weekday()) % 7  # Friday = 4
    return d + dt.timedelta(days=offset + 14)


def is_session(d: dt.date) -> bool:
    return _XNYS.is_session(pd.Timestamp(d))


def prev_session_on_or_before(d: dt.date) -> dt.date:
    ts = pd.Timestamp(d)
    if _XNYS.is_session(ts):
        return d
    return _XNYS.date_to_session(ts, direction="previous").date()


def formation_dates(start: str, end: str) -> list:
    """Last trading day on/before the 3rd Friday, for every month in [start, end]."""
    out = []
    for p in pd.period_range(start, end, freq="M"):
        out.append(prev_session_on_or_before(third_friday(p.year, p.month)))
    return out


def sessions(start, end) -> list:
    return [x.date() for x in _XNYS.sessions_in_range(pd.Timestamp(start), pd.Timestamp(end))]


def close_time_utc(d: dt.date) -> pd.Timestamp:
    """Regular (or early) close for session d, UTC."""
    return _XNYS.session_close(pd.Timestamp(d)).tz_convert("UTC")


def et_to_utc(d: dt.date, hhmm: str) -> pd.Timestamp:
    return pd.Timestamp(f"{d} {hhmm}", tz="America/New_York").tz_convert("UTC")


if __name__ == "__main__":
    fds = formation_dates("2013-01", "2026-10")
    for f in fds:
        tf = third_friday(f.year, f.month)
        if f != tf:
            print("holiday-adjusted:", tf, "->", f)
    print(len(fds), fds[0], fds[-1])
