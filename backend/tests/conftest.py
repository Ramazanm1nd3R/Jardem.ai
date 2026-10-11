from __future__ import annotations

from pathlib import Path

import pytest

from app.domain.graph import RoadGraph


@pytest.fixture(scope="session")
def almaty() -> RoadGraph:
    path = Path(__file__).resolve().parents[1] / "app" / "data" / "almaty_graph.json.gz"
    return RoadGraph.from_file(path)
