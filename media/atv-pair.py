#!/usr/bin/env python3
"""Apple TV pairing script for WSL (uses IP instead of mDNS identifier)"""
import asyncio
import sys
import time
from pathlib import Path

import pyatv

ATV_HOST = "192.168.68.67"
CRED_DIR = Path.home() / "atv-credentials"
PIN_FILE = Path("/tmp/atv_pin.txt")


async def pair_protocol(protocol_name, protocol):
    PIN_FILE.unlink(missing_ok=True)

    print(f"\n{'='*40}")
    print(f"Pairing {protocol_name}...")
    print(f"{'='*40}")

    atvs = await pyatv.scan(asyncio.get_event_loop(), hosts=[ATV_HOST])
    if not atvs:
        print("Apple TV not found!")
        return None

    atv = atvs[0]
    pairing = await pyatv.pair(atv, protocol=protocol, loop=asyncio.get_event_loop())
    await pairing.begin()
    print(f"PIN should be on TV screen now!")
    print(f"Write PIN to {PIN_FILE}")

    pin = None
    for _ in range(120):
        try:
            pin = PIN_FILE.read_text().strip()
            if pin:
                break
        except FileNotFoundError:
            pass
        time.sleep(1)

    if not pin:
        print("No PIN received, aborting")
        await pairing.close()
        return None

    print(f"Using PIN: {pin}")
    pairing.pin(int(pin))
    await pairing.finish()

    cred = None
    if pairing.has_paired:
        cred = pairing.service.credentials
        print(f"SUCCESS! Credentials: {cred}")
    else:
        print("Pairing failed!")

    await pairing.close()
    return cred


async def main():
    CRED_DIR.mkdir(parents=True, exist_ok=True)

    # Companion
    cred = await pair_protocol("Companion", pyatv.const.Protocol.Companion)
    if cred:
        (CRED_DIR / "companion.txt").write_text(cred)
        print(f"Saved to {CRED_DIR / 'companion.txt'}")

    # AirPlay
    cred = await pair_protocol("AirPlay", pyatv.const.Protocol.AirPlay)
    if cred:
        (CRED_DIR / "airplay.txt").write_text(cred)
        print(f"Saved to {CRED_DIR / 'airplay.txt'}")

    print("\nDone!")


if __name__ == "__main__":
    asyncio.run(main())
