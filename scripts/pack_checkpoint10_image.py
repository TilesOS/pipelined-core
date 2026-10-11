#!/usr/bin/env python3
"""Pack the board proof firmware into little-endian 128-bit ROM words."""
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
    args.output.mkdir(parents=True, exist_ok=True)
    rom = args.output.resolve() / "checkpoint10_image.mem"
    rom.write_text("".join(image[i:i+16][::-1].hex() + "\n" for i in range(0, len(image), 16)))
    (args.output / "checkpoint10_image.svh").write_text(
        f"`define CHECKPOINT10_IMAGE_WORDS {len(image) // 16}\n"
        f"`define CHECKPOINT10_IMAGE_FILE {json.dumps(str(rom))}\n")
    manifest = {
        "source_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
        "source_dirty": bool(subprocess.check_output(["git", "status", "--porcelain"], text=True).strip()),
        "opensbi_commit": "a32a91069119e7a5aa31e6bc51d5e00860be3d80",
        "firmware_bytes": len(firmware), "payload_bytes": len(payload),
        "image_bytes": len(image), "image_words": len(image) // 16,
        "firmware_address": "0x80000000", "payload_address": "0x80040000",
        "relocated_fdt_address": "0x80060000",
        "firmware_sha256": hashlib.sha256(firmware).hexdigest(),
        "payload_sha256": hashlib.sha256(payload).hexdigest(),
        "image_sha256": hashlib.sha256(image).hexdigest(),
        "rom_file_sha256": hashlib.sha256(rom.read_bytes()).hexdigest(),
    }
    (args.output / "image-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Board image: {len(image)} bytes, {len(image)//16} 128-bit words; {rom}")


if __name__ == "__main__":
    main()
