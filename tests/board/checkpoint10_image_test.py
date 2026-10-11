"""Check compact ROM reconstruction, padding, limits and artifact metadata."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class ImagePacking(unittest.TestCase):
    def pack(self, directory, firmware, payload):
        directory = Path(directory)
        (directory / "firmware.bin").write_bytes(firmware)
        (directory / "payload.bin").write_bytes(payload)
        return subprocess.run(
            [sys.executable, str(ROOT / "scripts/pack_checkpoint10_image.py"),
             str(directory / "firmware.bin"), str(directory / "payload.bin"),
             str(directory / "output")], cwd=ROOT, capture_output=True, text=True)

    def test_reconstruct_ddr_image(self):
        for firmware_size, payload_size in ((1, 1), (16, 16), (17, 31), (0x3ffff, 0xffff)):
            with self.subTest(firmware_size=firmware_size, payload_size=payload_size):
                with tempfile.TemporaryDirectory() as directory:
                    firmware = bytes((i * 13 + 1) % 256 for i in range(firmware_size))
                    payload = bytes((i * 7 + 3) % 256 for i in range(payload_size))
                    result = self.pack(directory, firmware, payload)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    output = Path(directory) / "output"
                    manifest = json.loads((output / "image-manifest.json").read_text())
                    rom_file = (output / "checkpoint10_image.mem").read_bytes()
                    words = [bytes.fromhex(line)[::-1] for line in rom_file.decode().splitlines()]
                    self.assertTrue(all(len(word) == 16 for word in words))
                    split = manifest["firmware_words"]
                    rom_data = b"".join(words)
                    ddr_image = b"".join(words[:split])
                    ddr_image += bytes(0x40000 - len(ddr_image))
                    ddr_image += b"".join(words[split:])
                    self.assertEqual(ddr_image[:firmware_size], firmware)
                    self.assertEqual(ddr_image[firmware_size:0x40000], bytes(0x40000-firmware_size))
                    self.assertEqual(ddr_image[0x40000:0x40000+payload_size], payload)
                    self.assertEqual(ddr_image[0x40000+payload_size:], bytes(-payload_size % 16))
                    self.assertEqual(manifest["image_bytes"], len(ddr_image))
                    self.assertEqual(manifest["image_words"] * 16, len(ddr_image))
                    self.assertEqual(manifest["rom_bytes"], len(rom_data))
                    self.assertEqual(manifest["rom_words"], len(words))
                    self.assertEqual(manifest["payload_word"], 0x40000 // 16)
                    self.assertEqual(manifest["image_sha256"], hashlib.sha256(ddr_image).hexdigest())
                    self.assertEqual(manifest["rom_file_sha256"], hashlib.sha256(rom_file).hexdigest())
                    header = (output / "checkpoint10_image.svh").read_text()
                    for macro, field in (("IMAGE_WORDS", "image_words"), ("ROM_WORDS", "rom_words"),
                                         ("FIRMWARE_WORDS", "firmware_words"), ("PAYLOAD_WORD", "payload_word")):
                        self.assertIn(f"`define CHECKPOINT10_{macro} {manifest[field]}\n", header)

    def test_invalid_sizes(self):
        for firmware_size, payload_size in ((0, 1), (0x40000, 1), (1, 0), (1, 0x10000)):
            with self.subTest(firmware_size=firmware_size, payload_size=payload_size):
                with tempfile.TemporaryDirectory() as directory:
                    result = self.pack(directory, bytes(firmware_size), bytes(payload_size))
                    self.assertNotEqual(result.returncode, 0)
                    self.assertFalse((Path(directory) / "output/checkpoint10_image.mem").exists())


if __name__ == "__main__":
    unittest.main()
