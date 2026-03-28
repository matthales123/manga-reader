from __future__ import annotations

import base64
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


def test_path_traversal_is_rejected(client_and_root):
    client, root = client_and_root
    _ = root

    traversal_id = encode_id("../outside")
    resp = client.get(f"/api/library/series/{traversal_id}/volumes")
    assert resp.status_code == 400
    assert resp.json()["detail"] == "Invalid path"
