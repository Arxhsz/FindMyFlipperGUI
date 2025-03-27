#!/usr/bin/env python3
import asyncio
import sys
import time
import logging
from bleak import BleakScanner, BleakClient, BleakError

logging.basicConfig(level=logging.DEBUG)

# Default fallback MAC
TARGET_ADDRESS = "00:00:00:00:00:00"
if len(sys.argv) > 1:
    TARGET_ADDRESS = sys.argv[1]

WRITE_CHAR_UUID = "19ed82ae-ed21-4c9d-4145-228e62fe0000"
READ_CHAR_UUID  = "19ed82ae-ed21-4c9d-4145-228e61fe0000"
WRITE_PAYLOAD_HEX = "03B20200"
EXPECTED_RESPONSE_HEX = "022200"

SCAN_TIMEOUT_SECS = 30  # We'll manually scan for up to 30s

class PersistentFlipper:
    def __init__(self, address):
        self.address = address
        self.client = None
        self.connected = False

    async def scan_for_device(self):
        """
        Manually scan for the device up to SCAN_TIMEOUT_SECS.
        If found, return True. Otherwise return False.
        """
        start_time = time.time()
        found = False
        while (time.time() - start_time) < SCAN_TIMEOUT_SECS:
            # Scan for ~2s each iteration
            logging.debug("Scanning for 2s...")
            devices = await BleakScanner.discover(timeout=2.0)
            for d in devices:
                logging.debug(f"Found device: {d.address} - {d.name}")
                if d.address.lower() == self.address.lower():
                    logging.info(f"Found target device {self.address}")
                    found = True
                    break
            if found:
                break
        return found

    async def connect(self):
        # 1) Manually scan for the device first
        found = await self.scan_for_device()
        if not found:
            print("FLIPPER_NOT_FOUND", flush=True)
            self.connected = False
            return

        # 2) If found, try connecting
        try:
            self.client = BleakClient(self.address)
            await self.client.connect()
            self.connected = await self.client.is_connected()
            if self.connected:
                print("FLIPPER_CONNECTED", flush=True)
                logging.info(f"Connected to {self.address}")
                await self.client.start_notify(READ_CHAR_UUID, self.notification_handler)
            else:
                print("FLIPPER_NOT_FOUND", flush=True)
                logging.error("Could not connect to device.")
        except Exception as e:
            logging.error(f"Failed to connect: {e}")
            print("FLIPPER_NOT_FOUND", flush=True)
            self.connected = False

    def notification_handler(self, sender, data):
        logging.debug(f"Notification from {sender}: {data.hex()}")

    async def send_alert(self):
        if not self.connected:
            print("Not connected", flush=True)
            return
        try:
            payload = bytes.fromhex(WRITE_PAYLOAD_HEX)
            logging.info(f"Sending alert command: {payload.hex()}")
            await self.client.write_gatt_char(WRITE_CHAR_UUID, payload, response=True)
            await asyncio.sleep(2)
            print("Success! Alert played.", flush=True)
        except Exception as e:
            logging.error(f"Error sending alert: {e}")
            print(f"Error: {e}", flush=True)

    async def disconnect(self):
        if self.connected and self.client:
            await self.client.disconnect()
            self.connected = False
            logging.info("Disconnected from device.")

async def main():
    flipper = PersistentFlipper(TARGET_ADDRESS)
    await flipper.connect()

    loop = asyncio.get_running_loop()
    while True:
        try:
            line = await loop.run_in_executor(None, sys.stdin.readline)
            if not line:
                break
            cmd = line.strip()
            if cmd == "alert":
                if not flipper.connected:
                    await flipper.connect()
                if flipper.connected:
                    await flipper.send_alert()
            elif cmd == "quit":
                break
        except Exception as e:
            logging.error(f"Error reading command: {e}")
            break
    await flipper.disconnect()

if __name__ == "__main__":
    asyncio.run(main())
