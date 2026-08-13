#!/usr/bin/env python3
"""Trace JWE3's SM60/SM65 selection without modifying the executable."""

from __future__ import annotations

import argparse
import struct
from pathlib import Path

import capstone
import pefile


DEFAULT_EXE = Path(
    r"C:\Program Files (x86)\Steam\steamapps\common\Jurassic World Evolution 3\JWE3.exe"
)
DEFAULT_TARGET = 0x141CA71D0


def executable_sections(pe: pefile.PE):
    for section in pe.sections:
        if section.Characteristics & 0x20000000:
            yield section


def containing_runtime_function(pe: pefile.PE, rva: int):
    for entry in getattr(pe, "DIRECTORY_ENTRY_EXCEPTION", []):
        begin = entry.struct.BeginAddress
        end = entry.struct.EndAddress
        if begin <= rva < end:
            return begin, end
    return None


def direct_rel32_xrefs(pe: pefile.PE, target_va: int):
    image_base = pe.OPTIONAL_HEADER.ImageBase
    results = []
    for section in executable_sections(pe):
        data = section.get_data()
        section_va = image_base + section.VirtualAddress
        for index, opcode in enumerate(data[:-4]):
            if opcode not in (0xE8, 0xE9):
                continue
            displacement = struct.unpack_from("<i", data, index + 1)[0]
            destination = section_va + index + 5 + displacement
            if destination == target_va:
                results.append((section_va + index, opcode))
    return results


def bytes_for_va(pe: pefile.PE, start_va: int, end_va: int) -> bytes:
    image_base = pe.OPTIONAL_HEADER.ImageBase
    start_rva = start_va - image_base
    return pe.get_data(start_rva, end_va - start_va)


def read_c_string(pe: pefile.PE, va: int, limit: int = 512) -> str | None:
    image_base = pe.OPTIONAL_HEADER.ImageBase
    try:
        raw = pe.get_data(va - image_base, limit)
    except pefile.PEFormatError:
        return None
    raw = raw.split(b"\0", 1)[0]
    if not raw:
        return ""
    try:
        value = raw.decode("utf-8")
    except UnicodeDecodeError:
        return None
    if any(ord(char) < 0x20 and char not in "\t\r\n" for char in value):
        return None
    return value


def dereferenced_strings(pe: pefile.PE, va: int, count: int = 8, stride: int = 16):
    image_base = pe.OPTIONAL_HEADER.ImageBase
    values = []
    for index in range(count):
        raw = pe.get_data(va - image_base + index * stride, 8)
        if len(raw) != 8:
            break
        pointer = struct.unpack("<Q", raw)[0]
        if not pointer:
            values.append((index, pointer, ""))
            continue
        value = read_c_string(pe, pointer)
        if value is not None:
            values.append((index, pointer, value))
    return values


def nearby_call_metadata(pe: pefile.PE, call_va: int, window: int = 160):
    """Decode the common argument setup immediately before a shader-load call."""
    start_va = call_va - window
    data = bytes_for_va(pe, start_va, call_va)
    metadata: dict[str, object] = {}

    # lea r8/r9, [rip+disp32]
    for key, prefix in (("r8", b"\x4c\x8d\x05"), ("r9", b"\x4c\x8d\x0d")):
        position = data.rfind(prefix)
        if position >= 0 and position + 7 <= len(data):
            displacement = struct.unpack_from("<i", data, position + 3)[0]
            instruction_va = start_va + position
            value_va = instruction_va + 7 + displacement
            metadata[key] = (value_va, read_c_string(pe, value_va))

    # Sixth argument: byte stored at [rsp+28h]. Keep the exact encoding/source.
    patterns = (
        (b"\xc6\x44\x24\x28", 5),
        (b"\x40\x88\x6c\x24\x28", 5),  # bpl
        (b"\x40\x88\x7c\x24\x28", 5),  # dil
        (b"\x44\x88\x64\x24\x28", 5),  # r12b
        (b"\x44\x88\x6c\x24\x28", 5),  # r13b
        (b"\x44\x88\x74\x24\x28", 5),  # r14b
        (b"\x44\x88\x7c\x24\x28", 5),  # r15b
    )
    found = []
    for prefix, length in patterns:
        position = data.rfind(prefix)
        if position >= 0:
            found.append((position, data[position : position + length]))
    if found:
        position, encoded = max(found)
        if encoded[:4] == b"\xc6\x44\x24\x28":
            metadata["sm65_arg"] = f"constant {encoded[4]}"
        else:
            register_names = {
                b"\x40\x88\x6c\x24\x28": "bpl",
                b"\x40\x88\x7c\x24\x28": "dil",
                b"\x44\x88\x64\x24\x28": "r12b",
                b"\x44\x88\x6c\x24\x28": "r13b",
                b"\x44\x88\x74\x24\x28": "r14b",
                b"\x44\x88\x7c\x24\x28": "r15b",
            }
            metadata["sm65_arg"] = register_names.get(encoded, encoded.hex(" "))
        metadata["sm65_store_va"] = start_va + position
    return metadata


