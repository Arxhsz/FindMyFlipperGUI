"""Manage the local anisette service used by Apple GSA authentication."""
from __future__ import annotations

import os
import platform
import shutil
import subprocess
import time
import urllib.request
from dataclasses import dataclass
from typing import Optional


ANISETTE_URL = "http://127.0.0.1:6969"
CONTAINER_NAME = "anisette-v3"
IMAGE_NAME = "dadoum/anisette-v3-server:latest"
DOCKER_READY_TIMEOUT_SECONDS = 90
ANISETTE_READY_TIMEOUT_SECONDS = 45

EXTRA_PATHS = (
    "/opt/homebrew/bin",
    "/usr/local/bin",
    "/usr/bin",
    "/bin",
    "/usr/sbin",
    "/sbin",
)


@dataclass
class AnisetteResult:
    ok: bool
    installed: bool = False
    started: bool = False
    runtime: Optional[str] = None
    message: Optional[str] = None
    error: Optional[str] = None
    detail: Optional[str] = None

    def as_dict(self) -> dict:
        return {
            "ok": self.ok,
            "installed": self.installed,
            "started": self.started,
            "runtime": self.runtime,
            "message": self.message,
            "error": self.error,
            "detail": self.detail,
        }


def ensure_anisette_server(install_if_missing: bool = False) -> AnisetteResult:
    """Ensure the local anisette server is reachable on 127.0.0.1:6969."""
    if anisette_is_available():
        return AnisetteResult(
            ok=True,
            runtime="existing",
            message="Anisette server is already running.",
        )

    installed = False
    docker = _which("docker")

    if docker is None:
        if not install_if_missing:
            return AnisetteResult(
                ok=False,
                error=(
                    "Docker is not installed or not in PATH. Install OrbStack "
                    "from the app setup flow, or install Docker Desktop manually."
                ),
            )

        install_result = _install_orbstack()
        if not install_result.ok:
            return install_result
        installed = install_result.installed
        docker = _which("docker")

    if docker is None:
        return AnisetteResult(
            ok=False,
            installed=installed,
            error="OrbStack was installed, but the docker CLI is not available yet.",
            detail="Open OrbStack once, finish its setup, then try Connect with Apple again.",
        )

    if not _wait_for_docker_daemon(docker):
        return AnisetteResult(
            ok=False,
            installed=installed,
            runtime="docker",
            error="Docker is installed but its engine is not running.",
            detail="Open OrbStack or Docker Desktop, wait for it to finish starting, then try again.",
        )

    start_result = _start_anisette_container(docker)
    if not start_result.ok:
        start_result.installed = installed
        return start_result

    if not _wait_for_anisette():
        return AnisetteResult(
            ok=False,
            installed=installed,
            started=True,
            runtime="docker",
            error="Anisette container started, but the service did not become reachable.",
            detail=f"Expected {ANISETTE_URL} to respond within {ANISETTE_READY_TIMEOUT_SECONDS} seconds.",
        )

    return AnisetteResult(
        ok=True,
        installed=installed,
        started=True,
        runtime="docker",
        message="Anisette server is running.",
    )


def anisette_is_available(timeout: float = 2.0) -> bool:
    try:
        with urllib.request.urlopen(ANISETTE_URL, timeout=timeout) as response:
            return 200 <= response.status < 500
    except Exception:
        return False


