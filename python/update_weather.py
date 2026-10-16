"""
Keeps the website's weather current, and measures how New York's climate
has actually shifted since 1948.

What it does, in order:

  1. Downloads monthly heating and cooling degree days for the Central Park
     weather station from NOAA (the official station for New York City).
  2. Checks the data. Every month has to exist exactly once, and the degree
     days have to agree with the month's average temperature.
  3. Writes a clean table the Shiny app reads when it starts.
  4. Fits a trend line through 78 summers and 78 winters to see whether New
     York now needs more cooling and less heating than it used to, and
     writes the numbers the app shows in "Is it getting more expensive?"

    python python/update_weather.py            # download fresh data, rebuild everything
    python python/update_weather.py --offline  # rebuild from the CSV already in the repo

Only uses the Python standard library plus NumPy (and matplotlib for the
chart), so there's nothing special to install.

Hugo Garcia Moreno
"""

from __future__ import annotations

import argparse
import calendar
import csv
import io
import math
import sys
import urllib.request
from pathlib import Path

import numpy as np

REPO = Path(__file__).resolve().parent.parent
RAW_CSV = REPO / "data" / "weather" / "nyc_central_park_monthly_noaa.csv"
APP_DATA = REPO / "shiny_app" / "data"
STATION = "USW00094728"   # New York Central Park
FIRST_YEAR = 1948
NOAA_URL = ("https://www.ncei.noaa.gov/access/services/data/v1"
            "?dataset=global-summary-of-the-month&stations={station}"
            "&startDate={start}&endDate={end}&dataTypes=HTDD,CLDD,TAVG"
            "&format=csv&units=standard")

SUMMER = (6, 7, 8, 9)          # June through September, same months NEADA uses
WINTER = (12, 1, 2, 3)         # December through March


# ---------------------------------------------------------------- download
def download(last_year: int) -> list[dict]:
    """Pull the data ten years at a time so no single request is huge."""
    rows: list[dict] = []
    for start in range(FIRST_YEAR, last_year + 1, 10):
        end = min(start + 9, last_year)
        url = NOAA_URL.format(station=STATION, start=f"{start}-01-01", end=f"{end}-12-31")
        with urllib.request.urlopen(url, timeout=60) as resp:
            text = resp.read().decode("utf-8")
        rows.extend(parse_noaa_csv(text))
        print(f"  got {start}-{end}")
    return rows


def parse_noaa_csv(text: str) -> list[dict]:
    out = []
    for r in csv.DictReader(io.StringIO(text)):
        if not r.get("DATE"):
            continue
        y, m = map(int, r["DATE"].split("-"))
        out.append({"year": y, "month": m, "hdd": int(r["HTDD"]),
                    "cdd": int(r["CLDD"]), "tavg": float(r["TAVG"])})
    return out


def read_raw(path: Path = RAW_CSV) -> list[dict]:
    return parse_noaa_csv(path.read_text())


def write_raw(rows: list[dict], path: Path = RAW_CSV) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["DATE", "CLDD", "HTDD", "TAVG"])
        for r in rows:
            w.writerow([f"{r['year']}-{r['month']:02d}", r["cdd"], r["hdd"], f"{r['tavg']:.1f}"])


