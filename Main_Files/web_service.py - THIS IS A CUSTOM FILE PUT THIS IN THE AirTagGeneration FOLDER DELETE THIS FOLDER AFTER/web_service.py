# THIS IS A CUSTOM FILE PUT THIS IN THE AirTagGeneration FOLDER DELETE THIS FOLDER AFTER

#!/usr/bin/env python3
import argparse
import base64
import datetime
import glob
import hashlib
import json
import os
import re
import sqlite3
import struct
from typing import Dict, Any, List

import requests
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from fastapi import FastAPI, Query, Body
from fastapi.responses import JSONResponse
import uvicorn
import logging
import time

from cores.pypush_gsa_icloud import icloud_login_mobileme, generate_anisette_headers

logging.basicConfig(level=logging.ERROR)

app = FastAPI(
    title="FindMy Gateway API",
    summary="Query Apple's Find My network, returning decrypted location reports.",
    description="This endpoint uses the working logic from request_reports.py to decrypt the reports."
)

# Upstream auth configuration
CONFIG_PATH = os.path.join(os.path.dirname(os.path.realpath(__file__)), "keys", "auth.json")
if os.path.exists(CONFIG_PATH):
    with open(CONFIG_PATH, "r") as f:
        j = json.load(f)
else:
    mobileme = icloud_login_mobileme(second_factor='sms')
    j = {
        'dsid': mobileme['dsid'],
        'searchPartyToken': mobileme['delegates']['com.apple.mobileme']['service-data']['tokens']['searchPartyToken']
    }
    os.makedirs(os.path.join(os.path.dirname(os.path.realpath(__file__)), "keys"), exist_ok=True)
    with open(CONFIG_PATH, "w") as f:
        json.dump(j, f)

dsid = j['dsid']
searchPartyToken = j['searchPartyToken']

# Helper functions
def sha256(data: bytes) -> bytes:
    digest = hashlib.new("sha256")
    digest.update(data)
    return digest.digest()

def decrypt(enc_data: bytes, algorithm_dkey, mode) -> bytes:
    decryptor = Cipher(algorithm_dkey, mode, default_backend()).decryptor()
    return decryptor.update(enc_data) + decryptor.finalize()

def decode_tag(data: bytes) -> Dict[str, Any]:
    latitude = struct.unpack(">i", data[0:4])[0] / 10000000.0
    longitude = struct.unpack(">i", data[4:8])[0] / 10000000.0
    confidence = int.from_bytes(data[8:9], 'big')
    status = int.from_bytes(data[9:10], 'big')
    return {'lat': latitude, 'lon': longitude, 'conf': confidence, 'status': status}

