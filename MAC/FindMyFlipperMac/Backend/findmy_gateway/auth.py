"""Apple Find My authentication manager.

This module wraps the original FindMyFlipper-compatible
``cores.pypush_gsa_icloud`` flow without using terminal prompts. The backend
stores only the returned DSID/searchParty token pair, never the Apple ID
password supplied for sign-in.
"""
from __future__ import annotations

import base64
import builtins
import importlib
import logging
import sys
from contextlib import contextmanager
from pathlib import Path
from types import ModuleType
from typing import Iterator, Optional

from .storage import AuthStorage

logger = logging.getLogger(__name__)

PACKAGE_ROOT = Path(__file__).resolve().parents[1]
VENDOR_CORES_CANDIDATES = (
    Path(__file__).parent / "vendor" / "cores",
)
VENDOR_MISSING_ERROR = (
    "Bundled FindMyFlipper auth core is missing from Backend/findmy_gateway/vendor/cores."
)


class TwoFactorCodeRequired(RuntimeError):
    """Raised when the original auth flow prompts for a 2FA code."""


def _vendor_cores_path() -> Optional[Path]:
    return next((path for path in VENDOR_CORES_CANDIDATES if path.exists()), None)


class AuthManager:
    def __init__(self, storage: AuthStorage):
        self._storage = storage
        self._pending_second_factor: Optional[dict[str, str]] = None

    def get_status(self) -> dict:
        auth = self._storage.load_auth()
        if self._is_valid_auth(auth):
            return {
                "connected": True,
                "account_identifier": auth.get("account_identifier"),
                "error": None,
            }
        return {"connected": False, "account_identifier": None, "error": None}

    def connect(
        self,
        username: Optional[str] = None,
        password: Optional[str] = None,
        second_factor: str = "trusted_device",
        code: Optional[str] = None,
    ) -> dict:
        existing = self._storage.load_auth()
        if self._is_valid_auth(existing) and not username and not password:
            return {"ok": True, "account_identifier": existing.get("account_identifier")}

        if code and (not username or not password) and self._pending_second_factor:
            username = self._pending_second_factor["username"]
            password = self._pending_second_factor["password"]
            second_factor = self._pending_second_factor.get("second_factor", second_factor)

        if not username or not password:
            return {
                "ok": False,
                "requires_credentials": True,
                "error": (
                    "Apple ID and password are required to connect Apple access."
                    if not code else
                    "The previous Apple sign-in expired. Enter your Apple ID and password again."
                ),
            }

        vendor_cores_path = _vendor_cores_path()
        if vendor_cores_path is None:
            return {"ok": False, "error": VENDOR_MISSING_ERROR}

        try:
            module = self._load_pypush_module(vendor_cores_path)
            with self._patched_auth_flow(
                module,
                username=username,
                password=password,
                second_factor=second_factor,
                code=code,
            ):
                mobileme = module.icloud_login_mobileme(
                    username=username,
                    password=password,
                    second_factor=second_factor,
                )

            auth_data = self._auth_data_from_mobileme(username, mobileme)
            self._storage.save_auth(auth_data)
            self._pending_second_factor = None
            return {
                "ok": True,
                "account_identifier": auth_data["account_identifier"],
            }
        except TwoFactorCodeRequired:
            return {
                "ok": False,
                "requires_2fa": True,
                "error": "Apple sent a two-factor code. Enter that code here to finish sign-in.",
            }
        except Exception as exc:
            logger.error("Auth connect failed: %s", exc)
            if code:
                self._pending_second_factor = None
            return {"ok": False, "error": self._friendly_error(exc)}

    def refresh(self) -> dict:
        if _vendor_cores_path() is None:
            return {"ok": False, "error": VENDOR_MISSING_ERROR}
        auth = self._storage.load_auth()
        if not self._is_valid_auth(auth):
            return {"ok": False, "error": "Not authenticated. Connect first."}
        return {"ok": True}

    def get_auth_pair(self) -> Optional[tuple[str, str]]:
        auth = self._storage.load_auth()
        if not self._is_valid_auth(auth):
            return None
        return str(auth["dsid"]), str(auth["searchPartyToken"])

    def get_auth_token(self) -> Optional[str]:
        pair = self.get_auth_pair()
        return pair[1] if pair else None

    def invalidate(self) -> None:
        """Discard an Apple token pair after the reports service rejects it."""
        self._storage.clear_auth()
        self._pending_second_factor = None

    @staticmethod
    def _is_valid_auth(auth: Optional[dict]) -> bool:
        return bool(
            isinstance(auth, dict)
            and auth.get("account_identifier")
            and auth.get("dsid")
            and auth.get("searchPartyToken")
        )

    @staticmethod
    def _load_pypush_module(vendor_cores_path: Path) -> ModuleType:
        vendor_parent = str(vendor_cores_path.parent)
        if vendor_parent not in sys.path:
            sys.path.insert(0, vendor_parent)
        return importlib.import_module("cores.pypush_gsa_icloud")

    @staticmethod
    @contextmanager
    def _patched_prompts(module: ModuleType, password: str, code: Optional[str]) -> Iterator[None]:
        original_input = builtins.input
        original_getpass = getattr(module, "getpass", None)

        def code_or_raise(_prompt: str = "") -> str:
            if code:
                return code
            raise TwoFactorCodeRequired()

        def getpass_replacement(prompt: str = "") -> str:
            lowered = prompt.lower()
            if "2fa" in lowered or "code" in lowered:
                return code_or_raise(prompt)
            return password

        builtins.input = code_or_raise
        module.getpass = getpass_replacement
        try:
            yield
        finally:
            builtins.input = original_input
            if original_getpass is not None:
                module.getpass = original_getpass

    @contextmanager
    def _patched_auth_flow(
        self,
        module: ModuleType,
        username: str,
        password: str,
        second_factor: str,
        code: Optional[str],
    ) -> Iterator[None]:
        original_trusted = getattr(module, "trusted_second_factor", None)
        original_sms = getattr(module, "sms_second_factor", None)

        def mark_pending_and_raise() -> None:
            self._pending_second_factor = {
                "username": username,
                "password": password,
                "second_factor": second_factor,
            }
            raise TwoFactorCodeRequired()

        def trusted_handler(dsid: str, idms_token: str) -> None:
            if code:
                self._validate_trusted_second_factor(module, dsid, idms_token, code)
                return
            self._trigger_trusted_second_factor(module, dsid, idms_token)
            mark_pending_and_raise()

        def sms_handler(dsid: str, idms_token: str) -> None:
            if code:
                self._validate_sms_second_factor(module, dsid, idms_token, code)
                return
            self._trigger_sms_second_factor(module, dsid, idms_token)
            mark_pending_and_raise()

        module.trusted_second_factor = trusted_handler
        module.sms_second_factor = sms_handler
        try:
            with self._patched_prompts(module, password=password, code=code):
                yield
        finally:
            if original_trusted is not None:
                module.trusted_second_factor = original_trusted
            if original_sms is not None:
                module.sms_second_factor = original_sms

    @staticmethod
    def _second_factor_headers(module: ModuleType, dsid: str, idms_token: str) -> dict:
        identity_token = base64.b64encode((str(dsid) + ":" + str(idms_token)).encode()).decode()
        headers = {
            "Content-Type": "text/x-xml-plist",
            "User-Agent": "Xcode",
            "Accept": "text/x-xml-plist",
            "Accept-Language": "en-us",
            "X-Apple-Identity-Token": identity_token,
            "X-Apple-App-Info": "com.apple.gs.xcode.auth",
            "X-Xcode-Version": "11.2 (11B41)",
            "X-Mme-Client-Info": "<MacBookPro18,3> <Mac OS X;13.4.1;22F8> <com.apple.AOSKit/282 (com.apple.dt.Xcode/3594.4.19)>",
        }
        headers.update(module.generate_anisette_headers())
        return headers

    def _trigger_trusted_second_factor(self, module: ModuleType, dsid: str, idms_token: str) -> None:
        headers = self._second_factor_headers(module, dsid, idms_token)
        response = module.requests.get(
            "https://gsa.apple.com/auth/verify/trusteddevice",
            headers=headers,
            verify=False,
            timeout=10,
        )
        if not response.ok:
            raise RuntimeError("Apple did not accept the trusted-device verification request.")

    def _validate_trusted_second_factor(self, module: ModuleType, dsid: str, idms_token: str, code: str) -> None:
        headers = self._second_factor_headers(module, dsid, idms_token)
        headers["security-code"] = code.strip()
        response = module.requests.get(
            "https://gsa.apple.com/grandslam/GsService2/validate",
            headers=headers,
            verify=False,
            timeout=10,
        )
        if not response.ok:
            raise RuntimeError("Apple rejected the two-factor code. Check the latest code and try again.")

    def _trigger_sms_second_factor(self, module: ModuleType, dsid: str, idms_token: str) -> None:
        headers = self._second_factor_headers(module, dsid, idms_token)
        body = {"phoneNumber": {"id": 1}, "mode": "sms"}
        response = module.requests.put(
            "https://gsa.apple.com/auth/verify/phone/",
            json=body,
            headers=headers,
            verify=False,
            timeout=10,
        )
        if not response.ok:
            raise RuntimeError("Apple did not accept the SMS verification request.")

    def _validate_sms_second_factor(self, module: ModuleType, dsid: str, idms_token: str, code: str) -> None:
        headers = self._second_factor_headers(module, dsid, idms_token)
        body = {
            "phoneNumber": {"id": 1},
            "mode": "sms",
            "securityCode": {"code": code.strip()},
        }
        response = module.requests.post(
            "https://gsa.apple.com/auth/verify/phone/securitycode",
            json=body,
            headers=headers,
            verify=False,
            timeout=10,
        )
        if not response.ok:
            raise RuntimeError("Apple rejected the SMS two-factor code. Check the latest code and try again.")

    @staticmethod
    def _auth_data_from_mobileme(username: str, mobileme: dict) -> dict:
        try:
            return {
                "account_identifier": username,
                "dsid": str(mobileme["dsid"]),
                "searchPartyToken": mobileme["delegates"]["com.apple.mobileme"]["service-data"]["tokens"]["searchPartyToken"],
            }
        except Exception as exc:
            raise RuntimeError("Apple auth response did not include a Search Party token.") from exc

    @staticmethod
    def _friendly_error(exc: Exception) -> str:
        text = str(exc).strip()
        if not text:
            return "Apple authentication failed."
        if "AuthenticationError" in text:
            return "Apple authentication failed. Check your Apple ID, password, and two-factor code."
        return text
