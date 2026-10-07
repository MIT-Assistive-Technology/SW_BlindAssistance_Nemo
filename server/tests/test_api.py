from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health():
    r = client.get("/v1/health")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"


def test_resolve_returns_contract_shape():
    r = client.post("/v1/resolve", json={"address": "77 Massachusetts Ave, Cambridge, MA"})
    assert r.status_code == 200
    body = r.json()
    assert body["candidates"], "expected at least one door"
    confidences = [c["confidence"] for c in body["candidates"]]
    assert confidences == sorted(confidences, reverse=True), "candidates must be best first"


def test_resolve_needs_a_destination():
    assert client.post("/v1/resolve", json={}).status_code == 422


def test_unknown_destination_is_404():
    assert client.get("/v1/destinations/nope").status_code == 404
