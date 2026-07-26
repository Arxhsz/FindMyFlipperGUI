"""Frozen Windows helper that ensures the local anisette service is online."""
from __future__ import annotations

import json
import os
from pathlib import Path
import sys

from findmy_gateway.anisette import ensure_anisette_server


def main() -> int:
    result = ensure_anisette_server(install_if_missing=False)
    serialized = json.dumps(result.as_dict())
    if sys.stdout is not None:
        print(serialized)
    try:
        root = Path(os.environ.get("LOCALAPPDATA", Path.home())) / "FindMyFlipper"
        root.mkdir(parents=True, exist_ok=True)
        (root / "anisette.log").write_text(serialized + "\n", encoding="utf-8")
    except OSError:
        pass
    return 0 if result.ok else 2


if __name__ == "__main__":
    sys.exit(main())
