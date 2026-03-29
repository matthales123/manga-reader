from __future__ import annotations

from pathlib import Path

import pytest
from fastapi.testclient import TestClient

import app.main as main_module
from app.arcs import ArcCatalog
from app.library import MangaLibrary


@pytest.fixture
def client_and_root(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    test_library = MangaLibrary(tmp_path)
    test_arc_catalog = ArcCatalog(library=test_library, cache_root=tmp_path / "_arc_index")
    monkeypatch.setattr(main_module, "library", test_library)
    monkeypatch.setattr(main_module, "arc_catalog", test_arc_catalog)
    with TestClient(main_module.app) as client:
        yield client, tmp_path
