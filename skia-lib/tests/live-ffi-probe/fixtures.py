"""Deterministic input only. These are not evidence of native Skia execution."""
from __future__ import annotations
from pathlib import Path
import binascii
import struct
import zlib

WIDTH, HEIGHT = 32, 24
COLORS = ((51, 102, 153, 255), (220, 40, 60, 255),
          (30, 190, 80, 255), (230, 190, 40, 255))


def rgba() -> bytes:
    return bytes(v for y in range(HEIGHT) for x in range(WIDTH)
                 for v in COLORS[(2 if y >= HEIGHT//2 else 0) + (1 if x >= WIDTH//2 else 0)])


def payload() -> bytes:
    return bytes((i * 37 + i // 251) % 256 for i in range(200003))


def png() -> bytes:
    def chunk(name: bytes, data: bytes) -> bytes:
        return (struct.pack('>I', len(data)) + name + data
                + struct.pack('>I', binascii.crc32(name + data) & 0xffffffff))
    pixels = rgba()
    raw = b''.join(b'\0' + pixels[y*WIDTH*4:(y+1)*WIDTH*4] for y in range(HEIGHT))
    # Use uncompressed DEFLATE to require multiple delayed producer writes.
    return (b'\x89PNG\r\n\x1a\n'
            + chunk(b'IHDR', struct.pack('>IIBBBBB', WIDTH, HEIGHT, 8, 6, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(raw, 0)) + chunk(b'IEND', b''))


def write(directory: Path) -> None:
    directory.mkdir(parents=True, exist_ok=False)
    for name, data in {'reference.rgba': rgba(), 'reference.png': png(), 'payload.bin': payload()}.items():
        (directory / name).write_bytes(data)
