"""Minimum-cost assignment (Hungarian algorithm, O(rows² · cols))."""

from __future__ import annotations

import math

# Cost standing in for "this pairing is not allowed". Finite so the potentials stay finite.
FORBIDDEN = 1e12


def solve_assignment(cost: list[list[float]]) -> list[int]:
    """Assign every row to a distinct column minimising total cost.

    Requires rows <= columns and finite costs. Returns the column chosen for each row.
    """
    n = len(cost)
    if n == 0:
        return []
    m = len(cost[0])
    if any(len(row) != m for row in cost):
        raise ValueError("cost matrix is not rectangular")
    if n > m:
        raise ValueError("need at least as many columns as rows")
    if any(not math.isfinite(c) for row in cost for c in row):
        raise ValueError("costs must be finite; use FORBIDDEN for disallowed pairs")

    # Shortest augmenting paths with row/column potentials (1-indexed, column 0 is virtual).
    u = [0.0] * (n + 1)
    v = [0.0] * (m + 1)
    match = [0] * (m + 1)  # match[j] = row assigned to column j
    way = [0] * (m + 1)
    for i in range(1, n + 1):
        match[0] = i
        j0 = 0
        minv = [math.inf] * (m + 1)
        used = [False] * (m + 1)
        while True:
            used[j0] = True
            i0 = match[j0]
            delta = math.inf
            j1 = 0
            for j in range(1, m + 1):
                if used[j]:
                    continue
                cur = cost[i0 - 1][j - 1] - u[i0] - v[j]
                if cur < minv[j]:
                    minv[j] = cur
                    way[j] = j0
                if minv[j] < delta:
                    delta = minv[j]
                    j1 = j
            for j in range(m + 1):
                if used[j]:
                    u[match[j]] += delta
                    v[j] -= delta
                else:
                    minv[j] -= delta
            j0 = j1
            if match[j0] == 0:
                break
        while j0 != 0:
            j1 = way[j0]
            match[j0] = match[j1]
            j0 = j1

    result = [-1] * n
    for j in range(1, m + 1):
        if match[j]:
            result[match[j] - 1] = j - 1
    return result


def assignment_cost(cost: list[list[float]], columns: list[int]) -> float:
    return sum(cost[i][j] for i, j in enumerate(columns))
