from __future__ import annotations

from pathlib import Path

import pytest
from fastapi.testclient import TestClient

import app.main as main_module
from app.library import MangaLibrary


@pytest.fixture
def client_and_root(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setattr(main_module, "library", MangaLibrary(tmp_path))
    with TestClient(main_module.app) as client:
        yield client, tmp_path
