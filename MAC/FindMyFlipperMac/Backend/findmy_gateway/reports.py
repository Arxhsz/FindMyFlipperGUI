"""Apple Find My report fetching and decryption."""
from __future__ import annotations

import datetime as dt
import importlib
import logging
import sys
from pathlib import Path
from typing import Optional

import requests

from .auth import AuthManager, VENDOR_CORES_CANDIDATES
from .decryptor import Decryptor
from .storage import ReportStorage

logger = logging.getLogger(__name__)

FINDMY_FETCH_URL = "https://gateway.icloud.com/acsnservice/fetch"


class AuthRequiredError(Exception):
    pass


class ReportFetcher:
    def __init__(self, auth_manager: AuthManager, storage: ReportStorage):
        self._auth = auth_manager
        self._storage = storage
        self._decryptor = Decryptor()
        self.last_found_keys: list[str] = []
        self.last_missing_keys: list[str] = []

    def fetch_encrypted_reports(self, hashed_adv_key_b64: str, hours: int = 24) -> list[dict]:
        auth_pair = self._auth.get_auth_pair()
        if not auth_pair:
            raise AuthRequiredError("Apple authentication required. Connect your Apple account first.")

        headers = self._generate_anisette_headers()
        now = int(dt.datetime.now(tz=dt.timezone.utc).timestamp())
        start = now - (60 * 60 * max(1, hours))
        body = {
            "search": [
                {
                    "startDate": start * 1000,
                    "endDate": now * 1000,
                    "ids": [hashed_adv_key_b64],
                }
            ]
        }

        response = requests.post(
            FINDMY_FETCH_URL,
            auth=auth_pair,
            headers=headers,
            json=body,
            timeout=30,
        )

        # Apple may return an HTML or empty body when a cached searchParty token
        # expires. Classify authentication before attempting JSON decoding so a
        # 401 becomes an actionable reconnect state instead of a parsing error.
        if response.status_code in (401, 403):
            self._auth.invalidate()
            raise AuthRequiredError("Apple authentication expired or was rejected. Reconnect Apple access.")

        try:
            data = response.json()
        except ValueError as exc:
            raise RuntimeError(f"Apple reports endpoint returned non-JSON response ({response.status_code}).") from exc

        if response.status_code >= 400:
            raise RuntimeError(f"Apple reports endpoint returned HTTP {response.status_code}: {data}")

        results = data.get("results", [])
        if not isinstance(results, list):
            raise RuntimeError("Apple reports response did not include a results list.")
        return [report for report in results if report.get("id") == hashed_adv_key_b64 and report.get("payload")]

    def fetch_and_decrypt(self, hashed_adv_key_b64: str, private_key_b64: str, hours: int = 24) -> list[dict]:
        encrypted_reports = self.fetch_encrypted_reports(hashed_adv_key_b64, hours)
        self.last_found_keys = sorted({r["id"] for r in encrypted_reports if r.get("id")})
        self.last_missing_keys = [] if hashed_adv_key_b64 in self.last_found_keys else [hashed_adv_key_b64]

        reports = self._decryptor.decrypt_report_dicts(encrypted_reports, private_key_b64)
        result = [r.model_dump(by_alias=True) for r in reports]
        result.sort(key=lambda r: r["timestamp"], reverse=True)

        if result:
            self._storage.save_reports(hashed_adv_key_b64, result)
        return result

    @staticmethod
    def _generate_anisette_headers() -> dict:
        module = _load_pypush_module()
        try:
            return module.generate_anisette_headers()
        except requests.RequestException as exc:
            raise RuntimeError("Local anisette server is not reachable. Start Apple access setup again.") from exc


def _load_pypush_module():
    for cores_path in VENDOR_CORES_CANDIDATES:
        if cores_path.exists():
            parent = str(cores_path.parent)
            if parent not in sys.path:
                sys.path.insert(0, parent)
            return importlib.import_module("cores.pypush_gsa_icloud")
    raise RuntimeError("Bundled FindMyFlipper auth core is missing from Backend/findmy_gateway/vendor/cores.")
