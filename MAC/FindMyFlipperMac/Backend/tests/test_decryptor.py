from findmy_gateway import decryptor
from findmy_gateway.decryptor import Decryptor


def test_report_dicts_get_unique_local_ids_for_same_hashed_key(monkeypatch):
    captured_ids = []

    def fake_decrypt_report(self, encrypted_blob_b64, private_key_b64, report_id=None):
        captured_ids.append(report_id)
        return _FakeReport(report_id)

    monkeypatch.setattr(Decryptor, "decrypt_report", fake_decrypt_report)

    reports = [
        {"id": "same-hashed-key", "payload": "payload-a", "datePublished": 1},
        {"id": "same-hashed-key", "payload": "payload-b", "datePublished": 2},
    ]

    decoded = Decryptor().decrypt_report_dicts(reports, "private-key")

    assert len(decoded) == 2
    assert captured_ids[0] != captured_ids[1]


def test_report_dict_ids_are_stable_for_repeated_fetches(monkeypatch):
    captured_ids = []

    def fake_decrypt_report(self, encrypted_blob_b64, private_key_b64, report_id=None):
        captured_ids.append(report_id)
        return _FakeReport(report_id)

    monkeypatch.setattr(Decryptor, "decrypt_report", fake_decrypt_report)

    report = {"id": "same-hashed-key", "payload": "payload-a", "datePublished": 1}

    Decryptor().decrypt_report_dicts([report], "private-key")
    Decryptor().decrypt_report_dicts([report], "private-key")

    assert captured_ids[0] == captured_ids[1]


def test_fallback_report_id_uses_full_payload_not_prefix():
    left = "same-prefix-" + ("a" * 80)
    right = "same-prefix-" + ("a" * 79) + "b"

    assert decryptor._stable_report_id({"payload": left}) != decryptor._stable_report_id({"payload": right})


class _FakeReport:
    def __init__(self, report_id):
        self.report_id = report_id

    def model_dump(self, by_alias=True):
        return {
            "id": self.report_id,
            "timestamp": 1,
            "isoDateTime": "2026-01-01T00:00:00Z",
            "lat": 0,
            "lon": 0,
            "confidence": 1,
            "status": 0,
            "source": "Find My Network",
        }
