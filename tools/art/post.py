#!/usr/bin/env python3
"""RealWorld — tools/art/post.py : post-process one Nano Banana render into a game-ready PNG.

Requires Pillow + numpy (`pip install pillow numpy`). Lessons from the first live batch (2026-11-04) are
baked in — the model does NOT paint the requested #FF00FF: the muted-palette bible pulls the "magenta"
to ~(190,50,112), adds a soft vignette and a darker cast shadow in the same hue. So keying is ADAPTIVE:

  --key     1. estimate the real background from the 3-px border ring (robust mode, any flat color);
            2. a pixel is background-family when its CHROMATICITY (r,g,b)/sum matches the bg — lighter
               (vignette) or darker (cast shadow) variants of the same hue;
               lit bg → alpha 0 · shadowed bg → soft black shadow (alpha ≤ 0.5);
            3. anti-aliased rim (≤3 px from keyed area): alpha from RGB distance to bg, color UN-MIXED
               (c - (1-a)·bg)/a — no magenta fringe;
            then trim to the alpha bbox and pad to a centered square.
  --tile    strip a uniform frame the model may copy from the swatch-card reference, inset, square-crop,
            then cross-fade the edges so the texture wraps seamlessly (verified by --check-seam metric).
  resize    premultiplied (RGBa) LANCZOS to --size, so transparent pixels never bleed dark halos.
  --palette optional snap to art/palette.json (no dither). Off by default: on painterly renders it
            posterizes; consistency comes from the style bible + reference anchors.

Usage: python3 -I tools/art/post.py IN.png OUT.png --size 128 [--key] [--tile] [--palette art/palette.json]
"""
import argparse
import json
import sys

import numpy as np
from PIL import Image

CHROMA_TOL = 0.045   # L2 distance in chromaticity space that still counts as "same hue as bg"
LIT_RATIO = 0.80     # luminance ratio vs bg above which a bg-hue pixel is plain background
SHADOW_MAX = 0.5     # alpha ceiling for converted cast shadows
RIM_PX = 3
RIM_LO, RIM_HI = 28.0, 120.0  # RGB distance → alpha ramp on the anti-aliased rim
TINT_PX, TINT_TOL = 24, 0.15  # despill band width / chroma reach (palette red & violet sit at ≥0.2)
SPILL_PX, SPILL_CD = 40, 0.34  # pink-excess un-mix: band width (px at ~1024 raw) / chroma reach (hue-shifted magenta shadows reach 0.27)
SPILL_BALANCE = 0.22  # magenta spill has r≈b: |r-b| ≤ this·max(r,b). Violet accents (#b58cff, b≫r) fail it and stay untouched
SPILL_EDGE_PX, SPILL_SHADOW_T = 6, 0.25  # beyond this from background, bg share ≥ T is cast shadow, not an anti-aliased edge
SPILL_NEAR_PX = 8  # within this of the background the r≈b gate is dropped (warm anti-aliased edges, e.g. flames)
FLAT_STD, FLAT_WIN = 6.0, 2  # a pink region whose 5×5 grey std is below this is a flat cast shadow, not painted detail
SPILL_MIN_T, SPILL_KILL_T = 0.03, 0.92  # ignore noise below this bg share; at/above the second the pixel is bg
SPILL_MIN_BG_EXCESS = 100.0  # only when the key really is pink (min(r,b)-g of the bg); else the older passes run alone


def estimate_bg(rgb):
    h, w, _ = rgb.shape
    ring = np.concatenate([rgb[:3].reshape(-1, 3), rgb[-3:].reshape(-1, 3),
                           rgb[:, :3].reshape(-1, 3), rgb[:, -3:].reshape(-1, 3)])
    med = np.median(ring, axis=0)
    d = np.linalg.norm(ring - med, axis=1)
    core = ring[d <= np.percentile(d, 60)]
    spread = float(np.percentile(d, 60))
    return core.mean(axis=0), spread


