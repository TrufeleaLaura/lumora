"""Generates the 1024x1024 Lumora app icon (opaque RGB PNG) with no third-party packages.

Design ("Aura"): deep plum radial background, a glowing lavender-rose-peach ring, a soft inner light
and a four-point sparkle on the ring.
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
    bg_center = (0.135, 0.075, 0.185)
    bg_edge = (0.035, 0.024, 0.045)
    lavender = (0.60, 0.46, 1.0)
    rose = (1.0, 0.40, 0.66)
    peach = (1.0, 0.62, 0.45)
    ring_radius = 0.30
    spark = (0.212, -0.212)  # upper right, on the ring
    rows = []
    for py in range(SIZE):
        row = bytearray()
        y = (py + 0.5) / SIZE - 0.5
        for px in range(SIZE):
            x = (px + 0.5) / SIZE - 0.5
            r = math.hypot(x, y)
            # Background radial gradient, slightly lifted toward the top-left.
            col = mix(bg_center, bg_edge, min(1.0, math.hypot(x + 0.08, y + 0.08) / 0.75))
            # Ring color sweeps lavender -> rose -> peach -> lavender around the circle.
            angle = (math.atan2(y, x) + math.pi) / (2 * math.pi)
            u = (angle * 3.0 + 0.4) % 3.0
            if u < 1.0:
                ring_col = mix(lavender, rose, u)
            elif u < 2.0:
                ring_col = mix(rose, peach, u - 1.0)
            else:
                ring_col = mix(peach, lavender, u - 2.0)
            d = (r - ring_radius)
            ring = 0.75 * math.exp(-(d / 0.015) ** 2)
            glow = 0.34 * math.exp(-(d / 0.08) ** 2)
            core = 0.08 * math.exp(-(r / 0.15) ** 2)
            col = tuple(c + rc * (ring + glow) + l * core for c, rc, l in zip(col, ring_col, lavender))
            # Four-point sparkle.
            dx, dy = abs(x - spark[0]), abs(y - spark[1])
            rs = math.hypot(dx, dy)
            star = math.exp(-math.sqrt(dx * dy) / 0.0065) * max(0.0, 1.0 - rs / 0.105) ** 1.5
            star += 0.8 * math.exp(-(rs / 0.018) ** 2) + 0.25 * math.exp(-(rs / 0.06) ** 2)
            col = tuple(c + star * w for c, w in zip(col, (1.0, 0.96, 0.98)))
            # Soft filmic clip that keeps the ring saturated.
            col = tuple(1.0 - math.exp(-1.5 * max(0.0, c)) for c in col)
            row.extend(int(max(0, min(255, round(255 * c)))) for c in col)
        rows.append(row)
    with open(out_path, "wb") as f:
        f.write(png_bytes(SIZE, SIZE, rows))


if __name__ == "__main__":
    main(sys.argv[1])
