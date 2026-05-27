#!/usr/bin/env python3
"""
Generate 240×320 RGB565 splash frames for blue-merle fb0 display.

Output: ../files/usr/share/blue-merle/screens/*.rgb565  (bundled in IPK)
        previews/*.png                                   (dev reference only)

Usage: python3 generate.py
"""

import os
import struct
from PIL import Image, ImageDraw, ImageFont

W, H = 240, 320

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
OUT_DIR     = os.path.join(SCRIPT_DIR, "../files/usr/share/blue-merle/screens")
PREVIEW_DIR = os.path.join(SCRIPT_DIR, "previews")

os.makedirs(OUT_DIR,     exist_ok=True)
os.makedirs(PREVIEW_DIR, exist_ok=True)

# ── Color palette ─────────────────────────────────────────────────────────────
BG      = (15,  23,  42)   # #0f172a  dark navy background
ACCENT  = (59,  130, 246)  # #3b82f6  blue accent bars
BRAND   = (148, 163, 184)  # #94a3b8  "blue-merle" brand label
DIVIDER = (30,  58,  95)   # #1e3a5f  subtle horizontal rule
WHITE   = (226, 232, 240)  # #e2e8f0  working / neutral status
GREEN   = (34,  197, 94)   # #22c55e  success / done
AMBER   = (245, 158, 11)   # #f59e0b  attention / sim-swap
PURPLE  = (139, 92,  246)  # #8b5cf6  restore
GRAY    = (100, 116, 139)  # #64748b  secondary text

# ── Font paths ────────────────────────────────────────────────────────────────
_FONT_DIR  = "/usr/share/fonts/truetype/dejavu"
FONT_BOLD  = os.path.join(_FONT_DIR, "DejaVuSans-Bold.ttf")
FONT_REG   = os.path.join(_FONT_DIR, "DejaVuSans.ttf")


def load_font(path, size):
    try:
        return ImageFont.truetype(path, size)
    except Exception:
        return ImageFont.load_default()


def to_rgb565(img):
    """Convert PIL image to RGB565 little-endian bytes (153,600 bytes for 240×320)."""
    data = img.convert("RGB").tobytes()
    out = bytearray(len(data) // 3 * 2)
    j = 0
    for i in range(0, len(data), 3):
        r, g, b = data[i], data[i + 1], data[i + 2]
        v = ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3)
        out[j]     = v & 0xFF
        out[j + 1] = (v >> 8) & 0xFF
        j += 2
    return bytes(out)


def draw_hcenter(draw, text, y, font, color):
    """Draw text horizontally centered at the given y coordinate (top of text)."""
    bbox = draw.textbbox((0, 0), text, font=font)
    w = bbox[2] - bbox[0]
    x = (W - w) / 2
    draw.text((x, y), text, fill=color, font=font)


def make_base():
    """Shared chrome: background, top/bottom bars, brand label, divider."""
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)

    d.rectangle([0, 0,    W, 4],    fill=ACCENT)   # top bar
    d.rectangle([0, H-4,  W, H],    fill=ACCENT)   # bottom bar

    f_brand = load_font(FONT_REG, 15)
    draw_hcenter(d, "Blue Merle V2", 18, f_brand, BRAND)

    d.line([20, 46, W - 20, 46], fill=DIVIDER)     # divider under brand

    return img, d


