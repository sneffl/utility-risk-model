"""
Checks that the Python model gives the same answers as the R code running
on the website, and that the simulation backs up the formula.

    python -m pytest python
"""

import json
from pathlib import Path

import numpy as np
import pytest

from markov_shutoff import analyze, simulate, transition_matrix

REF = json.loads((Path(__file__).parent / "r_reference.json").read_text())


@pytest.mark.parametrize("case", REF, ids=lambda c: f"{c['tier']}-{c['stress']}")
def test_matches_r_app_exactly(case):
    P = transition_matrix(case["tier"], case["stress"])
    np.testing.assert_allclose(P, np.array(case["P"]), atol=1e-12)

    result = analyze(P, horizon=24)
    assert result.expected_months == pytest.approx(case["expected_months"], abs=1e-9)
    np.testing.assert_allclose(result.trajectory, np.array(case["trajectory"]), atol=1e-12)


def test_rows_sum_to_one_everywhere():
    for tier in ("Low", "Elevated", "High"):
        for s in np.linspace(0, 1, 101):
            P = transition_matrix(tier, s)
            assert np.allclose(P.sum(axis=1), 1)
            assert (P >= 0).all()


def test_riskier_tier_means_more_shutoffs():
    for s in (0.05, 0.12, 0.30):
        p = [analyze(transition_matrix(t, s)).p12 for t in ("Low", "Elevated", "High")]
        assert p[0] < p[1] < p[2]


def test_bigger_bill_share_means_more_shutoffs():
    p = [analyze(transition_matrix("Elevated", s)).p12 for s in (0.02, 0.08, 0.2, 0.5)]
    assert p == sorted(p)


@pytest.mark.parametrize("tier,stress", [("Elevated", 0.12), ("High", 0.30)])
def test_simulation_agrees_with_formula(tier, stress):
    P = transition_matrix(tier, stress)
    exact, sim = analyze(P), simulate(P, n=100_000)
    # within the simulation's own 95% margin, padded a little
    assert abs(sim["p12"] - exact.p12) < 1.5 * sim["p12_margin"] + 1e-3
    assert sim["expected_months"] == pytest.approx(exact.expected_months, rel=0.03)