# New endpoint that uses the logic from request_reports.py
@app.post("/DecryptedReports/", summary="Return decrypted reports using keys from the keys folder.")
async def decrypted_reports(
    hours: int = Query(24, description="Only show reports not older than these hours", ge=1, le=24),
    prefix: str = Query("", description="Only use keyfiles starting with this prefix (optional)")
) -> Dict[str, Any]:
    try:
        # Load key files from the keys folder (generated with your generate_keys.py)
        key_dir = os.path.join(os.path.dirname(os.path.realpath(__file__)), "keys")
        privkeys: Dict[str, str] = {}
        names: Dict[str, str] = {}
        for keyfile in glob.glob(os.path.join(key_dir, prefix + "*.keys")):
            with open(keyfile) as f:
                hashed_adv = ""
                priv = ""
                name = os.path.basename(keyfile)[len(prefix):-5]  # remove prefix and .keys
                for line in f:
                    parts = line.rstrip('\n').split(': ')
                    if len(parts) < 2:
                        continue
                    if parts[0] == 'Private key':
                        priv = parts[1]
                    elif parts[0] == 'Hashed adv key':
                        hashed_adv = parts[1]
                if priv and hashed_adv:
                    privkeys[hashed_adv] = priv
                    names[hashed_adv] = name
                else:
                    logging.error(f"Couldn't find key pair in {keyfile}")
        
        if not privkeys:
            return JSONResponse(content={"error": "No key files found."}, status_code=400)
        
        # Build the upstream query
        unix_epoch = int(datetime.datetime.now().timestamp())
        startdate = unix_epoch - (60 * 60 * hours)
        # Use the list of advertisement keys from the keys folder
        adv_keys = list(privkeys.keys())
        data = {
            "search": [{
                "startDate": startdate * 1000,
                "endDate": unix_epoch * 1000,
                "ids": adv_keys
            }]
        }
        
        r = requests.post(
            "https://gateway.icloud.com/acsnservice/fetch",
            auth=(dsid, searchPartyToken),
            headers=generate_anisette_headers(),
            json=data
        )
        res = json.loads(r.content.decode())['results']
        logging.info(f"{r.status_code}: {len(res)} reports received.")
        
        ordered: List[Dict[str, Any]] = []
        found = set()
        
        # Create (or ensure existence of) the reports table (for local logging if desired)
        # Not strictly necessary for the endpoint's return value.
        sq3db = sqlite3.connect(os.path.join(key_dir, "reports.db"))
        sq3 = sq3db.cursor()
        create_table_query = '''CREATE TABLE IF NOT EXISTS reports (
            id_short TEXT, timestamp INTEGER, datePublished INTEGER, payload TEXT, 
            id TEXT, statusCode INTEGER, lat TEXT, lon TEXT, conf INTEGER, PRIMARY KEY(id_short,timestamp)
        );'''
        sq3.execute(create_table_query)
        
        for report in res:
            # Get the private key for this report using its id (hashed advertisement key)
            if report['id'] not in privkeys:
                continue
            priv = int.from_bytes(base64.b64decode(privkeys[report['id']]), byteorder='big')
            payload_bytes = base64.b64decode(report['payload'])
            timestamp = int.from_bytes(payload_bytes[0:4], 'big') + 978307200
            
            if timestamp < startdate:
                continue
            
            # Calculate adjustment (some payloads may include extra bytes)
            adj = len(payload_bytes) - 88
            # Use SECP224R1 and adjust offsets as in your request_reports.py code
            try:
                eph_key = ec.EllipticCurvePublicKey.from_encoded_point(
                    ec.SECP224R1(), payload_bytes[5+adj:62+adj])
            except Exception as e:
                logging.error(f"Error extracting ephemeral key: {e}")
                continue
            shared_key = ec.derive_private_key(priv, ec.SECP224R1(), default_backend()).exchange(ec.ECDH(), eph_key)
            symmetric_key = sha256(shared_key + b'\x00\x00\x00\x01' + payload_bytes[5+adj:62+adj])
            decryption_key = symmetric_key[:16]
            iv = symmetric_key[16:]
            enc_data = payload_bytes[62+adj:72+adj]
            auth_tag = payload_bytes[72+adj:]
            try:
                decrypted = decrypt(enc_data, algorithms.AES(decryption_key), modes.GCM(iv, auth_tag))
            except Exception as e:
                logging.error(f"Decryption failed: {e}")
                continue
            tag = decode_tag(decrypted)
            tag['timestamp'] = timestamp
            tag['isodatetime'] = datetime.datetime.fromtimestamp(timestamp).isoformat()
            tag['key'] = names.get(report['id'], report['id'])
            tag['goog'] = 'https://maps.google.com/maps?q=' + str(tag['lat']) + ',' + str(tag['lon'])
            found.add(tag['key'])
            ordered.append(tag)
            
            # Optionally, store in local SQLite database
            query = "INSERT OR REPLACE INTO reports VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"
            parameters = (names.get(report['id'], report['id']),
                          timestamp, report['datePublished'], report['payload'],
                          report['id'], report['statusCode'], str(tag['lat']), str(tag['lon']), tag['conf'])
            sq3.execute(query, parameters)
        
        sq3db.commit()
        sq3.close()
        sq3db.close()
        
        ordered.sort(key=lambda item: item.get('timestamp', 0))
        result = {
            "reports": ordered,
            "found_keys": list(found),
            "missing_keys": [name for name in names.values() if name not in found]
        }
        return result
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)

if __name__ == "__main__":
    uvicorn.run("web_service:app", host="127.0.0.1", port=8000, log_level="error")
