"""
Parser for FindMyFlipper .keys file format.

Expected file format (key: value lines):
    Private key: <base64>
    Private key (Hex): <hex>
    Advertisement key: <base64>
    Advertisement key (Hex): <hex>
    Hashed adv key: <base64>
    MAC: <XX:XX:XX:XX:XX:XX>
    Payload: <base64>

Required fields:  Private key, Hashed adv key, MAC, Payload
Optional fields:  Private key (Hex), Advertisement key, Advertisement key (Hex)
"""

from __future__ import annotations

from typing import Optional

from .models import FindMyKeyModel

# ---------------------------------------------------------------------------
# Internal field name → model attribute mappings
# ---------------------------------------------------------------------------

# Keys are stored lower-cased for case-insensitive matching.
_FIELD_MAP: dict[str, str] = {
    "private key": "private_key_base64",
    "private key (base64)": "private_key_base64",
    "private key (hex)": "private_key_hex",
    "advertisement key": "advertisement_key_base64",
    "advertisement key (base64)": "advertisement_key_base64",
    "advertisement key (hex)": "advertisement_key_hex",
    "hashed adv key": "hashed_adv_key_base64",
    "hashed adv key (base64)": "hashed_adv_key_base64",
    "mac": "generated_findmy_mac",
    "payload": "payload",
}

_REQUIRED_FIELDS: list[str] = [
    "Private key",
    "Hashed adv key",
    "MAC",
    "Payload",
]


class KeyParser:
    """Parse and validate .keys file content."""

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def parse(self, raw_content: str) -> FindMyKeyModel:
        """
        Parse raw .keys file content and return a :class:`FindMyKeyModel`.

        Raises
        ------
        ValueError
            With message ``"Missing required field: <field_name>"`` when a
            required field is absent or has an empty value.
        """
        fields = self._extract_fields(raw_content)
        normalized = self._normalize_fields(fields)

        for field_name in _REQUIRED_FIELDS:
            model_key = _FIELD_MAP[field_name.lower()]
            if not normalized.get(model_key):
                raise ValueError(f"Missing required field: {field_name}")

        return FindMyKeyModel(
            private_key_base64=normalized["private_key_base64"],
            private_key_hex=normalized.get("private_key_hex") or None,
            advertisement_key_base64=normalized.get("advertisement_key_base64") or None,
            advertisement_key_hex=normalized.get("advertisement_key_hex") or None,
            hashed_adv_key_base64=normalized["hashed_adv_key_base64"],
            generated_findmy_mac=normalized["generated_findmy_mac"],
            payload=normalized["payload"],
        )

    def validate(
        self, raw_content: str
    ) -> tuple[bool, list[str], dict[str, Optional[str]]]:
        """
        Validate raw .keys file content without raising.

        Returns
        -------
        tuple
            ``(is_valid, error_list, parsed_fields_dict)``

            * *is_valid* – ``True`` iff all required fields are present and
              non-empty.
            * *error_list* – list of human-readable error strings; empty when
              valid.
            * *parsed_fields_dict* – dictionary of all parsed key/value pairs
              (lower-cased key names), including optional fields when present.
        """
        fields = self._extract_fields(raw_content)
        normalized = self._normalize_fields(fields)
        errors: list[str] = []

        for field_name in _REQUIRED_FIELDS:
            model_key = _FIELD_MAP[field_name.lower()]
            if not normalized.get(model_key):
                errors.append(f"Missing required field: {field_name}")

        is_valid = len(errors) == 0
        return is_valid, errors, normalized

    # ------------------------------------------------------------------
    # Private helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _extract_fields(raw_content: str) -> dict[str, str]:
        """
        Parse ``key: value`` lines from *raw_content*.

        Rules
        -----
        * Leading/trailing whitespace is stripped from both key and value.
        * Key matching is case-insensitive.
        * Lines without a colon separator are silently ignored.
        * The *first* colon on a line separates key from value, so Base64
          values containing ``=`` are handled correctly.
        """
        result: dict[str, str] = {}
        for line in raw_content.splitlines():
            line = line.strip()
            if not line:
                continue
            if ":" not in line:
                continue
            # Split only on the first colon so that values such as
            # "AA:BB:CC:DD:EE:FF" (MAC) remain intact.
            raw_key, _, raw_value = line.partition(":")
            key = raw_key.strip().lower()
            value = raw_value.strip()
            if key:
                result[key] = value
        return result

    @staticmethod
    def _normalize_fields(fields: dict[str, str]) -> dict[str, str]:
        normalized: dict[str, str] = {}
        for key, value in fields.items():
            model_key = _FIELD_MAP.get(key)
            if model_key and value:
                normalized[model_key] = value
        return normalized
