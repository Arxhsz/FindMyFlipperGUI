"""Windows desktop bridge for a USB-connected Flipper Zero.

The bridge talks to the official Flipper serial CLI.  It never scans arbitrary
serial ports: only ports whose USB metadata identifies a Flipper (including
the standard STM32 CDC VID/PID) are considered.
"""
from __future__ import annotations

import base64
import re
import threading
import time
from contextlib import contextmanager
from pathlib import PurePosixPath
from typing import Iterator, Optional

import serial
from serial.tools import list_ports


KEY_DIRECTORY = "/ext/apps_data/findmy"
FLIPPER_USB_IDS = {(0x0483, 0x5740)}
_SERIAL_LOCK = threading.RLock()


def _is_flipper_port(port) -> bool:
    metadata = " ".join(
        str(value or "")
        for value in (
            getattr(port, "description", ""),
            getattr(port, "manufacturer", ""),
            getattr(port, "product", ""),
            getattr(port, "interface", ""),
        )
    ).lower()
    ids = (getattr(port, "vid", None), getattr(port, "pid", None))
    return "flipper" in metadata or ids in FLIPPER_USB_IDS


def find_flipper_port() -> Optional[str]:
    return next(
        (port.device for port in list_ports.comports() if _is_flipper_port(port)),
        None,
    )


def _safe_key_filename(filename: str) -> str:
    name = PurePosixPath(filename).name
    if name != filename or not re.fullmatch(r"[A-Za-z0-9._-]+\.keys", name):
        raise ValueError("The key filename must be a simple .keys filename.")
    return name


def _read_until_prompt(connection: serial.Serial, timeout: float = 8.0) -> str:
    deadline = time.monotonic() + timeout
    received = bytearray()
    while time.monotonic() < deadline:
        waiting = connection.in_waiting
        chunk = connection.read(waiting or 1)
        if chunk:
            received.extend(chunk)
            normalized = received.replace(b"\r\n", b"\n")
            if normalized.endswith((b">: ", b">:", b"> ")):
                break
    return received.decode("utf-8", errors="replace")


@contextmanager
def _connection() -> Iterator[tuple[str, serial.Serial]]:
    port = find_flipper_port()
    if not port:
        raise RuntimeError(
            "No Flipper Zero USB serial connection was found. Connect a data "
            "cable and close qFlipper before retrying."
        )
    with _SERIAL_LOCK:
        try:
            connection = serial.Serial(
                port=port, baudrate=115200, timeout=0.2, write_timeout=3
            )
        except serial.SerialException as exc:
            raise RuntimeError(
                f"Could not open {port}. Close qFlipper and retry: {exc}"
            ) from exc
        try:
            connection.reset_input_buffer()
            connection.write(b"\r")
            _read_until_prompt(connection, timeout=3)
            yield port, connection
        finally:
            connection.close()


def _command(connection: serial.Serial, command: str, timeout: float = 8.0) -> str:
    connection.reset_input_buffer()
    connection.write(command.encode("utf-8") + b"\r")
    connection.flush()
    output = _read_until_prompt(connection, timeout)
    if not output:
        raise RuntimeError("The Flipper did not respond to its serial CLI.")
    lowered = output.lower()
    if "command not found" in lowered or "error:" in lowered:
        raise RuntimeError(output.strip())
    return output


def _clean_command_output(output: str, command: str) -> str:
    lines = output.replace("\r\n", "\n").replace("\r", "\n").splitlines()
    cleaned = []
    for line in lines:
        stripped = line.strip()
        if not stripped or stripped == command or stripped in {">:", ">"}:
            continue
        if stripped.startswith(">:"):
            stripped = stripped[2:].lstrip()
            if not stripped:
                continue
        cleaned.append(stripped)
    return "\n".join(cleaned).strip()


def status() -> dict:
    port = find_flipper_port()
    return {
        "ok": True,
        "connected": port is not None,
        "port": port,
        "error": None if port else (
            "No Flipper Zero USB serial connection was found. Connect a data "
            "cable and close qFlipper."
        ),
    }


def list_keys() -> dict:
    command = f'storage list "{KEY_DIRECTORY}"'
    with _connection() as (port, connection):
        output = _command(connection, command)
    files = sorted(
        set(re.findall(r"([A-Za-z0-9._-]+\.keys)\b", output, re.IGNORECASE))
    )
    return {"ok": True, "port": port, "files": files}


def import_key(filename: str) -> dict:
    name = _safe_key_filename(filename)
    command = f'storage read "{KEY_DIRECTORY}/{name}"'
    with _connection() as (port, connection):
        output = _command(connection, command, timeout=12)
    content = _clean_command_output(output, command)
    if "private key" not in content.lower() or "hashed adv key" not in content.lower():
        raise RuntimeError(f"{name} did not contain a valid FindMyFlipper identity.")
    return {"ok": True, "port": port, "filename": name, "raw_content": content}


def write_key(filename: str, raw_content: str) -> dict:
    name = _safe_key_filename(filename or "findmyflipper.keys")
    if not raw_content.strip():
        raise ValueError("The key content is empty.")
    path = f"{KEY_DIRECTORY}/{name}"
    with _connection() as (port, connection):
        try:
            _command(connection, f'storage mkdir "{KEY_DIRECTORY}"')
        except RuntimeError as exc:
            if "exist" not in str(exc).lower():
                raise
        command = f'storage write "{path}"'
        connection.reset_input_buffer()
        connection.write(command.encode("utf-8") + b"\r")
        time.sleep(0.25)
        connection.write(raw_content.encode("utf-8"))
        if not raw_content.endswith("\n"):
            connection.write(b"\n")
        connection.write(b"\x03")
        connection.flush()
        result = _read_until_prompt(connection, timeout=15)
        if not result:
            raise RuntimeError("The Flipper did not confirm the key write.")
        verify_output = _command(connection, f'storage read "{path}"', timeout=12)
    verified = _clean_command_output(verify_output, f'storage read "{path}"')
    if "hashed adv key" not in verified.lower():
        raise RuntimeError("The Flipper key file could not be verified after writing.")
    return {"ok": True, "port": port, "destination": path}


def _normalized_hash(value: str) -> str:
    value = "".join(value.split())
    try:
        return base64.b64encode(base64.b64decode(value, validate=True)).decode()
    except (ValueError, TypeError):
        return value


def verify_hashed_adv_key(hashed_adv_key: str) -> dict:
    key_listing = list_keys()
    matching_filename = None
    for filename in key_listing["files"]:
        imported = import_key(filename)
        match = re.search(
            r"(?im)^\s*hashed\s+adv\s+key(?:\s*\(base64\))?\s*:\s*(\S+)",
            imported["raw_content"],
        )
        if match and _normalized_hash(match.group(1)) == _normalized_hash(
            hashed_adv_key
        ):
            matching_filename = filename
            break

    firmware = None
    with _connection() as (_, connection):
        info = _command(connection, "device_info", timeout=8)
    for pattern in (
        r"(?im)^\s*firmware(?:\s+version)?\s*[:=]\s*(.+)$",
        r"(?im)^\s*firmware_commit\s*[:=]\s*(.+)$",
    ):
        match = re.search(pattern, info)
        if match:
            firmware = match.group(1).strip()
            break
    return {
        "ok": True,
        "port": key_listing["port"],
        "files": key_listing["files"],
        "matching_filename": matching_filename,
        "firmware": firmware,
    }
