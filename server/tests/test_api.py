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
    assert all(c <= 0.95 for c in confidences), "nothing is certain before the camera confirms"


def test_errors_use_the_contract_envelope():
    r = client.post("/v1/resolve", json={})
    assert r.status_code == 422
    assert r.json()["error"]["code"] == "VALIDATION"

    r = client.post("/v1/resolve", json={"address": 5})
    assert r.status_code == 422
    assert r.json()["error"]["code"] == "VALIDATION"


def test_unknown_route_is_404_envelope():
    r = client.get("/v1/nope")
    assert r.status_code == 404
    assert r.json()["error"]["code"] == "NOT_FOUND"
