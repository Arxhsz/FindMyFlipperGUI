import types

from findmy_gateway.auth import VENDOR_CORES_CANDIDATES, AuthManager


def test_auth_vendor_core_is_self_contained():
    candidates = list(VENDOR_CORES_CANDIDATES)

    assert len(candidates) == 1
    assert "FindMyFlipperRepo" not in str(candidates[0])
    assert candidates[0].name == "cores"
    assert (candidates[0] / "pypush_gsa_icloud.py").exists()


def test_auth_connect_missing_credentials_does_not_need_external_repo(tmp_path):
    manager = AuthManager(storage=type("Storage", (), {"load_auth": lambda self: None})())

    response = manager.connect()

    assert response["ok"] is False
    assert response["requires_credentials"] is True


def test_auth_connect_waits_for_second_factor_code(monkeypatch):
    class MemoryAuthStorage:
        auth = None

        def load_auth(self):
            return self.auth

        def save_auth(self, auth):
            self.auth = auth

    module = types.SimpleNamespace()
    module.getpass = lambda prompt="": ""
    module.trusted_second_factor = lambda dsid, idms_token: None
    module.sms_second_factor = lambda dsid, idms_token: None

    calls = []
    triggered = []
    validated = []

    def fake_login(username, password, second_factor="sms"):
        calls.append((username, password, second_factor))
        module.trusted_second_factor("123", "token")
        return {
            "dsid": "123",
            "delegates": {
                "com.apple.mobileme": {
                    "service-data": {
                        "tokens": {
                            "searchPartyToken": "search-token",
                        }
                    }
                }
            },
        }

    module.icloud_login_mobileme = fake_login

    monkeypatch.setattr(AuthManager, "_load_pypush_module", staticmethod(lambda path: module))
    monkeypatch.setattr(
        AuthManager,
        "_trigger_trusted_second_factor",
        lambda self, module_arg, dsid, idms_token: triggered.append((dsid, idms_token)),
    )
    monkeypatch.setattr(
        AuthManager,
        "_validate_trusted_second_factor",
        lambda self, module_arg, dsid, idms_token, code: validated.append((dsid, idms_token, code)),
    )

    manager = AuthManager(storage=MemoryAuthStorage())

    first = manager.connect(
        username="user@example.com",
        password="secret-password",
        second_factor="trusted_device",
    )
    assert first["ok"] is False
    assert first["requires_2fa"] is True
    assert triggered == [("123", "token")]

    second = manager.connect(code="123456")
    assert second["ok"] is True
    assert second["account_identifier"] == "user@example.com"
    assert validated == [("123", "token", "123456")]
    assert calls == [
        ("user@example.com", "secret-password", "trusted_device"),
        ("user@example.com", "secret-password", "trusted_device"),
    ]
    assert manager._pending_second_factor is None
