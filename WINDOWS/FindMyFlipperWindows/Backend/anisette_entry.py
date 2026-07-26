"""Frozen Windows helper that ensures the local anisette service is online."""
from __future__ import annotations

import json
import sys

from findmy_gateway.anisette import ensure_anisette_server


def main() -> int:
    result = ensure_anisette_server(install_if_missing=False)
    print(json.dumps(result.as_dict()))
    return 0 if result.ok else 2


if __name__ == "__main__":
    sys.exit(main())
