from __future__ import annotations

import base64
import json
import zipfile


def write_image(path, payload: bytes = b"fake-image") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(payload)


def build_cbz(path, image_names: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(path, "w") as archive:
        for name in image_names:
            archive.writestr(name, b"fake-image")


def encode_id(relative_path: str) -> str:
    return base64.urlsafe_b64encode(relative_path.encode("utf-8")).decode("ascii").rstrip("=")


def test_series_and_volumes_from_directory_volume(client_and_root):
    client, root = client_and_root

    for page in ["001.jpg", "002.jpg", "003.jpg"]:
        write_image(root / "One Piece" / "Vol 001" / page)

    series_resp = client.get("/api/library/series")
    assert series_resp.status_code == 200
    series_items = series_resp.json()["items"]
    assert len(series_items) == 1
    assert series_items[0]["title"] == "One Piece"

    series_id = series_items[0]["id"]
    volume_resp = client.get(f"/api/library/series/{series_id}/volumes")
    assert volume_resp.status_code == 200
    volumes = volume_resp.json()["items"]
    assert [item["title"] for item in volumes] == ["Vol 001"]


def test_pages_from_cbz_archive(client_and_root):
    client, root = client_and_root

    build_cbz(
        root / "Berserk" / "Vol_001.cbz",
        ["003.jpg", "001.jpg", "002.jpg"],
    )

    series_id = encode_id("Berserk")
    volume_resp = client.get(f"/api/library/series/{series_id}/volumes")
    assert volume_resp.status_code == 200
    volume_id = volume_resp.json()["items"][0]["id"]

    pages_resp = client.get(f"/api/library/volumes/{volume_id}/pages")
    assert pages_resp.status_code == 200
    names = [item["name"] for item in pages_resp.json()["items"]]
    assert names == ["001.jpg", "002.jpg", "003.jpg"]

    page_resp = client.get(f"/api/library/volumes/{volume_id}/pages/0")
    assert page_resp.status_code == 200
    assert page_resp.headers["content-type"].startswith("image/")


def test_series_cover_endpoint(client_and_root):
    client, root = client_and_root

    series_path = root / "One Piece"
    series_path.mkdir(parents=True, exist_ok=True)
    (series_path / "cover.jpg").write_bytes(b"cover-bytes")
    # Keep series valid with at least one volume folder with >=3 pages
    volume_path = series_path / "Vol 001"
    volume_path.mkdir(parents=True, exist_ok=True)
    for page in ["001.jpg", "002.jpg", "003.jpg"]:
        (volume_path / page).write_bytes(b"img")

    series_resp = client.get("/api/library/series")
    series_item = next(item for item in series_resp.json()["items"] if item["title"] == "One Piece")
    series_id = series_item["id"]

    cover_resp = client.get(f"/api/library/series/{series_id}/cover")
    assert cover_resp.status_code == 200
    assert cover_resp.content == b"cover-bytes"
    assert cover_resp.headers["content-type"].startswith("image/")


def test_series_arcs_endpoint_builtin_resolution(client_and_root):
    client, root = client_and_root

    for page in ["001.jpg", "002.jpg", "003.jpg"]:
        write_image(root / "Attack on Titan" / "Vol 001" / page)

    series_resp = client.get("/api/library/series")
    series_item = next(item for item in series_resp.json()["items"] if item["title"] == "Attack on Titan")
    series_id = series_item["id"]

    arcs_resp = client.get(f"/api/library/series/{series_id}/arcs")
    assert arcs_resp.status_code == 200

    items = arcs_resp.json()["items"]
    assert len(items) >= 2
    assert items[0]["id"] == "aot-fall-of-shiganshina"
    assert items[0]["name"] == "Fall of Shiganshina Arc"
    assert items[0]["start_chapter"] == 1.0
    assert items[0]["end_chapter"] == 2.0
    assert [arc["order"] for arc in items] == sorted(arc["order"] for arc in items)


def test_series_arcs_endpoint_empty_for_unknown_series(client_and_root):
    client, root = client_and_root

    for page in ["001.jpg", "002.jpg", "003.jpg"]:
        write_image(root / "My Indie Manga" / "Vol 001" / page)

    series_resp = client.get("/api/library/series")
    series_item = next(item for item in series_resp.json()["items"] if item["title"] == "My Indie Manga")
    series_id = series_item["id"]

    arcs_resp = client.get(f"/api/library/series/{series_id}/arcs")
    assert arcs_resp.status_code == 200
    assert arcs_resp.json()["items"] == []


def test_series_arcs_endpoint_prefers_cached_data(client_and_root):
    client, root = client_and_root

    for page in ["001.jpg", "002.jpg", "003.jpg"]:
        write_image(root / "One Piece" / "Vol 001" / page)

    series_resp = client.get("/api/library/series")
    series_item = next(item for item in series_resp.json()["items"] if item["title"] == "One Piece")
    series_id = series_item["id"]

    cache_root = root / "_arc_index"
    cache_root.mkdir(parents=True, exist_ok=True)
    (cache_root / f"{series_id}.json").write_text(
        json.dumps(
            {
                "series_id": series_id,
                "series_title": "One Piece",
                "source": "test-override",
                "updated_at": "2026-03-29T00:00:00Z",
                "items": [
                    {
                        "id": "op-custom-arc",
                        "name": "Custom Arc",
                        "start_chapter": 10,
                        "end_chapter": 20,
                        "order": 1,
                    }
                ],
            }
        ),
        encoding="utf-8",
    )

    arcs_resp = client.get(f"/api/library/series/{series_id}/arcs")
    assert arcs_resp.status_code == 200
    items = arcs_resp.json()["items"]
    assert len(items) == 1
    assert items[0]["id"] == "op-custom-arc"
    assert items[0]["name"] == "Custom Arc"
    assert items[0]["start_chapter"] == 10.0
    assert items[0]["end_chapter"] == 20.0


def test_series_arcs_endpoint_infers_chapter_buckets_for_unknown_series(client_and_root):
    client, root = client_and_root

    for chapter in range(1, 31):
        chapter_dir = root / "Mashle" / f"Chapter {chapter}"
        chapter_dir.mkdir(parents=True, exist_ok=True)
        for page in ["001.jpg", "002.jpg", "003.jpg"]:
            (chapter_dir / page).write_bytes(b"img")

    series_resp = client.get("/api/library/series")
    series_item = next(item for item in series_resp.json()["items"] if item["title"] == "Mashle")
    series_id = series_item["id"]

    arcs_resp = client.get(f"/api/library/series/{series_id}/arcs")
    assert arcs_resp.status_code == 200
    items = arcs_resp.json()["items"]

    assert [item["name"] for item in items] == ["Chapters 1-25", "Chapters 26-30"]
    assert items[0]["start_chapter"] == 1.0
    assert items[0]["end_chapter"] == 25.0
    assert items[1]["start_chapter"] == 26.0
    assert items[1]["end_chapter"] == 30.0


def test_arcs_sync_endpoint_creates_cache_for_series(client_and_root):
    client, root = client_and_root

    chapter_dir = root / "Frieren" / "Chapter 1"
    chapter_dir.mkdir(parents=True, exist_ok=True)
    for page in ["001.jpg", "002.jpg", "003.jpg"]:
        (chapter_dir / page).write_bytes(b"img")

    sync_resp = client.post("/api/library/arcs/sync")
    assert sync_resp.status_code == 200
    payload = sync_resp.json()
    assert payload["series_total"] >= 1
    assert payload["created"] >= 1
    assert "errors" in payload


def test_path_traversal_is_rejected(client_and_root):
    client, root = client_and_root
    _ = root

    traversal_id = encode_id("../outside")
    resp = client.get(f"/api/library/series/{traversal_id}/volumes")
    assert resp.status_code == 400
    assert resp.json()["detail"] == "Invalid path"
