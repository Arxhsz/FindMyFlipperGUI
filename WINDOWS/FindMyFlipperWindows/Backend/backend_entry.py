"""Frozen Windows entry point for the local FindMyFlipper gateway."""
from __future__ import annotations

import datetime
import os
from pathlib import Path
import sys
import traceback


if not getattr(sys, "frozen", False):
    # Windows development builds reuse the same gateway package as macOS.
    shared_backend = Path(__file__).resolve().parents[3] / "MAC" / "FindMyFlipperMac" / "Backend"
    if shared_backend.is_dir():
        sys.path.insert(0, str(shared_backend))


def _trace(message: str) -> None:
    """Write release-startup diagnostics without depending on console pipes."""
    try:
        root = Path(os.environ.get("LOCALAPPDATA", Path.home())) / "FindMyFlipper"
        root.mkdir(parents=True, exist_ok=True)
        timestamp = datetime.datetime.now(datetime.timezone.utc).isoformat()
        with (root / "backend.log").open("a", encoding="utf-8") as stream:
            stream.write(f"{timestamp} {message}\n")
    except OSError:
        pass


def main() -> None:
    _trace("backend process entered")
    try:
        _trace("importing uvicorn")
        import uvicorn

        _trace("importing findmy_gateway.server")
        from findmy_gateway.server import app

        _trace("starting loopback HTTP server on 127.0.0.1:8765")
        # PyInstaller's windowed bootloader intentionally supplies no console
        # streams. Uvicorn's default color formatter calls stderr.isatty(), so
        # disable that console logging configuration for the release service.
        uvicorn.run(
            app,
            host="127.0.0.1",
            port=8765,
            log_config=None,
            access_log=False,
        )
        _trace("loopback HTTP server stopped normally")
    except BaseException:
        _trace("fatal backend startup failure:\n" + traceback.format_exc())
        raise


if __name__ == "__main__":
    main()
