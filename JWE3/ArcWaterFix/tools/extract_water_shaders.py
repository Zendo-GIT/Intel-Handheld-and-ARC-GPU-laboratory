#!/usr/bin/env python3
"""Extrait les conteneurs DXIL liés à l'eau de l'archive de shaders JWE3.

Le fichier source est uniquement lu. L'archive JWE3 est un flux DEFLATE brut
précédé d'un en-tête de 16 octets ; son contenu renferme des conteneurs DXBC
nommés pour les chemins SM6.0 et SM6.5.
"""

from __future__ import annotations

import argparse
import json
import re
import struct
import zlib
from pathlib import Path


NAME_PATTERN = re.compile(rb"[A-Za-z0-9_]+_Win64_SM(?:60|65)")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("archive", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--name-contains", default="Water_")
    return parser.parse_args()


def valid_dxbc(data: bytes, offset: int) -> tuple[int, int] | None:
    if offset + 32 > len(data) or data[offset : offset + 4] != b"DXBC":
        return None
    total_size = struct.unpack_from("<I", data, offset + 24)[0]
    chunk_count = struct.unpack_from("<I", data, offset + 28)[0]
    if total_size < 32 + 4 * chunk_count or offset + total_size > len(data):
        return None
    for index in range(chunk_count):
        relative = struct.unpack_from("<I", data, offset + 32 + 4 * index)[0]
        if relative + 8 > total_size:
            return None
        chunk_size = struct.unpack_from("<I", data, offset + relative + 4)[0]
        if relative + 8 + chunk_size > total_size:
            return None
    return total_size, chunk_count


def shader_name(record: bytes, name_offset: int) -> str | None:
    matches = list(NAME_PATTERN.finditer(record[name_offset:]))
    if not matches:
        return None
    return matches[0].group().decode("ascii")


def main() -> int:
    args = parse_args()
    packed = args.archive.read_bytes()
    if len(packed) < 17 or b"talfed" not in packed[:16]:
        raise ValueError("En-tête JWE3 'talfed' absent")
    unpacked = zlib.decompress(packed[16:], -15)

    args.output.mkdir(parents=True, exist_ok=True)
    manifest: list[dict[str, int | str]] = []
    cursor = 0
    record_index = 0
    while cursor + 16 <= len(unpacked):
        version_low, version_high, magic, record_size, payload_size = (
            struct.unpack_from("<2B6s2I", unpacked, cursor)
        )
        if record_size < 16 or cursor + record_size > len(unpacked):
            break
        if magic == b"ahsd3f" and record_size >= 64:
            dxbc_offset = cursor + 64
            parsed = valid_dxbc(unpacked, dxbc_offset)
            if parsed is not None:
                size, chunks = parsed
                name = shader_name(
                    unpacked[cursor : cursor + record_size], payload_size
                )
                if name and args.name_contains.lower() in name.lower():
                    filename = f"{name}__{dxbc_offset:08x}.dxil"
                    (args.output / filename).write_bytes(
                        unpacked[dxbc_offset : dxbc_offset + size]
                    )
                    manifest.append(
                        {
                            "name": name,
                            "record_index": record_index,
                            "record_offset": cursor,
                            "record_size": record_size,
                            "payload_size": payload_size,
                            "offset": dxbc_offset,
                            "size": size,
                            "chunks": chunks,
                            "file": filename,
                            "record_version": f"{version_high}.{version_low}",
                        }
                    )
        cursor += record_size
        record_index += 1

    (args.output / "manifest.json").write_text(
        json.dumps(manifest, indent=2), encoding="utf-8"
    )
    print(f"{len(manifest)} shaders extraits dans {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
