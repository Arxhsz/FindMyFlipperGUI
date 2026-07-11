"""
Simple JSON-based local storage for FindMyFlipper Gateway.

All data is stored under ``~/.findmyflipper/``.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any, Optional


def _default_data_dir() -> Path:
    """Return the default data directory, creating it if necessary."""
    data_dir = Path.home() / ".findmyflipper"
    data_dir.mkdir(parents=True, exist_ok=True)
    return data_dir


class ReportStorage:
    """Persist and retrieve encrypted/decrypted report blobs per key."""

    def __init__(self, data_dir: Optional[Path] = None) -> None:
        self._data_dir: Path = data_dir if data_dir is not None else _default_data_dir()
        self._data_dir.mkdir(parents=True, exist_ok=True)

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def save_reports(self, hashed_adv_key: str, reports: list[dict]) -> None:
        """
        Persist *reports* for the given *hashed_adv_key*.

        Overwrites any previously stored reports for that key.
        """
        path = self._reports_path(hashed_adv_key)
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(reports, fh, ensure_ascii=False)

    def load_reports(self, hashed_adv_key: str) -> list[dict]:
        """
        Load reports for *hashed_adv_key*.

        Returns an empty list if no reports are stored yet.
        """
        path = self._reports_path(hashed_adv_key)
        if not path.exists():
            return []
        try:
            with open(path, "r", encoding="utf-8") as fh:
                data = json.load(fh)
            if not isinstance(data, list):
                return []
            return data
        except (json.JSONDecodeError, OSError):
            return []

    def clear_reports(self, hashed_adv_key: str) -> None:
        """Delete stored reports for *hashed_adv_key*."""
        path = self._reports_path(hashed_adv_key)
        if path.exists():
            path.unlink()

    # ------------------------------------------------------------------
    # Private helpers
    # ------------------------------------------------------------------

    def _reports_path(self, hashed_adv_key: str) -> Path:
        """
        Derive a safe filename from *hashed_adv_key*.

        Base64 keys may contain ``/`` and ``+`` which are unsafe in file
        names, so we replace them with ``_`` and ``-`` respectively.
        """
        safe_key = hashed_adv_key.replace("/", "_").replace("+", "-").replace("=", "")
        return self._data_dir / f"reports_{safe_key}.json"


class AuthStorage:
    """Persist and retrieve Apple Find My authentication data."""

    _AUTH_FILE = "auth.json"

    def __init__(self, data_dir: Optional[Path] = None) -> None:
        self._data_dir: Path = data_dir if data_dir is not None else _default_data_dir()
        self._data_dir.mkdir(parents=True, exist_ok=True)

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def save_auth(self, auth_data: dict) -> None:
        """Persist *auth_data* to disk."""
        path = self._auth_path()
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(auth_data, fh, ensure_ascii=False)
        try:
            os.chmod(path, 0o600)
        except OSError:
            pass

    def load_auth(self) -> Optional[dict]:
        """
        Load stored auth data.

        Returns *None* if no auth data has been saved yet.
        """
        path = self._auth_path()
        if not path.exists():
            return None
        try:
            with open(path, "r", encoding="utf-8") as fh:
                data = json.load(fh)
            if not isinstance(data, dict):
                return None
            return data
        except (json.JSONDecodeError, OSError):
            return None

    def clear_auth(self) -> None:
        """Delete stored auth data."""
        path = self._auth_path()
        if path.exists():
            path.unlink()

    # ------------------------------------------------------------------
    # Private helpers
    # ------------------------------------------------------------------

    def _auth_path(self) -> Path:
        return self._data_dir / self._AUTH_FILE
