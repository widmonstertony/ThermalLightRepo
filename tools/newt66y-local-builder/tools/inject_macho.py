#!/usr/bin/env python3
"""Add an LC_LOAD_DYLIB command to a thin little-endian Mach-O 64 binary."""

from __future__ import annotations

import os
import shutil
import struct
import sys
from pathlib import Path


MH_MAGIC_64 = 0xFEEDFACF
LC_SEGMENT_64 = 0x19
LC_LOAD_DYLIB = 0x0C
HEADER_SIZE_64 = 32
SECTION_SIZE_64 = 80


def align(value: int, boundary: int) -> int:
    return (value + boundary - 1) & ~(boundary - 1)


def read_c_string(data: bytearray, start: int, limit: int) -> str:
    end = data.find(b"\0", start, limit)
    if end < 0:
        end = limit
    return data[start:end].decode("utf-8", errors="replace")


def inject(input_path: Path, output_path: Path, dylib_path: str) -> None:
    data = bytearray(input_path.read_bytes())
    if len(data) < HEADER_SIZE_64:
        raise ValueError("input is too small to be a Mach-O binary")

    header = struct.unpack_from("<IiiIIIII", data, 0)
    magic, _, _, _, ncmds, sizeofcmds, _, _ = header
    if magic != MH_MAGIC_64:
        raise ValueError("only thin little-endian Mach-O 64 binaries are supported")

    command_offset = HEADER_SIZE_64
    first_section_offset: int | None = None
    existing_dylibs: list[str] = []

    for _ in range(ncmds):
        if command_offset + 8 > len(data):
            raise ValueError("truncated Mach-O load command")
        cmd, cmdsize = struct.unpack_from("<II", data, command_offset)
        if cmdsize < 8 or command_offset + cmdsize > len(data):
            raise ValueError("invalid Mach-O load command size")

        if cmd == LC_SEGMENT_64:
            if cmdsize < 72:
                raise ValueError("invalid LC_SEGMENT_64 command")
            nsects = struct.unpack_from("<I", data, command_offset + 64)[0]
            section_offset = command_offset + 72
            for _ in range(nsects):
                if section_offset + SECTION_SIZE_64 > command_offset + cmdsize:
                    raise ValueError("truncated Mach-O section table")
                file_offset = struct.unpack_from("<I", data, section_offset + 48)[0]
                if file_offset > 0:
                    first_section_offset = (
                        file_offset
                        if first_section_offset is None
                        else min(first_section_offset, file_offset)
                    )
                section_offset += SECTION_SIZE_64

        if cmd == LC_LOAD_DYLIB and cmdsize >= 24:
            name_offset = struct.unpack_from("<I", data, command_offset + 8)[0]
            if 0 < name_offset < cmdsize:
                existing_dylibs.append(
                    read_c_string(data, command_offset + name_offset, command_offset + cmdsize)
                )

        command_offset += cmdsize

    expected_command_end = HEADER_SIZE_64 + sizeofcmds
    if command_offset != expected_command_end:
        raise ValueError("Mach-O header load-command size is inconsistent")

    if dylib_path in existing_dylibs:
        shutil.copy2(input_path, output_path)
        print(f"already present: {dylib_path}")
        return

    encoded_path = dylib_path.encode("utf-8") + b"\0"
    cmdsize = align(24 + len(encoded_path), 8)
    command = struct.pack(
        "<IIIIII",
        LC_LOAD_DYLIB,
        cmdsize,
        24,
        2,
        0x00010000,
        0x00010000,
    ) + encoded_path
    command += b"\0" * (cmdsize - len(command))

    if first_section_offset is None:
        raise ValueError("could not locate the first Mach-O section")
    if expected_command_end + cmdsize > first_section_offset:
        available = first_section_offset - expected_command_end
        raise ValueError(
            f"not enough Mach-O header padding: need {cmdsize} bytes, have {available}"
        )

    data[expected_command_end:expected_command_end + cmdsize] = command
    struct.pack_into("<I", data, 16, ncmds + 1)
    struct.pack_into("<I", data, 20, sizeofcmds + cmdsize)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    temp_path = output_path.with_suffix(output_path.suffix + ".tmp")
    temp_path.write_bytes(data)
    os.chmod(temp_path, input_path.stat().st_mode)
    temp_path.replace(output_path)
    print(f"injected {dylib_path} into {output_path}")


def main() -> None:
    if len(sys.argv) != 4:
        raise SystemExit(f"usage: {sys.argv[0]} INPUT OUTPUT DYLIB_PATH")
    inject(Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3])


if __name__ == "__main__":
    main()