def chroma(rgb):
    s = rgb.sum(axis=-1, keepdims=True)
    return rgb / np.maximum(s, 1.0)


def dilate(mask, px):
    m = mask.copy()
    for _ in range(px):
        g = m.copy()
        g[1:] |= m[:-1]
        g[:-1] |= m[1:]
        g[:, 1:] |= m[:, :-1]
        g[:, :-1] |= m[:, 1:]
        m = g
    return m


def local_std(g, r=FLAT_WIN):
    """Per-pixel std of the grey image over a (2r+1)² window (numpy only, edge-padded)."""
    pad = np.pad(g, r, mode="edge")
    m1 = np.zeros_like(g)
    m2 = np.zeros_like(g)
    for dy in range(2 * r + 1):
        for dx in range(2 * r + 1):
            w = pad[dy:dy + g.shape[0], dx:dx + g.shape[1]]
            m1 += w
            m2 += w * w
    n = float((2 * r + 1) ** 2)
    return np.sqrt(np.maximum(m2 / n - (m1 / n) ** 2, 0.0))


def chroma_key(img):
    rgb = np.asarray(img.convert("RGB"), dtype=np.float32)
    bg, spread = estimate_bg(rgb)
    if spread > 40:
        print(f"post.py: warning — border is not a flat background (spread {spread:.0f}); keying may be partial",
              file=sys.stderr)
    cd = np.linalg.norm(chroma(rgb) - chroma(bg[None, None, :])[0, 0], axis=-1)
    lum = rgb.sum(axis=-1) / max(float(bg.sum()), 1.0)
    family = cd < CHROMA_TOL
    lit = family & (lum >= LIT_RATIO)
    shadow = family & (lum < LIT_RATIO)

    out = np.dstack([rgb, np.full(rgb.shape[:2], 255.0, dtype=np.float32)])
    out[lit, 3] = 0.0
    out[shadow, :3] = 0.0
    out[shadow, 3] = np.clip((LIT_RATIO - lum[shadow]) / LIT_RATIO, 0.0, SHADOW_MAX) * 255.0

    rim = dilate(lit, RIM_PX) & ~family
    if rim.any():
        dist = np.linalg.norm(rgb[rim] - bg, axis=-1)
        a = np.clip((dist - RIM_LO) / (RIM_HI - RIM_LO), 0.0, 1.0)
        safe = np.maximum(a, 1e-3)[:, None]
        unmixed = (rgb[rim] - (1.0 - a)[:, None] * bg) / safe
        out[rim, :3] = np.clip(unmixed, 0, 255)
        out[rim, 3] = a * 255.0

    # Translucent wisps (smoke, steam, glow) composited over the key keep its hue. In a band near the keyed
    # area, pixels still LEANING toward the bg chroma are re-read as grey of the same luminance and faded by
    # how bg-like they are. Distance-gated, so purple/red details inside a subject are untouched.
    lean = dilate(lit, TINT_PX) & ~family & ~rim & (cd < TINT_TOL)
    if lean.any():
        w = np.clip(1.0 - (cd[lean] - CHROMA_TOL) / (TINT_TOL - CHROMA_TOL), 0.0, 1.0)[:, None]
        grey = rgb[lean].mean(axis=-1, keepdims=True)
        out[lean, :3] = rgb[lean] * (1.0 - w) + grey * w
        out[lean, 3] = 255.0 * (1.0 - 0.6 * w[:, 0])

    # Pink-excess un-mix (Nano Banana 2.1 paints a TRUE magenta key). The RGB-distance rim above under-estimates
    # coverage for a DARK outline blended over magenta (e.g. 50/50 → (134,12,136), distance > RIM_HI → "opaque"),
    # which leaves a violet halo and whiskers. A non-pink subject colour has ~0 excess min(r,b)-g, so the excess
    # of a mixed pixel is exactly its background share t: alpha = 1-t, colour = (c - t·bg)/(1-t).
    #   • FLAT pink regions (local texture std < FLAT_STD) with t ≥ SPILL_SHADOW_T are the model's cast shadow in a
    #     darker hue-shifted magenta — incl. enclosed pockets between legs/spikes far from any lit background. They
    #     become the same soft black shadow as the family shadow.
    #   • Everything within SPILL_PX of (lit ∪ flat-pink) is un-mixed. Away from the very edge only r≈b pixels
    #     qualify (violet accents #b58cff, b≫r, stay untouched); within SPILL_NEAR_PX the balance gate is dropped,
    #     because anti-aliased edges of warm subjects (flames: orange over magenta → r≫b) are not r≈b.
    exc_bg = min(float(bg[0]), float(bg[2])) - float(bg[1])
    if exc_bg > SPILL_MIN_BG_EXCESS:
        balanced = np.abs(rgb[..., 0] - rgb[..., 2]) <= SPILL_BALANCE * np.maximum(rgb[..., 0], rgb[..., 2])
        excess = np.minimum(rgb[..., 0], rgb[..., 2]) - rgb[..., 1]
        t = np.clip(excess / exc_bg, 0.0, 1.0)
        near = (cd < SPILL_CD) & ~family
        flat = near & balanced & (t >= SPILL_SHADOW_T) & (local_std(rgb.mean(axis=-1)) < FLAT_STD)
        if flat.any():
            out[flat, :3] = 0.0
            out[flat, 3] = np.minimum(out[flat, 3], np.clip(t[flat] * 0.6, 0.0, SHADOW_MAX) * 255.0)
        zone = lit | flat
        band = (dilate(zone, SPILL_PX) & balanced | dilate(zone, SPILL_NEAR_PX)) & near & ~flat
        fix = band & (t >= SPILL_MIN_T)
        if fix.any():
            tt = t[fix][:, None]
            keep = np.maximum(1.0 - tt, 1e-3)
            unmixed = np.clip((rgb[fix] - tt * bg) / keep, 0, 255)
            alpha = np.where(tt[:, 0] >= SPILL_KILL_T, 0.0, 255.0 * (1.0 - tt[:, 0]))
            out[fix, :3] = unmixed
            out[fix, 3] = np.minimum(out[fix, 3], alpha)
        # A strongly pink textured pixel FAR from any background can't be an anti-aliased edge either.
        deep = (dilate(zone, SPILL_PX) & balanced) & near & ~dilate(zone, SPILL_EDGE_PX) & (t >= SPILL_SHADOW_T) & ~flat
        if deep.any():
            out[deep, :3] = 0.0
            out[deep, 3] = np.minimum(out[deep, 3], np.clip(t[deep] * 0.6, 0.0, SHADOW_MAX) * 255.0)
    return Image.fromarray(out.round().astype(np.uint8), "RGBA")


