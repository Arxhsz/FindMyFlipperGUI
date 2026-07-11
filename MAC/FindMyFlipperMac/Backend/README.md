# Backend — FindMyFlipper Gateway

A local FastAPI server that handles Apple Find My authentication and report decryption.

## Prerequisites

- Python 3.11+
- Bundled original-compatible auth core in `findmy_gateway/vendor/cores`
- OrbStack or Docker Desktop for the local anisette service

## Setup

```bash
# From the FindMyFlipper project root:
cd Backend

# Create a virtual environment
python3 -m venv venv
source venv/bin/activate       # macOS/Linux
# or: venv\Scripts\activate    # Windows

# Install dependencies
pip install -r requirements.txt
```

## Original-Compatible Auth Core

The Apple GSA/iCloud authentication uses a minimal vendored copy of Matthew-compatible core files:

```text
Backend/findmy_gateway/vendor/cores/pypush_gsa_icloud.py
Backend/findmy_gateway/vendor/cores/old_key_generation.py
```

The app bundle includes this folder directly. It does not need the full upstream
`FindMyFlipperRepo` checkout at runtime.

## Upstream compatibility boundary

The bundled runtime includes every part of Matthew KuKanich's project needed by
the Mac report workflow, without requiring or launching a second checkout:

- `vendor/cores/pypush_gsa_icloud.py`: exact upstream Apple GSA/iCloud and anisette flow.
- `key_generator.py`: non-interactive form of upstream `generate_keys.py`, preserving
  SECP224R1 generation, advertisement payload construction, MAC derivation, SHA-256
  advertisement-key hashing, and the upstream filename-key compatibility rule.
- `reports.py`: upstream `gateway.icloud.com/acsnservice/fetch` request shape using
  DSID plus `searchPartyToken` and anisette headers.
- `decryptor.py`: upstream ECDH, SHA-256 KDF, AES-GCM, Apple epoch, latitude,
  longitude, confidence, and status decoding, exposed as typed API models.
- `key_parser.py`: accepts Matthew's `.keys` field names and Base64 aliases.

The Flipper firmware C source is not executed by macOS; it remains firmware for
the physical device. The Mac USB bridge targets the same firmware directory,
`/ext/apps_data/findmy`, and validates actual files through the Flipper serial CLI.

If these bundled files are missing, all auth endpoints return a JSON error (not a crash):
```json
{ "error": "Bundled FindMyFlipper auth core is missing from Backend/findmy_gateway/vendor/cores." }
```

## Starting the Server

```bash
# From the Backend/ directory with venv activated:
python -m findmy_gateway.server
# Server starts on http://127.0.0.1:8765
```

The macOS app will start the server automatically on launch.

## Anisette Runtime

`POST /auth/start-anisette` starts the local anisette server on `127.0.0.1:6969`.
By default it will not install anything. When called with `{"install_if_missing": true}`, the gateway
will use Homebrew to install OrbStack if no Docker CLI is available, launch the Docker runtime, and
start `dadoum/anisette-v3-server:latest` bound to localhost.

## Apple Access

`POST /auth/connect` accepts:

```json
{
  "username": "apple-id@example.com",
  "password": "not-stored",
  "second_factor": "trusted_device",
  "code": "123456"
}
```

`second_factor` can be `trusted_device` or `sms`. If Apple requires a two-factor code and no code was
provided, the response includes `requires_2fa: true`. The backend stores only the DSID and
`searchPartyToken` returned by the original-compatible flow.

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | Health check |
| POST | `/keys/validate` | Validate a .keys file |
| POST | `/reports/decrypted` | Fetch and decrypt reports |
| POST | `/reports/refresh` | Refresh reports |
| GET | `/reports/latest` | Get latest report |
| POST | `/auth/status` | Check Apple auth status |
| POST | `/auth/connect` | Connect Apple account |
| POST | `/auth/refresh` | Refresh Apple auth token |
