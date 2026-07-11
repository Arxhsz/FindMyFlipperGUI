import base64
import hashlib

from findmy_gateway.key_generator import generate_keys_content
from findmy_gateway.key_parser import KeyParser


def test_generated_content_matches_original_findmyflipper_invariants():
    content = generate_keys_content()
    record = KeyParser().parse(content)
    public_key = base64.b64decode(record.advertisement_key_base64)

    assert len(base64.b64decode(record.private_key_base64)) == 28
    assert len(public_key) == 28
    assert base64.b64encode(hashlib.sha256(public_key).digest()).decode() == record.hashed_adv_key_base64
    assert len(record.generated_findmy_mac) == 12
    assert len(bytes.fromhex(record.payload)) == 31
    assert bytes.fromhex(record.payload)[0:7] == bytes.fromhex("1eff4c00121900")
