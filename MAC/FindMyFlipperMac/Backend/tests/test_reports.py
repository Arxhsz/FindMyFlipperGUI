import pytest

from findmy_gateway.reports import AuthRequiredError, FINDMY_FETCH_URL, ReportFetcher
from findmy_gateway.storage import ReportStorage


class FakeAuth:
    invalidated = False

    def get_auth_pair(self):
        return ("12345", "search-token")

    def invalidate(self):
        self.invalidated = True


class FakeResponse:
    status_code = 200

    def json(self):
        return {
            "results": [
                {"id": "hash-1", "payload": "payload-1"},
                {"id": "other", "payload": "payload-2"},
            ]
        }


def test_fetch_encrypted_reports_uses_original_fetch_shape(monkeypatch, tmp_path):
    captured = {}

    def fake_headers():
        return {"X-Apple-I-MD": "md"}

    def fake_post(url, auth, headers, json, timeout):
        captured.update(
            {
                "url": url,
                "auth": auth,
                "headers": headers,
                "json": json,
                "timeout": timeout,
            }
        )
        return FakeResponse()

    monkeypatch.setattr("findmy_gateway.reports.ReportFetcher._generate_anisette_headers", staticmethod(fake_headers))
    monkeypatch.setattr("findmy_gateway.reports.requests.post", fake_post)

    fetcher = ReportFetcher(FakeAuth(), ReportStorage(data_dir=tmp_path))
    reports = fetcher.fetch_encrypted_reports("hash-1", hours=6)

    assert reports == [{"id": "hash-1", "payload": "payload-1"}]
    assert captured["url"] == FINDMY_FETCH_URL
    assert captured["auth"] == ("12345", "search-token")
    assert captured["headers"] == {"X-Apple-I-MD": "md"}
    assert captured["json"]["search"][0]["ids"] == ["hash-1"]
    assert captured["timeout"] == 30


def test_non_json_401_invalidates_auth_and_requests_reconnect(monkeypatch, tmp_path):
    class UnauthorizedResponse:
        status_code = 401

        def json(self):
            raise ValueError("HTML response")

    auth = FakeAuth()
    monkeypatch.setattr("findmy_gateway.reports.ReportFetcher._generate_anisette_headers", staticmethod(lambda: {}))
    monkeypatch.setattr("findmy_gateway.reports.requests.post", lambda *_args, **_kwargs: UnauthorizedResponse())

    fetcher = ReportFetcher(auth, ReportStorage(data_dir=tmp_path))
    with pytest.raises(AuthRequiredError, match="Reconnect Apple access"):
        fetcher.fetch_encrypted_reports("hash-1")

    assert auth.invalidated is True
