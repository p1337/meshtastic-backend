#!/usr/bin/env python3
"""Read-only, hash-pinned literal probe. This sends no SIM/modem commands.

Usage: python3 sim-toolkit-probe.py /path/to/research_sources
Firmware acquisition/hashes are described in IPHONE15PM_NATIVE_LORA_RESEARCH.md.
Offsets in the JSON are file-byte offsets, never register or function addresses.
"""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile

CASES = [
    ("baseline-apps", "mav23_release/apps.mbn", "aadb8af740b387997d4b4aa4e07d966da66d01f2f5343cb96d1ff486489c3794"),
    ("current-apps", None, "0ddbde8e266e258bf2883c9c9bd2d70d994199a3e5a3d7efc8d46b7c854111f3"),
    ("baseline-dsp", "mav23_release/qdsp6sw.mbn", "80726034dbdb544ac5a593c46aedba6bccd30a9870ded8ee7ea9622f2c197e12"),
    ("current-dsp", "apple_current/qdsp6sw.mbn", "8973152eaf1cdd59c72001d25810b811a2f0e3aaf1f8c2d1b7899f8c7aae1269"),
]
NEEDLES = [b"RUN AT CMD", b"RUN AT COMMAND", b"TERMINAL PROFILE", b"qmi_cati_get_terminal_profile"]


def inspect(root: Path) -> list[dict]:
    results = []
    for name, path, expected in CASES:
        if path is None:
            with zipfile.ZipFile(root / "apple_current/Mav23-4.02.04.Release.bbfw") as archive:
                names = [n for n in archive.namelist() if Path(n).name == "apps.mbn"]
                if len(names) != 1:
                    raise ValueError("Expected exactly one current apps.mbn")
                data = archive.read(names[0])
        else:
            data = (root / path).read_bytes()
        digest = hashlib.sha256(data).hexdigest()
        if digest != expected:
            raise ValueError(f"Unexpected firmware hash for {name}: {digest}")
        hits = {}
        for needle in NEEDLES:
            offsets = []
            start = 0
            while (offset := data.find(needle, start)) >= 0:
                offsets.append(offset)
                start = offset + len(needle)
            hits[needle.decode("ascii")] = offsets
        results.append({"image": name, "sha256": digest, "bytes": len(data), "literal_offsets": hits})
    return results


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("research_sources", type=Path)
    args = parser.parse_args()
    print(json.dumps(inspect(args.research_sources), indent=2))
