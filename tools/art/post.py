#!/usr/bin/env python3
"""RealWorld — tools/art/post.py : post-process one Nano Banana render into a game-ready PNG.

Nano Banana never returns alpha and never returns an exact pixel size, so every candidate goes through:
  1. --key     chroma-key the flat magenta (#FF00FF) background to alpha — flood-filled FROM THE BORDER only,
               so magenta-ish pixels inside the subject (a purple crystal, a pink cloth) survive; then
               de-spill the magenta fringe on the remaining edge pixels;
  2. trim      crop to the alpha bbox, pad to a square with a small margin (subject centered);
  3. --tile    tiles skip keying/trim: center-crop to square instead;
  4. resize    LANCZOS down to --size (masters stay painterly; Godot filters/mipmaps from here);
  5. --palette snap RGB to the shared palette (art/palette.json) without dithering — one palette across
               every sprite is what makes 300+ independently generated images read as ONE world.

Usage: python3 -I tools/art/post.py IN.png OUT.png --size 128 [--key] [--tile] [--palette art/palette.json]
Pillow only; no other deps.
"""
import argparse
import json
from collections import deque

from PIL import Image

KEY_RGB = (255, 0, 255)


def is_key(px, tol):
    r, g, b = px[0], px[1], px[2]
    # magenta: red and blue high and close to each other, green clearly lower.
    return r > 255 - tol * 2 and b > 255 - tol * 2 and g < tol * 2 + 40 and abs(r - b) < tol + 30


def chroma_key(img, tol=48):
    img = img.convert("RGBA")
    w, h = img.size
    px = img.load()
    seen = bytearray(w * h)
    q = deque()
    for x in range(w):
        q.append((x, 0))
        q.append((x, h - 1))
    for y in range(h):
        q.append((0, y))
        q.append((w - 1, y))
    while q:
        x, y = q.popleft()
        i = y * w + x
        if seen[i]:
            continue
        seen[i] = 1
        if not is_key(px[x, y], tol):
            continue
        px[x, y] = (0, 0, 0, 0)
        if x > 0:
            q.append((x - 1, y))
        if x < w - 1:
            q.append((x + 1, y))
        if y > 0:
            q.append((x, y - 1))
        if y < h - 1:
            q.append((x, y + 1))
    # de-spill: pixels touching transparency lose the magenta cast and get a soft alpha edge.
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            edge = any(
                0 <= nx < w and 0 <= ny < h and px[nx, ny][3] == 0
                for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1))
            )
            if not edge:
                continue
            m = min(r, b)
            if m > g:
                spill = m - g
                r, b = r - spill, b - spill
                a = max(0, 255 - int(spill * 1.4))
            px[x, y] = (r, g, b, a)
    return img


def trim_square(img, margin=0.06):
    bbox = img.getchannel("A").point(lambda v: 255 if v > 16 else 0).getbbox()
    if not bbox:
        raise SystemExit("post.py: chroma-key removed everything — background was not flat magenta?")
    img = img.crop(bbox)
    w, h = img.size
    side = int(max(w, h) * (1 + margin * 2))
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(img, ((side - w) // 2, (side - h) // 2))
    return canvas


def center_square(img):
    w, h = img.size
    s = min(w, h)
    return img.crop(((w - s) // 2, (h - s) // 2, (w - s) // 2 + s, (h - s) // 2 + s))


def apply_palette(img, palette_path):
    with open(palette_path, encoding="utf-8") as f:
        colors = json.load(f)["colors"]
    flat = []
    for hx in colors[:256]:
        hx = hx.lstrip("#")
        flat += [int(hx[0:2], 16), int(hx[2:4], 16), int(hx[4:6], 16)]
    pal_img = Image.new("P", (1, 1))
    pal_img.putpalette(flat + flat[:3] * (256 - len(flat) // 3))
    rgba = img.convert("RGBA")
    alpha = rgba.getchannel("A")
    snapped = rgba.convert("RGB").quantize(palette=pal_img, dither=Image.Dither.NONE).convert("RGB")
    snapped.putalpha(alpha)
    return snapped


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--size", type=int, default=128)
    ap.add_argument("--key", action="store_true")
    ap.add_argument("--tile", action="store_true")
    ap.add_argument("--palette")
    a = ap.parse_args()

    img = Image.open(a.src)
    if a.tile:
        img = center_square(img.convert("RGBA"))
    elif a.key:
        img = trim_square(chroma_key(img))
    else:
        img = img.convert("RGBA")
    if a.size > 0 and img.size[0] != a.size:
        img = img.resize((a.size, a.size), Image.LANCZOS)
    if a.palette:
        img = apply_palette(img, a.palette)
    img.save(a.dst, optimize=True)


if __name__ == "__main__":
    main()