# ------------------------------------------------------------------- check
def check(rows: list[dict], tolerance: float = 3.5) -> dict:
    """
    Two checks. First, no month missing or repeated. Second, heating minus
    cooling degree days should equal days in the month times (65 minus the
    average temperature). That's just the definition, so a month that's way
    off usually means a typo or a bad download.
    """
    keys = [(r["year"], r["month"]) for r in rows]
    if len(keys) != len(set(keys)):
        raise ValueError("a month shows up twice")
    y0, m0 = keys[0]
    expected = [(y0 + (m0 - 1 + i) // 12, (m0 - 1 + i) % 12 + 1) for i in range(len(keys))]
    if keys != expected:
        raise ValueError("months are missing or out of order")

    off = []
    for r in rows:
        days = calendar.monthrange(r["year"], r["month"])[1]
        gap = (r["hdd"] - r["cdd"]) - days * (65 - r["tavg"])
        if abs(gap) > tolerance:
            off.append((f"{r['year']}-{r['month']:02d}", round(gap, 1)))
    return {"months": len(rows), "first": keys[0], "last": keys[-1], "off": off}


def complete_years(rows: list[dict]) -> list[dict]:
    """Drop the current year if it isn't finished yet."""
    counts: dict[int, int] = {}
    for r in rows:
        counts[r["year"]] = counts.get(r["year"], 0) + 1
    return [r for r in rows if counts[r["year"]] == 12]


# ------------------------------------------------------------------- trend
def t_quantile(p: float, df: int) -> float:
    """Student t quantile without SciPy (Cornish-Fisher, plenty for df > 20)."""
    z = math.sqrt(2) * _erfinv(2 * p - 1)
    return (z + (z**3 + z) / (4 * df)
            + (5 * z**5 + 16 * z**3 + 3 * z) / (96 * df**2))


def _erfinv(x: float) -> float:
    a = 0.147
    ln = math.log(1 - x * x)
    first = 2 / (math.pi * a) + ln / 2
    return math.copysign(math.sqrt(math.sqrt(first**2 - ln / a) - first), x)


def fit_trend(years: np.ndarray, values: np.ndarray) -> dict:
    """Straight line through the points by least squares, with a 95% range on the slope."""
    X = np.column_stack([np.ones_like(years, dtype=float), years.astype(float)])
    beta, *_ = np.linalg.lstsq(X, values.astype(float), rcond=None)
    resid = values - X @ beta
    n = len(years)
    s2 = resid @ resid / (n - 2)
    se_slope = math.sqrt(s2 / np.sum((years - years.mean()) ** 2))
    t = t_quantile(0.975, n - 2)
    return {"intercept": float(beta[0]), "slope": float(beta[1]),
            "slope_low": float(beta[1] - t * se_slope),
            "slope_high": float(beta[1] + t * se_slope), "n": n}


def season_totals(rows: list[dict]) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """
    Per year: cooling degree days June-September, and heating degree days
    for the winter ending that year (December of the year before through
    March). The first year has no December before it, so it's skipped for
    winter.
    """
    by = {(r["year"], r["month"]): r for r in rows}
    years = sorted({r["year"] for r in rows})
    summer = np.array([sum(by[(y, m)]["cdd"] for m in SUMMER) for y in years], dtype=float)
    winter = []
    for y in years:
        if (y - 1, 12) not in by:
            winter.append(np.nan)
        else:
            winter.append(by[(y - 1, 12)]["hdd"] + sum(by[(y, m)]["hdd"] for m in (1, 2, 3)))
    return np.array(years), summer, np.array(winter, dtype=float)


# ------------------------------------------------------------------ output
def build(rows: list[dict], make_chart: bool = True) -> dict:
    full = complete_years(rows)
    APP_DATA.mkdir(parents=True, exist_ok=True)

    with (APP_DATA / "nyc_degree_days.csv").open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["year", "month", "hdd", "cdd", "tavg"])
        for r in full:
            w.writerow([r["year"], r["month"], r["hdd"], r["cdd"], r["tavg"]])

    years, summer, winter = season_totals(full)
    ok = ~np.isnan(winter)
    s_fit = fit_trend(years, summer)
    w_fit = fit_trend(years[ok], winter[ok])

    with (APP_DATA / "climate_trend.csv").open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["year", "summer_cdd", "winter_hdd", "summer_trend", "winter_trend"])
        for y, s, h in zip(years, summer, winter):
            w.writerow([y, int(s), "" if np.isnan(h) else int(h),
                        round(s_fit["intercept"] + s_fit["slope"] * y, 1),
                        round(w_fit["intercept"] + w_fit["slope"] * y, 1)])

    def first_last(fit, ys):
        a = fit["intercept"] + fit["slope"] * ys[0]
        b = fit["intercept"] + fit["slope"] * ys[-1]
        return a, b, 100 * (b - a) / a

    s_a, s_b, s_pct = first_last(s_fit, years)
    w_a, w_b, w_pct = first_last(w_fit, years[ok])
    summary = [
        ("summer_cooling", s_fit, s_a, s_b, s_pct, int(years[0]), int(years[-1])),
        ("winter_heating", w_fit, w_a, w_b, w_pct, int(years[ok][0]), int(years[-1])),
    ]
    with (APP_DATA / "climate_trend_summary.csv").open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["season", "per_decade", "per_decade_low", "per_decade_high",
                    "trend_start", "trend_end", "pct_change", "first_year", "last_year", "n"])
        for name, fit, a, b, pct, y0, y1 in summary:
            w.writerow([name, round(10 * fit["slope"], 2), round(10 * fit["slope_low"], 2),
                        round(10 * fit["slope_high"], 2), round(a, 1), round(b, 1),
                        round(pct, 1), y0, y1, fit["n"]])

    if make_chart:
        chart(years, summer, s_fit, winter, w_fit)

    return {"years": (int(years[0]), int(years[-1])), "summer": s_fit, "winter": w_fit,
            "summer_pct": s_pct, "winter_pct": w_pct}