def disassemble(md: capstone.Cs, pe: pefile.PE, start_va: int, end_va: int):
    code = bytes_for_va(pe, start_va, end_va)
    return list(md.disasm(code, start_va))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("exe", nargs="?", type=Path, default=DEFAULT_EXE)
    parser.add_argument("--target", type=lambda value: int(value, 0), default=DEFAULT_TARGET)
    parser.add_argument("--context", type=int, default=48)
    parser.add_argument("--match", help="Only show calls whose nearby strings contain this text")
    parser.add_argument("--call", type=lambda value: int(value, 0), help="Only show one call VA")
    parser.add_argument(
        "--mesh-capable",
        action="store_true",
        help="Only show calls whose platform table contains Win64_SM65",
    )
    parser.add_argument("--full", action="store_true", help="Print disassembly around every match")
    args = parser.parse_args()

    pe = pefile.PE(str(args.exe), fast_load=False)
    pe.parse_data_directories(
        directories=[pefile.DIRECTORY_ENTRY["IMAGE_DIRECTORY_ENTRY_EXCEPTION"]]
    )
    image_base = pe.OPTIONAL_HEADER.ImageBase
    md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
    md.detail = True

    target_rva = args.target - image_base
    target_function = containing_runtime_function(pe, target_rva)
    print(f"image_base=0x{image_base:x}")
    print(f"target=0x{args.target:x}")
    if target_function:
        begin, end = target_function
        print(
            f"target_function=0x{image_base + begin:x}-0x{image_base + end:x} "
            f"({end - begin} bytes)"
        )
    else:
        print("target_function=<not present in exception directory>")

    xrefs = direct_rel32_xrefs(pe, args.target)
    print(f"direct_rel32_xrefs={len(xrefs)}")
    for call_va, opcode in xrefs:
        if args.call is not None and call_va != args.call:
            continue
        metadata = nearby_call_metadata(pe, call_va)
        platform_values = []
        if "r8" in metadata:
            platform_values = dereferenced_strings(pe, metadata["r8"][0])
        if args.mesh_capable and not any(value == "Win64_SM65" for _, _, value in platform_values):
            continue
        string_values = [
            value[1]
            for key, value in metadata.items()
            if key in ("r8", "r9") and isinstance(value, tuple) and value[1] is not None
        ]
        if args.match and not any(args.match.casefold() in value.casefold() for value in string_values):
            continue
        caller = containing_runtime_function(pe, call_va - image_base)
        instruction = "call" if opcode == 0xE8 else "jmp"
        if caller:
            begin, end = caller
            caller_begin = image_base + begin
            caller_end = image_base + end
            print(f"\n{instruction} 0x{call_va:x}, caller=0x{caller_begin:x}-0x{caller_end:x}")
            context_begin = max(caller_begin, call_va - args.context)
            context_end = min(caller_end, call_va + 5 + args.context)
        else:
            print(f"\n{instruction} 0x{call_va:x}, caller=<unknown>")
            context_begin = call_va - args.context
            context_end = call_va + 5 + args.context

        for key in ("r8", "r9"):
            if key in metadata:
                value_va, value = metadata[key]
                print(f"  {key}=0x{value_va:x} {value!r}")
                for index, pointer, pointed_value in dereferenced_strings(pe, value_va):
                    print(f"    [{index}]=0x{pointer:x} {pointed_value!r}")
        print(
            f"  sm65_arg={metadata.get('sm65_arg', '<not decoded>')} "
            f"store={metadata.get('sm65_store_va', '<unknown>')}"
        )
        if args.full:
            for insn in disassemble(md, pe, context_begin, context_end):
                marker = ">" if insn.address == call_va else " "
                encoded = insn.bytes.hex(" ")
                print(
                    f"{marker} 0x{insn.address:011x}: {encoded:<30} "
                    f"{insn.mnemonic:<8} {insn.op_str}"
                )

    if target_function and args.full:
        begin, end = target_function
        print("\nTARGET FUNCTION")
        for insn in disassemble(md, pe, image_base + begin, image_base + end):
            encoded = insn.bytes.hex(" ")
            print(
                f"  0x{insn.address:011x}: {encoded:<30} "
                f"{insn.mnemonic:<8} {insn.op_str}"
            )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
