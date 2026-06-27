"""Dependency-free 1024x1024 Quorum mark PNG (ascending-bars / council).

Mirrors apps/desktop/lib/ui/terminal_screen.dart `_BarsMarkPainter`: three rounded
bars (blue / teal / green) on the QC.bg field. No Pillow required — raw RGBA
scanlines + zlib + PNG chunks from the Python stdlib only.

Usage:
    .venv/Scripts/python.exe <this> <output_png_path>
"""
import struct
import sys
import zlib

S = 1024
BG = (0x0A, 0x0C, 0x10, 0xFF)  # QC.bg #0A0C10
BARS = [  # (x_frac, top_height_frac, color) — from _BarsMarkPainter._bars
    (0.05, 0.35, (0x3D, 0x7D, 0xFF)),
    (0.38, 0.55, (0x36, 0xA6, 0xC6)),
    (0.71, 0.95, (0x2B, 0xC5, 0x7E)),
]
PAD = 0.19            # inset so the mark reads as an app icon (~62% of canvas)
inner = 1.0 - 2 * PAD
W = S * 0.22 * inner  # bar width (painter uses 0.22 of mark width)
R = int(S * 0.012)    # top-corner radius in px

rects = []
for xf, hf, col in BARS:
    x0 = PAD * S + xf * inner * S
    h = hf * inner * S
    y0 = PAD * S + (inner * S - h)  # bottom-aligned within inner box
    rects.append((int(x0), int(y0), int(x0 + W), int(y0 + h), col))


def in_rounded(px, py, x0, y0, x1, y1, r):
    if not (x0 <= px < x1 and y0 <= py < y1):
        return False
    if px < x0 + r and py < y0 + r:  # round top-left
        dx, dy = (x0 + r) - px, (y0 + r) - py
        return dx * dx + dy * dy <= r * r
    if px >= x1 - r and py < y0 + r:  # round top-right
        dx, dy = px - (x1 - r - 1), (y0 + r) - py
        return dx * dx + dy * dy <= r * r
    return True


raw = bytearray()
for y in range(S):
    raw.append(0)  # filter type 0
    for x in range(S):
        px = BG
        for (x0, y0, x1, y1, col) in rects:
            if in_rounded(x, y, x0, y0, x1, y1, R):
                px = (col[0], col[1], col[2], 0xFF)
                break
        raw.extend(px)


def chunk(tag, data):
    return (struct.pack(">I", len(data)) + tag + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))


ihdr = struct.pack(">IIBBBBB", S, S, 8, 6, 0, 0, 0)  # 8-bit RGBA
png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
       + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b""))
out = sys.argv[1]
with open(out, "wb") as f:
    f.write(png)
print("wrote", len(png), "bytes ->", out)
