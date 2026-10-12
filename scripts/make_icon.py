"""Generates the 1024x1024 Lumora app icon (opaque RGB PNG) with no third-party packages.

Design: deep plum radial background, a glowing gold-to-rose "aura" ring and a soft inner light.
Usage: python scripts/make_icon.py <output.png>
"""
import math
import struct
import sys
import zlib

SIZE = 1024


def lerp(a, b, t):
    return a + (b - a) * t


def mix(c1, c2, t):
    return tuple(lerp(a, b, t) for a, b in zip(c1, c2))


def png_bytes(width, height, rows):
    raw = b"".join(b"\x00" + bytes(row) for row in rows)

    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")


def main(out_path):
    bg_center = (0.13, 0.045, 0.17)
    bg_edge = (0.025, 0.018, 0.035)
    gold = (0.965, 0.757, 0.467)
    rose = (0.922, 0.435, 0.573)
    ring_radius = 0.30
    rows = []
    for py in range(SIZE):
        row = bytearray()
        y = (py + 0.5) / SIZE - 0.5
        for px in range(SIZE):
            x = (px + 0.5) / SIZE - 0.5
            r = math.hypot(x, y)
            # Background radial gradient.
            col = mix(bg_center, bg_edge, min(1.0, r / 0.72))
            # Ring color sweeps gold -> rose around the circle.
            angle = (math.atan2(y, x) + math.pi) / (2 * math.pi)
            ring_col = mix(gold, rose, 0.5 + 0.5 * math.sin(angle * 2 * math.pi - 0.9))
            d = (r - ring_radius)
            ring = 0.95 * math.exp(-(d / 0.016) ** 2)
            glow = 0.30 * math.exp(-(d / 0.075) ** 2)
            core = 0.07 * math.exp(-(r / 0.14) ** 2)
            col = tuple(c + rc * (ring + glow) + g * core for c, rc, g in zip(col, ring_col, gold))
            # Soft filmic clip that keeps the ring saturated.
            col = tuple(1.0 - math.exp(-1.5 * max(0.0, c)) for c in col)
            row.extend(int(max(0, min(255, round(255 * c)))) for c in col)
        rows.append(row)
    with open(out_path, "wb") as f:
        f.write(png_bytes(SIZE, SIZE, rows))


if __name__ == "__main__":
    main(sys.argv[1])
