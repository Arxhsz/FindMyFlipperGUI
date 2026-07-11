import pytest
from httpx import AsyncClient, ASGITransport
from findmy_gateway.server import app
import findmy_gateway.server as server

@pytest.fixture
def anyio_backend():
    return "asyncio"

@pytest.mark.anyio
async def test_health():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        r = await client.get("/health")
    assert r.status_code == 200
    data = r.json()
    assert data["status"] == "ok"
    assert "version" in data

@pytest.mark.anyio
async def test_validate_keys_valid():
    content = "\n".join([
        "Private key: dGVzdHByaXZhdGVrZXliYXNlNjQ=",
        "Hashed adv key: dGVzdGhhc2hlZA==",
        "MAC: DE:AD:BE:EF:CA:FE",
        "Payload: dGVzdHBheWxvYWQ=",
    ])
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        r = await client.post("/keys/validate", json={"raw_content": content})
    assert r.status_code == 200
    data = r.json()
    assert data["valid"] is True
    assert data["errors"] == []
    # Private key must NOT appear in parsedFields
    assert "private_key_base64" not in data.get("parsedFields", {})

@pytest.mark.anyio
async def test_validate_keys_accepts_base64_aliases():
    content = "\n".join([
        "Private key (Base64): dGVzdHByaXZhdGVrZXliYXNlNjQ=",
        "Hashed adv key (Base64): dGVzdGhhc2hlZA==",
        "MAC: DE:AD:BE:EF:CA:FE",
        "Payload: dGVzdHBheWxvYWQ=",
    ])
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        r = await client.post("/keys/validate", json={"raw_content": content})
    assert r.status_code == 200
    data = r.json()
    assert data["valid"] is True
    assert data["parsedFields"]["hashed_adv_key_base64"] == "dGVzdGhhc2hlZA=="

@pytest.mark.anyio
async def test_validate_keys_missing_field():
    content = "Hashed adv key: dGVzdA==\nMAC: AA:BB:CC:DD:EE:FF\nPayload: dGVzdA=="
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        r = await client.post("/keys/validate", json={"raw_content": content})
    assert r.status_code == 200
    data = r.json()
    assert data["valid"] is False
    assert len(data["errors"]) > 0

@pytest.mark.anyio
async def test_auth_status_shape():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        r = await client.post("/auth/status")
    assert r.status_code == 200
    data = r.json()
    assert "connected" in data

@pytest.mark.anyio
async def test_auth_connect_without_credentials_returns_json_not_stub(monkeypatch):
    """auth/connect must not create fake credentials when no Apple ID/password is supplied."""
    class MemoryAuthStorage:
        def load_auth(self):
            return None

        def save_auth(self, auth):
            raise AssertionError("auth/connect without credentials must not save auth")

    monkeypatch.setattr(server, "_auth_manager", server.AuthManager(MemoryAuthStorage()))

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        r = await client.post("/auth/connect")
    assert r.status_code == 200
    data = r.json()
    assert data["ok"] is False
    assert data["requires_credentials"] is True
    assert "test@icloud.com" not in str(data)

@pytest.mark.anyio
async def test_reports_decrypted_no_auth_returns_json():
    """Without auth, reports endpoint returns ok=False with error, not 500."""
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        r = await client.post("/reports/decrypted", json={
            "hashed_adv_key_base64": "dGVzdA==",
            "private_key_base64": "dGVzdA==",
        })
    assert r.status_code == 200
    data = r.json()
    assert "ok" in data
    assert "reports" in data

@pytest.mark.anyio
async def test_reports_latest_empty():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        r = await client.get("/reports/latest", params={"hashed_adv_key_base64": "nonexistent_key_xyz"})
    assert r.status_code == 200
    data = r.json()
    assert data["ok"] is True
    assert isinstance(data["reports"], list)

@pytest.mark.anyio
async def test_start_anisette_defaults_to_no_install(monkeypatch):
    captured = {}

    class FakeResult:
        def as_dict(self):
            return {"ok": True, "installed": False}

    def fake_ensure(install_if_missing=False):
        captured["install_if_missing"] = install_if_missing
        return FakeResult()

    monkeypatch.setattr(server, "ensure_anisette_server", fake_ensure)

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        r = await client.post("/auth/start-anisette", json={})

    assert r.status_code == 200
    assert r.json()["ok"] is True
    assert captured["install_if_missing"] is False

@pytest.mark.anyio
async def test_start_anisette_accepts_install_request(monkeypatch):
    captured = {}

    class FakeResult:
        def as_dict(self):
            return {"ok": True, "installed": True}

    def fake_ensure(install_if_missing=False):
        captured["install_if_missing"] = install_if_missing
        return FakeResult()

    monkeypatch.setattr(server, "ensure_anisette_server", fake_ensure)

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        r = await client.post("/auth/start-anisette", json={"install_if_missing": True})

    assert r.status_code == 200
    assert r.json()["installed"] is True
    assert captured["install_if_missing"] is True
