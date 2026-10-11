import itertools
import math
import random

import numpy as np
import pytest
from scipy.optimize import linear_sum_assignment

from app.domain.dispatch.assignment import FORBIDDEN, assignment_cost, solve_assignment


def brute_force(cost):
    n, m = len(cost), len(cost[0])
    return min(
        sum(cost[i][cols[i]] for i in range(n)) for cols in itertools.permutations(range(m), n)
    )


def test_empty():
    assert solve_assignment([]) == []


def test_single_cell():
    assert solve_assignment([[7.0]]) == [0]


def test_textbook_case():
    cost = [[4, 1, 3], [2, 0, 5], [3, 2, 2]]
    cols = solve_assignment(cost)
    assert cols == [1, 0, 2]
    assert assignment_cost(cost, cols) == 5


def test_greedy_trap():
    # Greedy takes (0,0)=1 and is then forced into 100; optimal is 2 + 3.
    cost = [[1, 2], [3, 100]]
    assert solve_assignment(cost) == [1, 0]


def test_rectangular_picks_best_columns():
    cost = [[9, 9, 1, 9], [9, 2, 1, 9]]
    cols = solve_assignment(cost)
    assert cols == [2, 1]


def test_forbidden_pairs_avoided():
    cost = [[FORBIDDEN, 5.0, 9.0], [1.0, FORBIDDEN, FORBIDDEN]]
    assert solve_assignment(cost) == [1, 0]


def test_negative_costs():
    cost = [[-5.0, 0.0], [-6.0, -4.0]]
    assert solve_assignment(cost) == [0, 1]


@pytest.mark.parametrize(
    "bad",
    [[[1.0, 2.0], [1.0]], [[1.0], [2.0]], [[math.inf, 1.0]], [[math.nan, 1.0]]],
)
def test_invalid_input(bad):
    with pytest.raises(ValueError):
        solve_assignment(bad)


def test_matches_brute_force_and_scipy_on_random_matrices():
    rng = random.Random(5)
    for _ in range(300):
        n = rng.randint(1, 5)
        m = rng.randint(n, 6)
        cost = [
            [FORBIDDEN if rng.random() < 0.15 else round(rng.uniform(-50, 500), 1)
             for _ in range(m)]
            for _ in range(n)
        ]
        cols = solve_assignment(cost)
        assert sorted(set(cols)) == sorted(cols) and len(cols) == n
        assert all(0 <= c < m for c in cols)
        total = assignment_cost(cost, cols)
        assert total == pytest.approx(brute_force(cost), rel=1e-9)
        r, c = linear_sum_assignment(np.array(cost))
        assert total == pytest.approx(float(np.array(cost)[r, c].sum()), rel=1e-9)


def test_larger_instance_matches_scipy():
    rng = random.Random(9)
    cost = [[rng.uniform(0, 1000) for _ in range(60)] for _ in range(40)]
    cols = solve_assignment(cost)
    r, c = linear_sum_assignment(np.array(cost))
    assert assignment_cost(cost, cols) == pytest.approx(float(np.array(cost)[r, c].sum()))
