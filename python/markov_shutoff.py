"""
The shutoff timeline from my utility app, rebuilt in Python.

The website (R + Shiny) models an electric bill as being in one of four
states each month: Current, Late, Severe, or Disconnected. Disconnected
is absorbing, meaning once you're there the model doesn't let you leave.

This file does the same math with NumPy, then checks it a second,
completely different way: it simulates 100,000 made-up households month
by month and counts what happens to them. If the formula and the
simulation agree, the formula is probably right.

    python python/markov_shutoff.py            # prints the comparison, saves the chart
    python -m pytest python                    # runs the checks against the R app

Hugo Garcia Moreno
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

STATES = ("Current", "Late", "Severe", "Disconnected")

# Chance a paid-up account slips to Late in a month, by risk tier.
# These come from the tiers of the logistic model I fit in R.
TIER_BASE_SLIP = {"Low": 0.03, "Elevated": 0.12, "High": 0.28}


# What happens once an account is behind. These are stated assumptions,
# not fitted numbers (no public dataset tracks this month by month).
# s is the "stress index": monthly bill divided by monthly income.
def cure_from_late(s: float) -> float:
    return float(np.clip(0.75 - 1.6 * s, 0.05, 0.85))


def progress_from_late(s: float) -> float:
    return float(np.clip(0.08 + 1.6 * s, 0.03, 0.90))


def cure_from_severe(s: float) -> float:
    return float(np.clip(0.42 - 1.3 * s, 0.02, 0.60))


def progress_from_severe(s: float) -> float:
    return float(np.clip(0.06 + 1.1 * s, 0.02, 0.70))


def transition_matrix(tier: str, stress: float) -> np.ndarray:
    """4x4 matrix. Row = where you are this month, column = next month."""
    a = TIER_BASE_SLIP[tier]
    cL, pL = cure_from_late(stress), progress_from_late(stress)
    cS, pS = cure_from_severe(stress), progress_from_severe(stress)
    P = np.array([
        [1 - a, a,           0.0,         0.0],
        [cL,    1 - cL - pL, pL,          0.0],
        [cS,    0.0,         1 - cS - pS, pS],
        [0.0,   0.0,         0.0,         1.0],
    ])
    if np.any(P < 0) or not np.allclose(P.sum(axis=1), 1.0):
        raise ValueError(f"not a valid transition matrix for {tier=}, {stress=}")
    return P


@dataclass
class ChainResult:
    expected_months: float      # average months until shutoff, starting paid up
    trajectory: np.ndarray      # (horizon+1) x 4, chance of each state each month

    @property
    def p12(self) -> float:
        return float(self.trajectory[12, 3])


def analyze(P: np.ndarray, horizon: int = 24) -> ChainResult:
    """The exact answer, using the fundamental matrix N = (I - Q)^-1."""
    Q = P[:3, :3]                          # the three states you can still leave
    N = np.linalg.inv(np.eye(3) - Q)       # expected visits to each state
    expected = N.sum(axis=1)[0]            # row sum from Current = time to absorption

    traj = np.zeros((horizon + 1, 4))
    traj[0] = [1, 0, 0, 0]
    for m in range(horizon):
        traj[m + 1] = traj[m] @ P
    return ChainResult(float(expected), traj)


def simulate(P: np.ndarray, n: int = 100_000, horizon: int = 24,
             max_months: int = 50_000, seed: int = 7) -> dict:
    """
    The brute-force check. Start n households paid up, roll dice every
    month using the same matrix, and count. No formula involved.
    """
    rng = np.random.default_rng(seed)
    cum = P.cumsum(axis=1)
    state = np.zeros(n, dtype=np.int8)
    shut_month = np.full(n, -1)
    share_by_month = np.zeros((horizon + 1, 4))
    share_by_month[0, 0] = 1.0

    month = 0
    alive = np.arange(n)                   # households not shut off yet
    while month < max_months and alive.size:
        month += 1
        u = rng.random(alive.size)
        new = (u[:, None] > cum[state[alive]]).sum(axis=1).astype(np.int8)
        state[alive] = new
        shut_month[alive[new == 3]] = month
        alive = alive[new != 3]            # shut-off households stop rolling
        if month <= horizon:
            share_by_month[month] = np.bincount(state, minlength=4) / n

    done = shut_month > 0
    p12 = float((done & (shut_month <= 12)).mean())
    return {
        "p12": p12,
        "p12_margin": 1.96 * np.sqrt(p12 * (1 - p12) / n),   # 95% margin of error
        "expected_months": float(shut_month[done].mean()),
        "still_on_at_cap": int((~done).sum()),
        "share_by_month": share_by_month,
    }


def main() -> None:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    print("Formula vs 400,000 simulated households per row (± is the 95% margin)\n")
    print(f"{'tier':<9}{'stress':>7}{'P(shutoff in 12 mo)':>22}{'simulated':>12}"
          f"{'avg months':>12}{'simulated':>11}")
    for tier in TIER_BASE_SLIP:
        for s in (0.05, 0.12, 0.30):
            P = transition_matrix(tier, s)
            exact, sim = analyze(P), simulate(P, n=400_000)
            print(f"{tier:<9}{s:>7.2f}{exact.p12:>22.4f}"
                  f"{sim['p12']:>9.4f}±{sim['p12_margin']:.4f}"
                  f"{exact.expected_months:>12.1f}{sim['expected_months']:>11.1f}")

    # One chart: formula as lines, simulation as dots, for one household
    tier, s = "Elevated", 0.12
    P = transition_matrix(tier, s)
    exact, sim = analyze(P), simulate(P)
    months = np.arange(25)
    paper, ink = "#f6f1e4", "#1f1d1a"
    series = [("Paid up", exact.trajectory[:, 0], sim["share_by_month"][:, 0], "#2f6b4f"),
              ("Behind", exact.trajectory[:, 1] + exact.trajectory[:, 2],
               sim["share_by_month"][:, 1] + sim["share_by_month"][:, 2], "#b7791f"),
              ("Shut off", exact.trajectory[:, 3], sim["share_by_month"][:, 3], "#b3261e")]

    fig, ax = plt.subplots(figsize=(8, 4.6), dpi=150)
    fig.patch.set_facecolor(paper); ax.set_facecolor(paper)
    for name, line, dots, col in series:
        ax.plot(months, 100 * line, color=col, lw=1.6)
        ax.scatter(months[::2], 100 * dots[::2], color=col, s=46, zorder=3,
                   edgecolor=paper, linewidth=1)
        ax.text(24.4, 100 * line[-1], f"{name} {100 * line[-1]:.0f}", color=col,
                va="center", fontsize=10)
    ax.set_xlim(0, 28); ax.set_ylim(0, 100)
    ax.set_xticks([0, 6, 12, 18, 24])
    ax.set_xlabel("Months from now", color=ink)
    ax.set_ylabel("Households out of 100", color=ink)
    for side in ("top", "right"):
        ax.spines[side].set_visible(False)
    ax.tick_params(colors=ink); ax.grid(axis="y", color="#ddd5c2", lw=0.8)
    ax.set_title("Lines: the formula.  Dots: 100,000 simulated households.",
                 loc="left", color=ink, fontsize=11)
    fig.tight_layout()
    fig.savefig("python/formula_vs_simulation.png", facecolor=paper)
    print("\nsaved python/formula_vs_simulation.png")


if __name__ == "__main__":
    main()