def make_frame(name, main_text, main_color, sub_lines):
    """Render one splash frame and write .rgb565 + .png preview.

    sub_lines: list of (text, font_size, color, gap_before) tuples.
    gap_before is the vertical gap above this line (pixels).
    """
    img, d = make_base()

    f_main = load_font(FONT_BOLD, 36)

    # Pre-load fonts and measure all lines
    rendered = []
    for text, size, color, gap in sub_lines:
        f = load_font(FONT_REG, size)
        bbox = d.textbbox((0, 0), text, font=f)
        h = bbox[3] - bbox[1]
        rendered.append((text, f, color, gap, h))

    main_bbox = d.textbbox((0, 0), main_text, font=f_main)
    main_h    = main_bbox[3] - main_bbox[1]

    block_h = main_h
    for _, _, _, gap, h in rendered:
        block_h += gap + h

    content_top = 55
    content_bot = 285
    main_y = content_top + (content_bot - content_top - block_h) // 2

    draw_hcenter(d, main_text, main_y, f_main, main_color)

    y = main_y + main_h
    for text, f, color, gap, h in rendered:
        y += gap
        draw_hcenter(d, text, y, f, color)
        y += h

    rgb565 = to_rgb565(img)
    assert len(rgb565) == W * H * 2, f"expected {W*H*2} bytes, got {len(rgb565)}"

    out_path     = os.path.join(OUT_DIR,     f"{name}.rgb565")
    preview_path = os.path.join(PREVIEW_DIR, f"{name}.png")

    with open(out_path, "wb") as f:
        f.write(rgb565)
    img.save(preview_path)

    print(f"  {name:<12} {len(rgb565):>7,} bytes  →  {os.path.relpath(out_path)}")


# ── Frame definitions ─────────────────────────────────────────────────────────
# sub_lines entries: (text, font_size, color, gap_before_px)
DIM = (71, 85, 105)   # #475569  dimmer gray for tip lines

FRAMES = [
    ("rotating",  "Rotating...",  WHITE,  [
        ("RF Disabled",                    14, GRAY, 14),
        ("New IMEIs Generated",            14, GRAY,  6),
        ("Writing to Modem...",            14, GRAY, 28),
        ("Waiting for Re-registration",    14, GRAY,  6),
        ("Do not power off",               11, DIM,  12),
    ]),
    ("done",      "Done",         GREEN,  [
        ("IMEIs Written to Modem",         14, GRAY, 14),
        ("Re-registering with Carrier",     14, GRAY, 28),
        ("Rotation complete.",             11, DIM,  12),
    ]),
    ("simswap",   "SIM Swap",     AMBER,  [
        ("RF Disabled, Temp IMEIs Set",    14, GRAY, 14),
        ("Automatically Powering Off",     14, GRAY,  6),
        ("Swap SIMs, then power back on",  14, GRAY,  6),
        ("Recommended: Change location",   11, DIM,  12),
        ("between SIM Swaps",              11, DIM,   4),
    ]),
    ("restoring", "Restoring...", PURPLE, [
        ("Factory IMEIs",                  14, GRAY, 14),
        ("MAC Addresses",                  14, GRAY,  6),
        ("SSIDs & WiFi Passwords",         14, GRAY,  6),
        ("Hostname",                       14, GRAY,  6),
        ("Please wait...",                 11, DIM,  12),
    ]),
]

print(f"Generating {len(FRAMES)} frames  ({W}×{H} RGB565, {W*H*2:,} bytes each)")
for args in FRAMES:
    make_frame(*args)

# ── Extra frames (not bundled in IPK — for future use) ────────────────────────
# Saved to screens/extras/ so the build-ipk.sh glob doesn't pick them up.
# error   — hard failure (IMEI write failed, modem unresponsive)
# warning — soft failure (modem timed out on re-registration, operation completed
#           but device may not be on network yet)

EXTRAS_DIR = os.path.join(SCRIPT_DIR, "extras")
os.makedirs(EXTRAS_DIR, exist_ok=True)

RED    = (239, 68,  68)   # #ef4444
ORANGE = (249, 115, 22)   # #f97316

EXTRA_FRAMES = [
    ("error",   "Error",   RED,    [
        ("Operation failed.",               14, GRAY, 14),
        ("logread | grep blue-merle",       11, DIM,  10),
    ]),
    ("warning", "Warning", ORANGE, [
        ("Modem did not re-register.",      14, GRAY, 14),
        ("Check connection manually.",      14, GRAY,  6),
        ("logread | grep blue-merle",       11, DIM,  10),
    ]),
]

_orig_out = OUT_DIR
OUT_DIR = EXTRAS_DIR
print(f"\nGenerating {len(EXTRA_FRAMES)} extra frames  → {os.path.relpath(EXTRAS_DIR)}")
for args in EXTRA_FRAMES:
    make_frame(*args)
OUT_DIR = _orig_out

print("Done.")