def chart(years, summer, s_fit, winter, w_fit) -> None:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    paper, ink, grid = "#f6f6f1", "#1d211f", "#dcdfd7"
    fig, axes = plt.subplots(1, 2, figsize=(10, 4), dpi=150)
    fig.patch.set_facecolor(paper)
    for ax, vals, fit, col, title in [
        (axes[0], summer, s_fit, "#b3261e", "Summer cooling points (June to September)"),
        (axes[1], winter, w_fit, "#1f5c4a", "Winter heating points (December to March)"),
    ]:
        ok = ~np.isnan(vals)
        ax.set_facecolor(paper)
        ax.scatter(years[ok], vals[ok], s=14, color=col, alpha=0.55, edgecolor="none")
        ax.plot(years, fit["intercept"] + fit["slope"] * years, color=ink, lw=2)
        ax.set_title(title, loc="left", fontsize=10.5, color=ink)
        ax.grid(axis="y", color=grid, lw=0.8)
        for side in ("top", "right"):
            ax.spines[side].set_visible(False)
        ax.tick_params(colors=ink, labelsize=9)
    fig.suptitle("78 years of Central Park weather. Dots are single years, the line is the trend.",
                 x=0.01, ha="left", fontsize=11, color=ink)
    fig.tight_layout()
    fig.savefig(REPO / "python" / "climate_trend.png", facecolor=paper)


def main(argv: list[str] | None = None) -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--offline", action="store_true", help="use the CSV already in the repo")
    ap.add_argument("--last-year", type=int, default=None, help="last year to download")
    args = ap.parse_args(argv)

    if args.offline:
        rows = read_raw()
        print(f"read {len(rows)} months from {RAW_CSV.relative_to(REPO)}")
    else:
        import datetime
        last = args.last_year or datetime.date.today().year
        print(f"downloading Central Park monthly data {FIRST_YEAR}-{last} from NOAA")
        rows = download(last)
        write_raw(rows)

    report = check(rows)
    print(f"checked {report['months']} months, {report['first']} to {report['last']}")
    if report["off"]:
        print(f"  {len(report['off'])} month(s) where degree days and temperature disagree by more"
              f" than 3.5: {report['off']}")
        print("  (if a fresh download gives the same numbers, they're NOAA's own, not a typo)")

    out = build(rows)
    s, w = out["summer"], out["winter"]
    print(f"\ntrend over {out['years'][0]}-{out['years'][1]}:")
    print(f"  summers: {10 * s['slope']:+.1f} cooling points per decade "
          f"(95% range {10 * s['slope_low']:+.1f} to {10 * s['slope_high']:+.1f}), "
          f"{out['summer_pct']:+.0f}% over the whole period")
    print(f"  winters: {10 * w['slope']:+.1f} heating points per decade "
          f"(95% range {10 * w['slope_low']:+.1f} to {10 * w['slope_high']:+.1f}), "
          f"{out['winter_pct']:+.0f}% over the whole period")
    print(f"\nwrote shiny_app/data/ (3 files) and python/climate_trend.png")


if __name__ == "__main__":
    main(sys.argv[1:])
