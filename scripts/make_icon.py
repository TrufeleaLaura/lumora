"""Generates the 1024x1024 Lumora app icon (opaque RGB PNG) with no third-party packages.

Design ("Darkroom"): warm black, a crisp cream lens ring with a fine inner ring, four lens-scale
ticks and one safelight-orange dot set into the ring. Flat, no glow.
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


def coverage(distance, half_width):
    """Anti-aliased coverage of a band of half-width `half_width` (in unit coords)."""
    return max(0.0, min(1.0, (half_width - abs(distance)) * SIZE + 0.5))


def main(out_path):
    ink_center = (0.085, 0.077, 0.070)
    ink_edge = (0.043, 0.039, 0.035)
    cream = (0.929, 0.902, 0.855)
    safelight = (0.878, 0.376, 0.227)
    ring_radius = 0.30
    dot = (0.30 * math.cos(math.radians(45)), -0.30 * math.sin(math.radians(45)))
    dot_radius = 0.036
    rows = []
    for py in range(SIZE):
        row = bytearray()
        y = (py + 0.5) / SIZE - 0.5
        for px in range(SIZE):
            x = (px + 0.5) / SIZE - 0.5
            r = math.hypot(x, y)
            col = mix(ink_center, ink_edge, min(1.0, r / 0.72))
            background = col
            # Outer lens ring and a fine inner ring.
            col = mix(col, cream, coverage(r - ring_radius, 0.0055))
            col = mix(col, cream, 0.38 * coverage(r - 0.232, 0.0018))
            # Lens-scale ticks at the four cardinal points, just outside the ring.
            for tx, ty in ((0, -1), (1, 0), (0, 1), (-1, 0)):
                along = x * tx + y * ty
                across = abs(x * ty - y * tx)
                if 0.33 <= along <= 0.362:
                    col = mix(col, cream, 0.55 * coverage(across, 0.0022))
            # Safelight dot set into the ring, with a thin gap of background around it.
            dd = math.hypot(x - dot[0], y - dot[1])
            col = mix(col, background, coverage(dd - (dot_radius + 0.007), 0.0075) if dd > dot_radius else 0.0)
            col = mix(col, safelight, max(0.0, min(1.0, (dot_radius - dd) * SIZE + 0.5)))
            row.extend(int(max(0, min(255, round(255 * c)))) for c in col)
        rows.append(row)
    with open(out_path, "wb") as f:
        f.write(png_bytes(SIZE, SIZE, rows))


if __name__ == "__main__":
    main(sys.argv[1])
