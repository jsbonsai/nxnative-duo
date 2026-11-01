#!/usr/bin/env python3
"""hudcheck.py — is each HUD corner at its true shape or stretched? Compares a device screenshot with an
unpatched 1920x1080 frame of the same scene.

    hudcheck.py <device.png> <baseline-1080.png>

A corner-anchored HUD element at its true shape is the baseline's corner scaled uniformly by W/1920 (the UI
laid out on the real screen); stretched, it is scaled W/1920 across and H/1080 down (the 16:9 picture
stretched to the screen). For each corner the baseline crop is rendered both ways, anchored to that corner,
and scored by normalized cross-correlation with a small shift search; the higher score names the shape.
"""
import sys
import numpy as np
from PIL import Image

def ncc(a, b):
    a = a - a.mean(); b = b - b.mean(); d = np.sqrt((a * a).sum() * (b * b).sum())
    return float((a * b).sum() / d) if d else 0.0

def main(dev_path, base_path):
    dev = Image.open(dev_path).convert('L'); base = Image.open(base_path).convert('L')
    W, H = dev.size; sx, sy = W / 1920, H / 1080
    D = np.asarray(dev, dtype=np.float32)
    corners = {'top-left': (0, 0), 'top-right': (1, 0), 'bottom-left': (0, 1), 'bottom-right': (1, 1)}
    bw, bh = 300, 220   # baseline crop size at each corner (1920x1080 px): the HUD clusters live there
    for name, (rx, ry) in corners.items():
        bx = 1920 - bw if rx else 0; by = 1080 - bh if ry else 0
        crop = base.crop((bx, by, bx + bw, by + bh))
        res = {}
        for shape, (kx, ky) in (('true shape', (sx, sx)), ('stretched', (sx, sy))):
            w, h = round(bw * kx), round(bh * ky)
            ref = np.asarray(crop.resize((w, h), Image.BILINEAR), dtype=np.float32)
            best = -1
            for dy in range(-40, 41, 4):
                for dx in range(-40, 41, 4):
                    x0 = (W - w if rx else 0) + dx; y0 = (H - h if ry else 0) + dy
                    if x0 < 0 or y0 < 0 or x0 + w > W or y0 + h > H: continue
                    best = max(best, ncc(D[y0:y0 + h:2, x0:x0 + w:2], ref[::2, ::2]))
            res[shape] = best
        verdict = max(res, key=res.get)
        print(f'{name:13s} true shape {res["true shape"]:.3f}   stretched {res["stretched"]:.3f}   -> {verdict}')

if __name__ == '__main__':
    if len(sys.argv) != 3: sys.exit(__doc__)
    main(*sys.argv[1:])
