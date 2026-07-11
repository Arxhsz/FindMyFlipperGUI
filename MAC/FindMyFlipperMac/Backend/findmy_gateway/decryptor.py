"""Original-compatible FindMyFlipper report decryption."""
from __future__ import annotations

import base64
import datetime as dt
import hashlib
import logging
import struct
import uuid
from typing import Optional

from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

from .models import LocationReportModel

logger = logging.getLogger(__name__)

APPLE_EPOCH_OFFSET = 978_307_200


class Decryptor:
    """Decrypt Apple Find My reports using MatthewKuKanich-compatible logic."""

    def decrypt_report(
        self,
        encrypted_blob_b64: str,
        private_key_b64: str,
        report_id: Optional[str] = None,
    ) -> LocationReportModel:
        data = base64.b64decode(encrypted_blob_b64)
        if len(data) < 88:
            raise ValueError(f"Encrypted report payload too short: {len(data)} bytes")

        private_key_int = int.from_bytes(base64.b64decode(private_key_b64), byteorder="big")
        timestamp = int.from_bytes(data[0:4], "big") + APPLE_EPOCH_OFFSET
        decrypted = self._decrypt_payload(data, private_key_int)
        lat, lon, confidence, status = self._decode_tag(decrypted)
        iso_dt = dt.datetime.fromtimestamp(timestamp, tz=dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

        stable_id = report_id or str(uuid.uuid5(uuid.NAMESPACE_DNS, encrypted_blob_b64[:48]))
        return LocationReportModel(
            id=stable_id,
            timestamp=float(timestamp),
            iso_date_time=iso_dt,
            lat=lat,
            lon=lon,
            confidence=confidence,
            status=status,
        )

    def decrypt_reports(
        self,
        report_blobs: list[str],
        private_key_b64: str,
    ) -> list[LocationReportModel]:
        results: list[LocationReportModel] = []
        for i, blob in enumerate(report_blobs):
            try:
                results.append(self.decrypt_report(blob, private_key_b64))
            except Exception as exc:
                logger.warning("Failed to decrypt report blob %d/%d: %s", i + 1, len(report_blobs), exc)
        return results

    def decrypt_report_dicts(
        self,
        reports: list[dict],
        private_key_b64: str,
    ) -> list[LocationReportModel]:
        results: list[LocationReportModel] = []
        for i, report in enumerate(reports):
            try:
                payload = report["payload"]
                report_id = str(report.get("id") or uuid.uuid5(uuid.NAMESPACE_DNS, payload[:48]))
                results.append(self.decrypt_report(payload, private_key_b64, report_id=report_id))
            except Exception as exc:
                logger.warning("Failed to decrypt report %d/%d: %s", i + 1, len(reports), exc)
        return results

    @staticmethod
    def _decrypt_payload(data: bytes, private_key_int: int) -> bytes:
        offset_adjustment = len(data) - 88
        eph_start = 5 + offset_adjustment
        eph_end = 62 + offset_adjustment
        enc_start = 62 + offset_adjustment
        enc_end = 72 + offset_adjustment
        tag_start = 72 + offset_adjustment

        eph_key = ec.EllipticCurvePublicKey.from_encoded_point(
            ec.SECP224R1(),
            data[eph_start:eph_end],
        )
        shared_key = ec.derive_private_key(
            private_key_int,
            ec.SECP224R1(),
            default_backend(),
        ).exchange(ec.ECDH(), eph_key)

        symmetric_key = hashlib.sha256(
            shared_key + b"\x00\x00\x00\x01" + data[eph_start:eph_end]
        ).digest()
        decryption_key = symmetric_key[:16]
        iv = symmetric_key[16:]
        auth_tag = data[tag_start:]
        encrypted_data = data[enc_start:enc_end]

        decryptor = Cipher(
            algorithms.AES(decryption_key),
            modes.GCM(iv, auth_tag),
            default_backend(),
        ).decryptor()
        return decryptor.update(encrypted_data) + decryptor.finalize()

    @staticmethod
    def _decode_tag(data: bytes) -> tuple[float, float, int, int]:
        if len(data) < 10:
            raise ValueError(f"Decrypted report payload too short: {len(data)} bytes")
        latitude = struct.unpack(">i", data[0:4])[0] / 10_000_000.0
        longitude = struct.unpack(">i", data[4:8])[0] / 10_000_000.0
        confidence = int.from_bytes(data[8:9], "big")
        status = int.from_bytes(data[9:10], "big")
        return latitude, longitude, confidence, status