def trim_square(img, margin=0.06):
    bbox = img.getchannel("A").point(lambda v: 255 if v > 16 else 0).getbbox()
    if not bbox:
        raise SystemExit("post.py: keying removed everything — background was not flat?")
    img = img.crop(bbox)
    w, h = img.size
    side = int(max(w, h) * (1 + margin * 2))
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(img, ((side - w) // 2, (side - h) // 2))
    return canvas


def strip_frame(rgb, max_frac=0.2, std_tol=9.0):
    """Peel uniform rows/cols (a swatch-card frame/padding) off each side."""
    lum = rgb.mean(axis=-1)
    h, w = lum.shape
    top, bot, left, right = 0, h, 0, w
    while top < h * max_frac and lum[top].std() < std_tol:
        top += 1
    while h - bot < h * max_frac and lum[bot - 1].std() < std_tol:
        bot -= 1
    while left < w * max_frac and lum[:, left].std() < std_tol:
        left += 1
    while w - right < w * max_frac and lum[:, right - 1].std() < std_tol:
        right -= 1
    # frames are usually a dark card + a 1–2 px bevel: inset a little more once a frame was found
    pad = int((0.035 if (top or left or h - bot or w - right) else 0.02) * min(h, w))
    return rgb[top + pad:bot - pad, left + pad:right - pad]


def seamless(rgb, frac=0.125):
    """Cross-fade overlap: output is (n - o) wide, the first o columns blend in the last o, so col 0 continues
    from col n-o-1. Applied per axis. Returns a strictly periodic texture."""
    for axis in (1, 0):
        n = rgb.shape[axis]
        o = max(2, int(n * frac))
        m = n - o
        a = np.moveaxis(rgb, axis, 0)
        t = a[:m].copy()
        ramp = (np.arange(o, dtype=np.float32) / o)[(slice(None),) + (None,) * (a.ndim - 1)]
        t[:o] = a[m:m + o] * (1.0 - ramp) + a[:o] * ramp
        rgb = np.moveaxis(t, 0, axis)
    return rgb


def seam_score(rgb):
    """Mean abs jump across the wrap boundary relative to the mean interior neighbour jump (≈1 = seamless)."""
    f = rgb.astype(np.float32)
    inner = (np.abs(np.diff(f, axis=1)).mean() + np.abs(np.diff(f, axis=0)).mean()) / 2
    wrap = (np.abs(f[:, 0] - f[:, -1]).mean() + np.abs(f[0] - f[-1]).mean()) / 2
    return float(wrap / max(inner, 1e-6))


def tile(img):
    rgb = np.asarray(img.convert("RGB"), dtype=np.float32)
    rgb = strip_frame(rgb)
    h, w, _ = rgb.shape
    s = min(h, w)
    rgb = rgb[(h - s) // 2:(h - s) // 2 + s, (w - s) // 2:(w - s) // 2 + s]
    rgb = seamless(rgb)
    return Image.fromarray(np.clip(rgb, 0, 255).round().astype(np.uint8), "RGB").convert("RGBA")


def apply_palette(img, palette_path):
    with open(palette_path, encoding="utf-8") as f:
        colors = json.load(f)["colors"][:256]
    flat = []
    for hx in colors:
        hx = hx.lstrip("#")
        flat += [int(hx[0:2], 16), int(hx[2:4], 16), int(hx[4:6], 16)]
    pal_img = Image.new("P", (1, 1))
    pal_img.putpalette(flat + flat[:3] * (256 - len(colors)))  # pad by repeating color 0 — never a new color
    alpha = img.getchannel("A")
    snapped = img.convert("RGB").quantize(palette=pal_img, dither=Image.Dither.NONE).convert("RGB")
    snapped.putalpha(alpha)
    return snapped


def resize_wrapped(img, size):
    """Resize a periodic texture as a 3×3 mosaic and keep the center, so the filter sees wrapped neighbours
    at the edges (a plain resize clamps at the border and re-opens the seam)."""
    w, h = img.size
    big = Image.new(img.mode, (w * 3, h * 3))
    for i in range(3):
        for j in range(3):
            big.paste(img, (i * w, j * h))
    big = big.resize((size * 3, size * 3), Image.LANCZOS)
    return big.crop((size, size, size * 2, size * 2))


def resize_premultiplied(img, size):
    return img.convert("RGBa").resize((size, size), Image.LANCZOS).convert("RGBA")


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
        img = tile(img)
    elif a.key:
        img = trim_square(chroma_key(img))
    else:
        img = img.convert("RGBA")
    if a.size > 0 and img.size[0] != a.size:
        img = resize_wrapped(img, a.size) if a.tile else resize_premultiplied(img, a.size)
    if a.palette:
        img = apply_palette(img, a.palette)
    if a.tile:
        img = img.convert("RGB")
        print(f"post.py: seam score {seam_score(np.asarray(img)):.2f} (≈1 seamless)", file=sys.stderr)
    img.save(a.dst, optimize=True)


if __name__ == "__main__":
    main()
