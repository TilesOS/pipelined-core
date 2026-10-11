#!/usr/bin/env python3
"""Pack firmware/payload into a compact ROM; the loader zeroes their DDR gap."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("firmware", type=Path)
    parser.add_argument("payload", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    firmware, payload = args.firmware.read_bytes(), args.payload.read_bytes()
    if not 0 < len(firmware) < 0x40000:
        parser.error("firmware must fit its 256 KiB reservation")
    if not 0 < len(payload) < 0x10000:
        parser.error("payload must fit below 0x80050000")
    image = firmware + bytes(0x40000 - len(firmware)) + payload
    image += bytes(-len(image) % 16)
    firmware_padded = firmware + bytes(-len(firmware) % 16)
    payload_padded = payload + bytes(-len(payload) % 16)
    rom_data = firmware_padded + payload_padded
    firmware_words = len(firmware_padded) // 16
    payload_word = 0x40000 // 16
    args.output.mkdir(parents=True, exist_ok=True)
    rom = args.output.resolve() / "checkpoint10_image.mem"
    rom.write_text("".join(rom_data[i:i+16][::-1].hex() + "\n" for i in range(0, len(rom_data), 16)))
    (args.output / "checkpoint10_image.svh").write_text(
        f"`define CHECKPOINT10_IMAGE_WORDS {len(image) // 16}\n"
        f"`define CHECKPOINT10_ROM_WORDS {len(rom_data) // 16}\n"
        f"`define CHECKPOINT10_FIRMWARE_WORDS {firmware_words}\n"
        f"`define CHECKPOINT10_PAYLOAD_WORD {payload_word}\n"
        f"`define CHECKPOINT10_IMAGE_FILE {json.dumps(str(rom))}\n")
    manifest = {
        "rom_layout": "firmware_then_payload_v1",
        "source_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
        "source_dirty": bool(subprocess.check_output(["git", "status", "--porcelain"], text=True).strip()),
        "opensbi_commit": "a32a91069119e7a5aa31e6bc51d5e00860be3d80",
        "firmware_bytes": len(firmware), "payload_bytes": len(payload),
        "image_bytes": len(image), "image_words": len(image) // 16,
        "rom_bytes": len(rom_data), "rom_words": len(rom_data) // 16,
        "firmware_words": firmware_words, "payload_word": payload_word,
        "firmware_address": "0x80000000", "payload_address": "0x80040000",
        "relocated_fdt_address": "0x80060000",
        "firmware_sha256": hashlib.sha256(firmware).hexdigest(),
        "payload_sha256": hashlib.sha256(payload).hexdigest(),
        "image_sha256": hashlib.sha256(image).hexdigest(),
        "rom_file_sha256": hashlib.sha256(rom.read_bytes()).hexdigest(),
    }
    (args.output / "image-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Board image: {len(image)} bytes, {len(image)//16} 128-bit words; {rom}")
    print(f"Compact ROM: {len(rom_data)} bytes, {len(rom_data)//16} words; DDR gap generated as zeroes")


if __name__ == "__main__":
    main()
