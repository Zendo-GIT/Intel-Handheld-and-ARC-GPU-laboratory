#!/usr/bin/env python3
"""Find direct RIP-relative and pointer references in a 64-bit PE image."""

from __future__ import annotations

import argparse
import struct
from pathlib import Path

import capstone
import pefile


DEFAULT_EXE = Path(
    r"C:\Program Files (x86)\Steam\steamapps\common\Jurassic World Evolution 3\JWE3.exe"
)


def section_for_offset(pe: pefile.PE, offset: int):
    for section in pe.sections:
        start = section.PointerToRawData
        end = start + section.SizeOfRawData
        if start <= offset < end:
            return section
    return None


def va_for_offset(pe: pefile.PE, offset: int) -> int | None:
    section = section_for_offset(pe, offset)
    if section is None:
        return None
    return (
        pe.OPTIONAL_HEADER.ImageBase
        + section.VirtualAddress
        + offset
        - section.PointerToRawData
    )


def pointer_refs(pe: pefile.PE, target_va: int):
    needle = struct.pack("<Q", target_va)
    results = []
    position = 0
    while True:
        position = pe.__data__.find(needle, position)
        if position < 0:
            return results
        va = va_for_offset(pe, position)
        if va is not None:
            results.append(va)
        position += 1


def rip_refs(pe: pefile.PE, target_vas: set[int]):
    """Find common x64 RIP-relative LEA/MOV references to exact VAs."""
    image_base = pe.OPTIONAL_HEADER.ImageBase
    results = []
    for section in pe.sections:
        if not section.Characteristics & 0x20000000:
            continue
        data = section.get_data()
        section_va = image_base + section.VirtualAddress
        for opcode in (0x8D, 0x8B, 0x89):
            needle = bytes((opcode,))
            position = 0
            while True:
                position = data.find(needle, position)
                if position < 0:
                    break
                if position + 6 <= len(data):
                    modrm = data[position + 1]
                    if modrm & 0xC7 == 0x05:
                        displacement = struct.unpack_from("<i", data, position + 2)[0]
                        destination = section_va + position + 6 + displacement
                        if destination in target_vas:
                            start = position
                            if position and 0x40 <= data[position - 1] <= 0x4F:
                                start -= 1
                            results.append((section_va + start, destination))
                position += 1
    return sorted(set(results))


def runtime_function(pe: pefile.PE, va: int):
    rva = va - pe.OPTIONAL_HEADER.ImageBase
    for entry in getattr(pe, "DIRECTORY_ENTRY_EXCEPTION", []):
        if entry.struct.BeginAddress <= rva < entry.struct.EndAddress:
            base = pe.OPTIONAL_HEADER.ImageBase
            return base + entry.struct.BeginAddress, base + entry.struct.EndAddress
    return None


def disassemble_at(pe: pefile.PE, va: int):
    md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
    code = pe.get_data(va - pe.OPTIONAL_HEADER.ImageBase, 15)
    return next(md.disasm(code, va), None)


def disassemble_context(pe: pefile.PE, function: tuple[int, int], focus: int, context: int):
    begin, end = function
    md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
    code = pe.get_data(begin - pe.OPTIONAL_HEADER.ImageBase, end - begin)
    for insn in md.disasm(code, begin):
        if focus - context <= insn.address <= focus + context:
            marker = ">" if insn.address == focus else " "
            print(
                f"   {marker} 0x{insn.address:x}: {insn.bytes.hex(' '):<30} "
                f"{insn.mnemonic:<8} {insn.op_str}"
            )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("exe", nargs="?", type=Path, default=DEFAULT_EXE)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--string", help="Find an exact ASCII string first")
    group.add_argument("--target", type=lambda value: int(value, 0))
    parser.add_argument("--depth", type=int, default=2)
    parser.add_argument("--context", type=int, default=0)
    args = parser.parse_args()

    pe = pefile.PE(str(args.exe), fast_load=False)
    pe.parse_data_directories(
        directories=[pefile.DIRECTORY_ENTRY["IMAGE_DIRECTORY_ENTRY_EXCEPTION"]]
    )
    if args.string is not None:
        offset = pe.__data__.find(args.string.encode("ascii"))
        if offset < 0:
            raise SystemExit("String not found")
        target = va_for_offset(pe, offset)
        if target is None:
            raise SystemExit("String is not inside a mapped section")
        print(f"string={args.string!r} offset=0x{offset:x} va=0x{target:x}")
    else:
        target = args.target

    frontier = {target}
    visited = set()
    all_nodes = {target}
    for depth in range(args.depth + 1):
        frontier -= visited
        if not frontier:
            break
        visited |= frontier
        print(f"\nDEPTH {depth}: " + ", ".join(f"0x{value:x}" for value in sorted(frontier)))

        for source, destination in rip_refs(pe, frontier):
            function = runtime_function(pe, source)
            insn = disassemble_at(pe, source)
            rendered = f"{insn.mnemonic} {insn.op_str}" if insn else "<decode failed>"
            where = (
                f" function=0x{function[0]:x}-0x{function[1]:x}" if function else ""
            )
            print(f"  code 0x{source:x} -> 0x{destination:x}: {rendered}{where}")
            if args.context and function:
                disassemble_context(pe, function, source, args.context)

        next_frontier = set()
        for destination in frontier:
            for source in pointer_refs(pe, destination):
                print(f"  ptr  0x{source:x} -> 0x{destination:x}")
                next_frontier.add(source)
        all_nodes |= next_frontier
        frontier = next_frontier
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
