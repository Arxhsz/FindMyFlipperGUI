from types import SimpleNamespace

import pytest

from findmy_gateway import platform_bridge


def test_flipper_port_filter_uses_usb_identity(monkeypatch):
    ports = [
        SimpleNamespace(
            device="COM4",
            description="Bluetooth modem",
            manufacturer="Other",
            product="",
            interface="",
            vid=1,
            pid=2,
        ),
        SimpleNamespace(
            device="COM16",
            description="Flipper Zero",
            manufacturer="Flipper Devices",
            product="Flipper Zero",
            interface="CDC",
            vid=0x0483,
            pid=0x5740,
        ),
    ]
    monkeypatch.setattr(platform_bridge.list_ports, "comports", lambda: ports)

    assert platform_bridge.find_flipper_port() == "COM16"


@pytest.mark.parametrize(
    "filename",
    ("../secret.keys", "nested/key.keys", "identity.txt", "bad key.keys"),
)
def test_key_filename_rejects_path_traversal_and_wrong_extensions(filename):
    with pytest.raises(ValueError):
        platform_bridge._safe_key_filename(filename)


def test_hash_comparison_normalizes_valid_base64():
    assert platform_bridge._normalized_hash(" dGVz\ndA== ") == "dGVzdA=="
