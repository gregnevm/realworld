"""Value analysis of a game screenshot ('desaturate it' test, "Reducing Visual Confusion").
usage: value_check.py <screenshot.png> [out_gray.png] — crops the map area, prints luminance stats, saves gray."""
import sys
from PIL import Image, ImageOps
import numpy as np
im = Image.open(sys.argv[1]).convert("RGB"); w, h = im.size
g = ImageOps.grayscale(im.crop((int(w*.20), int(h*.08), int(w*.78), int(h*.90))))
a = np.asarray(g, dtype=float)
p5, p50, p95 = (float(np.percentile(a, q)) for q in (5, 50, 95))
print(f"value mean={a.mean():.1f} std={a.std():.1f} p5={p5:.0f} p50={p50:.0f} p95={p95:.0f} range={p95-p5:.0f} near-black={(a<20).mean()*100:.1f}%")
if p95 - p5 < 40: print("WARN: flat scene — objects will not separate from ground")
if len(sys.argv) > 2: g.save(sys.argv[2])
