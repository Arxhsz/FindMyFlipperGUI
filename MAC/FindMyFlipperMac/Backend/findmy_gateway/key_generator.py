"""FindMyFlipper-compatible SECP224R1 identity generation.

This is the non-interactive backend form of Matthew KuKanich's
``AirTagGeneration/generate_keys.py`` algorithm.
"""
from __future__ import annotations

import base64

from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import ec


def advertisement_template() -> bytearray:
    advertisement = "1e" "ff" "4c00" "1219" "00"
    advertisement += "00" * 22
    advertisement += "00" "00"
    return bytearray.fromhex(advertisement)


def generate_mac_and_payload(public_key: ec.EllipticCurvePublicKey) -> tuple[str, str]:
    key = public_key.public_numbers().x.to_bytes(28, byteorder="big")
    address = bytearray(key[:6])
    address[0] |= 0b11000000
    advertisement = advertisement_template()
    advertisement[7:29] = key[6:28]
    advertisement[29] = key[0] >> 6
    return address.hex(), advertisement.hex()


def generate_keys_content(max_attempts: int = 100) -> str:
    for _ in range(max_attempts):
        private_key = ec.generate_private_key(ec.SECP224R1(), default_backend())
        public_key = private_key.public_key()
        private_bytes = private_key.private_numbers().private_value.to_bytes(28, byteorder="big")
        public_bytes = public_key.public_numbers().x.to_bytes(28, byteorder="big")
        private_base64 = base64.b64encode(private_bytes).decode("ascii")
        public_base64 = base64.b64encode(public_bytes).decode("ascii")

        digest = hashes.Hash(hashes.SHA256())
        digest.update(public_bytes)
        hashed_advertisement_key = base64.b64encode(digest.finalize()).decode("ascii")
        if "/" in hashed_advertisement_key[:7]:
            continue

        mac, payload = generate_mac_and_payload(public_key)
        return (
            f"Private key: {private_base64}\n"
            f"Advertisement key: {public_base64}\n"
            f"Hashed adv key: {hashed_advertisement_key}\n"
            f"Private key (Hex): {private_bytes.hex()}\n"
            f"Advertisement key (Hex): {public_bytes.hex()}\n"
            f"MAC: {mac}\n"
            f"Payload: {payload}\n"
        )

    raise RuntimeError(f"Failed to generate a compatible key after {max_attempts} attempts.")