def _install_orbstack() -> AnisetteResult:
    if platform.system() != "Darwin":
        return AnisetteResult(
            ok=False,
            error="Automatic Docker runtime install is currently supported on macOS only.",
        )

    brew = _which("brew")
    if brew is None:
        return AnisetteResult(
            ok=False,
            error="Homebrew is not installed, so FindMyFlipper cannot install OrbStack automatically.",
            detail="Install Homebrew or install OrbStack/Docker Desktop manually, then try again.",
        )

    installed = _run([brew, "list", "--cask", "orbstack"], timeout=30).returncode == 0
    if not installed:
        proc = _run([brew, "install", "--cask", "orbstack"], timeout=900)
        if proc.returncode != 0:
            return AnisetteResult(
                ok=False,
                error="Failed to install OrbStack with Homebrew.",
                detail=_trim(proc.stderr or proc.stdout),
            )
        installed = True

    _run(["open", "-ga", "OrbStack"], timeout=15)

    if _which("docker") is None:
        proc = _run([brew, "install", "docker"], timeout=900)
        if proc.returncode != 0:
            return AnisetteResult(
                ok=False,
                installed=installed,
                runtime="orbstack",
                error="OrbStack is installed, but installing the Docker CLI failed.",
                detail=_trim(proc.stderr or proc.stdout),
            )

    return AnisetteResult(
        ok=True,
        installed=installed,
        runtime="orbstack",
        message="OrbStack is installed and starting.",
    )


def _wait_for_docker_daemon(docker: str) -> bool:
    if _docker_info_ok(docker):
        return True

    _run(["open", "-ga", "OrbStack"], timeout=15)
    _run(["open", "-ga", "Docker"], timeout=15)

    deadline = time.monotonic() + DOCKER_READY_TIMEOUT_SECONDS
    while time.monotonic() < deadline:
        if _docker_info_ok(docker):
            return True
        time.sleep(2)
    return False


def _docker_info_ok(docker: str) -> bool:
    return _run([docker, "info"], timeout=15).returncode == 0


def _start_anisette_container(docker: str) -> AnisetteResult:
    inspect = _run([docker, "inspect", CONTAINER_NAME], timeout=30)
    if inspect.returncode == 0:
        proc = _run([docker, "start", CONTAINER_NAME], timeout=60)
    else:
        proc = _run(
            [
                docker,
                "run",
                "-d",
                "--restart",
                "unless-stopped",
                "--name",
                CONTAINER_NAME,
                "-p",
                "127.0.0.1:6969:6969",
                IMAGE_NAME,
            ],
            timeout=300,
        )

    if proc.returncode == 0:
        return AnisetteResult(ok=True, started=True, runtime="docker")

    if "port is already allocated" in proc.stderr.lower() and anisette_is_available():
        return AnisetteResult(
            ok=True,
            started=False,
            runtime="docker",
            message="Anisette server is already available on port 6969.",
        )

    return AnisetteResult(
        ok=False,
        runtime="docker",
        error="Failed to start the anisette Docker container.",
        detail=_trim(proc.stderr or proc.stdout),
    )


def _wait_for_anisette() -> bool:
    deadline = time.monotonic() + ANISETTE_READY_TIMEOUT_SECONDS
    while time.monotonic() < deadline:
        if anisette_is_available():
            return True
        time.sleep(1)
    return False


def _which(name: str) -> Optional[str]:
    return shutil.which(name, path=_command_env()["PATH"])


def _run(cmd: list[str], timeout: int) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
            env=_command_env(),
        )
    except subprocess.TimeoutExpired as exc:
        return subprocess.CompletedProcess(
            cmd,
            returncode=124,
            stdout=exc.stdout.decode() if isinstance(exc.stdout, bytes) else (exc.stdout or ""),
            stderr=exc.stderr.decode() if isinstance(exc.stderr, bytes) else (exc.stderr or "Timed out."),
        )
    except FileNotFoundError as exc:
        return subprocess.CompletedProcess(cmd, returncode=127, stdout="", stderr=str(exc))


def _command_env() -> dict[str, str]:
    env = os.environ.copy()
    existing = env.get("PATH", "")
    paths = [p for p in EXTRA_PATHS if p not in existing.split(os.pathsep)]
    env["PATH"] = os.pathsep.join(paths + ([existing] if existing else []))
    return env


def _trim(value: str, limit: int = 1200) -> str:
    value = value.strip()
    if len(value) <= limit:
        return value
    return value[:limit].rstrip() + "..."
