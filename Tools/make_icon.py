#!/usr/bin/env python3
"""
Draws the Cadence application icon and packages it as an .icns file.

Written against nothing but the Python standard library on purpose: the icon is
part of the source, it rebuilds identically on any machine, and the project keeps
its promise of needing no paid or third-party tooling. Shapes are drawn from signed
distance fields so the edges are antialiased without supersampling.

    python3 Tools/make_icon.py [output-directory]

Produces Cadence.icns, a Cadence.iconset folder and icon-512.png.
"""

import math
import os
import struct
import sys
import zlib

# ── Palette ───────────────────────────────────────────────────────────────────
# The same sage green as the application's accent, deepened for a filled tile.
TOP = (0x3C, 0x86, 0x6C)
BOTTOM = (0x17, 0x40, 0x33)
CREAM = (0xF6, 0xF3, 0xEA)
MINT = (0x8F, 0xDD, 0xB8)


def mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def smoothstep(edge0, edge1, x):
    if edge1 == edge0:
        return 0.0 if x < edge0 else 1.0
    t = (x - edge0) / (edge1 - edge0)
    return max(0.0, min(1.0, t))


def squircle_distance(x, y, half, exponent=5.0):
    """Signed distance to Apple's rounded-square silhouette (a superellipse)."""
    ax, ay = abs(x) / half, abs(y) / half
    if ax == 0 and ay == 0:
        return -half
    r = (ax ** exponent + ay ** exponent) ** (1.0 / exponent)
    return (r - 1.0) * half


def rounded_rect_distance(x, y, half_w, half_h, radius):
    dx = abs(x) - (half_w - radius)
    dy = abs(y) - (half_h - radius)
    outside = math.hypot(max(dx, 0.0), max(dy, 0.0))
    inside = min(max(dx, dy), 0.0)
    return outside + inside - radius


def over(dst, src, alpha):
    """Source-over compositing on straight RGB with an opaque destination."""
    return tuple(src[i] * alpha + dst[i] * (1 - alpha) for i in range(3))


def render(size):
    """Renders the icon at `size` pixels square, returning RGBA bytes."""
    scale = size / 1024.0
    px = 1.0 / scale                     # one output pixel, in design units
    feather = max(px * 0.8, 0.35)

    tile_half = 416.0                    # 832 pt body inside the 1024 pt canvas
    bar_half_height = 42.0 * (1.0 if size >= 64 else 1.12)
    bar_radius = bar_half_height
    rail_x = -300.0
    bars = [
        (-168.0, 236.0, CREAM, 0.93),    # (centre y, half width, colour, alpha)
        (0.0, 168.0, MINT, 1.00),
        (168.0, 202.0, CREAM, 0.72),
    ]

    out = bytearray(size * size * 4)
    index = 0
    for row in range(size):
        y = (row + 0.5) * px - 512.0
        for column in range(size):
            x = (column + 0.5) * px - 512.0

            tile = squircle_distance(x, y, tile_half)
            coverage = 1.0 - smoothstep(-feather, feather, tile)
            if coverage <= 0.0:
                index += 4
                continue

            # Vertical gradient, with a soft light gathered towards the top left.
            colour = mix(TOP, BOTTOM, smoothstep(-tile_half, tile_half, y))
            glow = 1.0 - smoothstep(0.0, tile_half * 1.5, math.hypot(x + 180, y + 260))
            colour = mix(colour, (0xFF, 0xFF, 0xFF), glow * 0.10)

            # A hairline of light along the top edge, the way macOS tiles catch it.
            edge = abs(tile + 6.0) - 3.0
            if y < 0:
                colour = over(colour, (0xFF, 0xFF, 0xFF),
                              (1.0 - smoothstep(-feather, feather, edge)) * 0.16 * (1.0 - smoothstep(-tile_half, 0.0, y)))

            # The day rail: a faint vertical line the sessions hang from.
            rail = rounded_rect_distance(x - rail_x, y, 9.0, 252.0, 9.0)
            colour = over(colour, CREAM, (1.0 - smoothstep(-feather, feather, rail)) * 0.38)

            # Three sessions, the middle one being the current session.
            for centre_y, half_width, bar_colour, alpha in bars:
                bar = rounded_rect_distance(
                    x - (rail_x + 78.0 + half_width), y - centre_y,
                    half_width, bar_half_height, bar_radius,
                )
                colour = over(colour, bar_colour, (1.0 - smoothstep(-feather, feather, bar)) * alpha)

            # The "now" marker sitting on the rail beside the current session.
            marker = math.hypot(x - rail_x, y) - 30.0
            colour = over(colour, MINT, 1.0 - smoothstep(-feather, feather, marker))

            out[index] = int(max(0, min(255, colour[0])) + 0.5)
            out[index + 1] = int(max(0, min(255, colour[1])) + 0.5)
            out[index + 2] = int(max(0, min(255, colour[2])) + 0.5)
            out[index + 3] = int(coverage * 255 + 0.5)
            index += 4
    return bytes(out)


def write_png(path, size, rgba):
    def chunk(kind, payload):
        return (struct.pack(">I", len(payload)) + kind + payload
                + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF))

    stride = size * 4
    raw = b"".join(b"\x00" + rgba[row * stride:(row + 1) * stride] for row in range(size))
    data = (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9))
            + chunk(b"IEND", b""))
    with open(path, "wb") as handle:
        handle.write(data)
    return data


# icns chunk type → pixel size. These are the entries iconutil itself emits.
ICNS_ENTRIES = [
    (b"icp4", 16), (b"icp5", 32), (b"ic11", 32), (b"ic12", 64),
    (b"ic07", 128), (b"ic13", 256), (b"ic08", 256), (b"ic14", 512),
    (b"ic09", 512), (b"ic10", 1024),
]

# Filenames Apple's iconutil expects inside an .iconset folder.
ICONSET_ENTRIES = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]


def main():
    destination = sys.argv[1] if len(sys.argv) > 1 else "Resources"
    os.makedirs(destination, exist_ok=True)
    iconset = os.path.join(destination, "Cadence.iconset")
    os.makedirs(iconset, exist_ok=True)

    rendered = {}
    for size in sorted({size for _, size in ICNS_ENTRIES} | {size for _, size in ICONSET_ENTRIES}):
        print(f"  rendering {size}×{size}", flush=True)
        rendered[size] = render(size)

    png_bytes = {}
    for filename, size in ICONSET_ENTRIES:
        png_bytes[size] = write_png(os.path.join(iconset, filename), size, rendered[size])

    body = b"".join(
        kind + struct.pack(">I", len(png_bytes[size]) + 8) + png_bytes[size]
        for kind, size in ICNS_ENTRIES
    )
    icns = b"icns" + struct.pack(">I", len(body) + 8) + body
    icns_path = os.path.join(destination, "Cadence.icns")
    with open(icns_path, "wb") as handle:
        handle.write(icns)

    write_png(os.path.join(destination, "icon-512.png"), 512, rendered[512])
    print(f"wrote {icns_path} ({len(icns):,} bytes) and {iconset}")


if __name__ == "__main__":
    main()
