"""
Checks for the weather pipeline.

    python -m pytest python
"""

import calendar

import numpy as np
import pytest

import update_weather as uw


def fake_months(years, base_temp=55.0):
    """Made-up but internally consistent months: degree days match the temperature."""
    rows = []
    for y in years:
        for m in range(1, 13):
            days = calendar.monthrange(y, m)[1]
            t = base_temp + 20 * np.sin((m - 4) / 12 * 2 * np.pi)
            hdd = max(0, round(days * (65 - t)))
            cdd = max(0, round(days * (t - 65)))
            rows.append({"year": y, "month": m, "hdd": hdd, "cdd": cdd, "tavg": round(t, 1)})
    return rows


def test_real_file_is_complete_and_consistent():
    rows = uw.read_raw()
    report = uw.check(rows)
    assert report["first"] == (1948, 1)
    assert report["months"] >= 78 * 12
    # NOAA's own published values for three early months don't line up with
    # their temperature. A second download returned the same numbers, so
    # they're left as published. Nothing else is allowed to drift.
    assert {d for d, _ in report["off"]} <= {"1950-01", "1951-02", "1951-12"}


def test_parse_handles_noaa_quotes():
    text = '"STATION","DATE","CLDD","HTDD","TAVG"\n"USW00094728","2016-07","424","0","78.7"\n'
    assert uw.parse_noaa_csv(text) == [{"year": 2016, "month": 7, "hdd": 0, "cdd": 424, "tavg": 78.7}]


def test_check_catches_missing_month():
    rows = fake_months([2000, 2001])
    del rows[5]
    with pytest.raises(ValueError):
        uw.check(rows)


def test_check_catches_duplicate_month():
    rows = fake_months([2000])
    rows.append(dict(rows[0]))
    with pytest.raises(ValueError):
        uw.check(rows)


def test_check_flags_a_typo():
    rows = fake_months([2000])
    rows[0]["hdd"] += 300          # someone fat-fingered January
    assert [d for d, _ in uw.check(rows)["off"]] == ["2000-01"]


def test_incomplete_year_is_dropped():
    rows = fake_months([2000, 2001])[:-3]
    assert {r["year"] for r in uw.complete_years(rows)} == {2000}


def test_trend_recovers_a_known_slope():
    years = np.arange(1950, 2026)
    rng = np.random.default_rng(0)
    values = 1000 + 2.0 * (years - 1950) + rng.normal(0, 30, len(years))
    fit = uw.fit_trend(years, values)
    assert fit["slope"] == pytest.approx(2.0, abs=0.4)
    assert fit["slope_low"] < 2.0 < fit["slope_high"]


def test_flat_data_has_no_trend():
    years = np.arange(1950, 2026)
    fit = uw.fit_trend(years, np.full(len(years), 500.0) + (years % 2))
    assert fit["slope_low"] <= 0 <= fit["slope_high"]


def test_t_quantile_is_close_to_textbook():
    assert uw.t_quantile(0.975, 76) == pytest.approx(1.9917, abs=0.002)
    assert uw.t_quantile(0.975, 30) == pytest.approx(2.0423, abs=0.003)


def test_winter_uses_december_from_the_year_before():
    rows = fake_months([2000, 2001])
    years, summer, winter = uw.season_totals(rows)
    assert np.isnan(winter[0])
    by = {(r["year"], r["month"]): r for r in rows}
    expected = by[(2000, 12)]["hdd"] + sum(by[(2001, m)]["hdd"] for m in (1, 2, 3))
    assert winter[1] == expected
    assert summer[0] == sum(by[(2000, m)]["cdd"] for m in (6, 7, 8, 9))
