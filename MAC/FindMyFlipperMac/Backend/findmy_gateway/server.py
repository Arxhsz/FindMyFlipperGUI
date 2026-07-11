"""FindMyFlipper Gateway FastAPI server."""
from __future__ import annotations
import logging
from pathlib import Path
from typing import Optional
import uvicorn
from fastapi import FastAPI
from pydantic import BaseModel
from .key_parser import KeyParser
from .decryptor import Decryptor
from .models import FindMyKeyModel
from .storage import ReportStorage, AuthStorage
from .auth import AuthManager
from .reports import ReportFetcher, AuthRequiredError
from .anisette import ensure_anisette_server
from .key_generator import generate_keys_content

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="FindMyFlipper Gateway", version="1.0.0")

# Initialize singletons
_auth_storage = AuthStorage()
_report_storage = ReportStorage()
_auth_manager = AuthManager(_auth_storage)
_report_fetcher = ReportFetcher(_auth_manager, _report_storage)
_key_parser = KeyParser()

# --- Request models ---
class KeysValidateRequest(BaseModel):
    raw_content: str

class ReportsRequest(BaseModel):
    hashed_adv_key_base64: str
    private_key_base64: str
    hours: int = 24

class AuthConnectRequest(BaseModel):
    username: Optional[str] = None
    password: Optional[str] = None
    second_factor: str = "trusted_device"
    code: Optional[str] = None

class StartAnisetteRequest(BaseModel):
    install_if_missing: bool = False

# --- Endpoints ---
@app.get("/health")
async def health():
    return {"status": "ok", "version": "1.0.0"}

@app.post("/keys/validate")
async def validate_keys(body: KeysValidateRequest):
    is_valid, errors, parsed_fields = _key_parser.validate(body.raw_content)
    # Return only non-secret parsed fields
    safe_fields = {k: v for k, v in parsed_fields.items()
                   if k not in ("private_key_base64", "private_key_hex")}
    return {"valid": is_valid, "errors": errors, "parsedFields": safe_fields}

@app.post("/reports/decrypted")
async def get_decrypted_reports(body: ReportsRequest):
    try:
        reports = _report_fetcher.fetch_and_decrypt(
            body.hashed_adv_key_base64, body.private_key_base64, body.hours
        )
        return {
            "ok": True,
            "reports": reports,
            "foundKeys": _report_fetcher.last_found_keys,
            "missingKeys": _report_fetcher.last_missing_keys,
            "message": None if reports else "No reports yet. Your Flipper may not have been seen by nearby Apple devices."
        }
    except AuthRequiredError as e:
        return {"ok": False, "reports": [], "error": str(e)}
    except Exception as e:
        logger.error("Unexpected error in /reports/decrypted: %s", e)
        return {"ok": False, "reports": [], "error": str(e)}

@app.post("/reports/refresh")
async def refresh_reports(body: ReportsRequest):
    try:
        reports = _report_fetcher.fetch_and_decrypt(
            body.hashed_adv_key_base64, body.private_key_base64, body.hours
        )
        return {
            "ok": True,
            "reports": reports,
            "foundKeys": _report_fetcher.last_found_keys,
            "missingKeys": _report_fetcher.last_missing_keys,
        }
    except AuthRequiredError as e:
        return {"ok": False, "reports": [], "error": str(e)}
    except Exception as e:
        logger.error("Unexpected error in /reports/refresh: %s", e)
        return {"ok": False, "reports": [], "error": str(e)}

@app.get("/reports/latest")
async def get_latest_reports(hashed_adv_key_base64: str):
    reports = _report_storage.load_reports(hashed_adv_key_base64)
    return {"ok": True, "reports": reports}

@app.post("/auth/status")
async def auth_status():
    return _auth_manager.get_status()

@app.post("/auth/connect")
async def auth_connect(body: Optional[AuthConnectRequest] = None):
    request = body or AuthConnectRequest()
    return _auth_manager.connect(
        username=request.username,
        password=request.password,
        second_factor=request.second_factor,
        code=request.code,
    )

@app.post("/auth/refresh")
async def auth_refresh():
    return _auth_manager.refresh()

@app.post("/keys/generate")
async def generate_keys():
    try:
        return {"ok": True, "raw_content": generate_keys_content()}
    except RuntimeError as exc:
        return {"ok": False, "error": str(exc)}

@app.post("/auth/start-anisette")
async def start_anisette(body: Optional[StartAnisetteRequest] = None):
    request = body or StartAnisetteRequest()
    result = ensure_anisette_server(install_if_missing=request.install_if_missing)
    return result.as_dict()

if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=8765)
