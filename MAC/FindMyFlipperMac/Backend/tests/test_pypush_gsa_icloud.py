import json

import pytest

from findmy_gateway.vendor.cores import pypush_gsa_icloud as gsa


def test_anisette_server_headers_keep_server_device_identity(monkeypatch):
    server_headers = {
        "X-Apple-I-MD": "otp",
        "X-Apple-I-MD-M": "machine-id",
        "X-Apple-I-MD-RINFO": "server-rinfo",
        "X-Apple-I-MD-LU": "server-local-user",
        "X-Mme-Device-Id": "server-device-id",
        "X-Apple-I-SRL-NO": "server-serial",
        "X-Apple-I-Client-Time": "2026-09-12T01:02:03Z",
        "X-Apple-I-TimeZone": "Asia/Chita",
        "X-Apple-Locale": "en_US",
    }
    response = type("Response", (), {"text": json.dumps(server_headers)})()

    monkeypatch.setattr(gsa.requests, "get", lambda *args, **kwargs: response)
    monkeypatch.setattr(gsa.locale, "getdefaultlocale", lambda: ("ru_RU", "UTF-8"))
    monkeypatch.setattr(
        gsa,
        "generate_meta_headers",
        lambda *args, **kwargs: pytest.fail("server headers must not be mixed with local UUIDs"),
    )

    assert gsa.generate_anisette_headers() == {
        **server_headers,
        "loc": "ru_RU",
    }


def test_gsa_authenticate_keeps_second_factor_on_retry(monkeypatch):
    class FakeUser:
        def __init__(self, *args, **kwargs):
            self.p = None

        def start_authentication(self):
            return None, b"A"

        def process_challenge(self, salt, challenge):
            return b"M1"

        def verify_session(self, server_proof):
            return None

        def authenticated(self):
            return True

    complete_requests = 0

    def fake_authenticated_request(parameters):
        nonlocal complete_requests
        if parameters["o"] == "init":
            return {"sp": "s2k", "s": b"salt", "i": 1, "B": b"challenge", "c": "context"}

        complete_requests += 1
        status = {"au": "trustedDeviceSecondaryAuth"} if complete_requests == 1 else {}
        return {"M2": b"proof", "spd": b"encrypted", "Status": status}

    trusted_calls = []
    sms_calls = []
    monkeypatch.setattr(gsa.srp, "User", FakeUser)
    monkeypatch.setattr(gsa, "gsa_authenticated_request", fake_authenticated_request)
    monkeypatch.setattr(gsa, "encrypt_password", lambda *args, **kwargs: b"password")
    monkeypatch.setattr(gsa, "decrypt_cbc", lambda *args, **kwargs: b"plist")
    monkeypatch.setattr(
        gsa.plist,
        "loads",
        lambda data: {"adsid": "123", "GsIdmsToken": "token"},
    )
    monkeypatch.setattr(gsa, "trusted_second_factor", lambda *args: trusted_calls.append(args))
    monkeypatch.setattr(gsa, "sms_second_factor", lambda *args: sms_calls.append(args))

    result = gsa.gsa_authenticate("user@example.com", "password", "trusted_device")

    assert result == {"adsid": "123", "GsIdmsToken": "token"}
    assert trusted_calls == [("123", "token")]
    assert sms_calls == []
    assert complete_requests == 2


def test_gsa_request_reports_non_plist_response_details(monkeypatch):
    response = type(
        "Response",
        (),
        {
            "status_code": 503,
            "headers": {"Content-Type": "text/html; charset=utf-8"},
            "content": b"<html>" + (b"x" * 1100) + b"not-in-preview",
        },
    )()
    monkeypatch.setattr(gsa.requests, "post", lambda *args, **kwargs: response)
    monkeypatch.setattr(gsa, "generate_cpd", lambda: {})
    monkeypatch.setattr(gsa.time, "sleep", lambda delay: None)

    with pytest.raises(RuntimeError) as exc_info:
        gsa.gsa_authenticated_request({"o": "init"})

    message = str(exc_info.value)
    assert "HTTP 503" in message
    assert "Content-Type: text/html; charset=utf-8" in message
    assert "first 1000 bytes" in message
    assert "<html>" in message
    assert "not-in-preview" not in message


def test_gsa_request_uses_unblocked_akd_client_identity(monkeypatch):
    captured_headers = []
    response = type(
        "Response",
        (),
        {
            "status_code": 200,
            "headers": {"Content-Type": "text/x-xml-plist"},
            "content": gsa.plist.dumps({"Response": {"ok": True}}),
        },
    )()

    def fake_post(*args, **kwargs):
        captured_headers.append(kwargs["headers"])
        return response

    monkeypatch.setattr(gsa.requests, "post", fake_post)
    monkeypatch.setattr(gsa, "generate_cpd", lambda: {})

    assert gsa.gsa_authenticated_request({"o": "init"}) == {"ok": True}
    assert captured_headers[0]["X-MMe-Client-Info"] == gsa.GSA_CLIENT_INFO
    assert "com.apple.akd/1.0" in gsa.GSA_CLIENT_INFO
    assert "com.apple.dt.Xcode" not in gsa.GSA_CLIENT_INFO


def test_gsa_request_retries_transient_503_on_fresh_requests(monkeypatch):
    responses = [
        type(
            "Response",
            (),
            {
                "status_code": 503,
                "headers": {"Content-Type": "text/html"},
                "content": b"<html>temporary</html>",
            },
        )(),
        type(
            "Response",
            (),
            {
                "status_code": 200,
                "headers": {"Content-Type": "text/x-xml-plist"},
                "content": gsa.plist.dumps({"Response": {"ok": True}}),
            },
        )(),
    ]
    sleeps = []
    monkeypatch.setattr(gsa.requests, "post", lambda *args, **kwargs: responses.pop(0))
    monkeypatch.setattr(gsa, "generate_cpd", lambda: {})
    monkeypatch.setattr(gsa.time, "sleep", sleeps.append)

    assert gsa.gsa_authenticated_request({"o": "init"}) == {"ok": True}
    assert responses == []
    assert sleeps == [0.5]
