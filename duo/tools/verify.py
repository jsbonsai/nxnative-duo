#!/usr/bin/env python3
"""verify.py — build a game into a device slot, drive it, capture frames, and measure what came out.

    verify.py <game folder> --keys <prod.keys> --slot <bundle id> [--mode duo|letterbox|crop]
              [--keyscript "A,A,A"] [--waits 20,8,10,14] [--out /tmp/verify]

The "slot" is one of the bundle ids that already has a provisioning profile on this Mac (a free Apple ID
allows three apps at a time, so tests reuse them): the ones a `security find-identity` + profile listing shows (e.g. org.nxnative.duo.*).

Steps, all reported line by line so several can run at once:
 1. bin/duo build … --mode … --bundle-id <slot>  (prepare + xcodebuild + sign; no install yet)
 2. devicectl install + launch
 3. press the keys in --keyscript with the waits, screenshotting after each
 4. measure each screenshot: colour vs controls, and (with --baseline) the HUD shape score from hudcheck.py

Nothing here decides "good": it prints the numbers and the frame paths; a human (or the next agent) reads them.
"""
import argparse
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DEV = os.path.join(ROOT, 'duo', 'tools', 'dev.py')
HUD = os.path.join(ROOT, 'duo', 'tools', 'hudcheck.py')
DUO = os.path.join(ROOT, 'bin', 'duo')
PY = sys.executable


def say(m):
    print(m, flush=True)


def shots(paths):
    """Quick numeric signature of each frame, so an unattended run can be skimmed: size + colour/controls split."""
    from PIL import Image
    import numpy as np
    for p in paths:
        if not os.path.isfile(p):
            say(f'  {p}: MISSING')
            continue
        im = Image.open(p).convert('RGB')
        a = np.asarray(im.resize((64, 46)), dtype=np.float32)
        say(f'  {os.path.basename(p)}: {im.size[0]}x{im.size[1]} mean RGB {a.mean(axis=(0, 1)).round(0)} std {a.std():.0f} ({os.path.getsize(p)//1024} KB)')


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument('game')
    ap.add_argument('--keys', required=True)
    ap.add_argument('--slot', required=True)
    ap.add_argument('--mode', default='duo', choices=['duo', 'letterbox', 'crop'])
    ap.add_argument('--keyscript', default='A,A,A')
    ap.add_argument('--waits', default='22,8,10,14')
    ap.add_argument('--out', default='/tmp/verify')
    ap.add_argument('--baseline', help='unpatched 1920x1080 frame of the same scene, for hudcheck.py')
    ap.add_argument('--no-build', action='store_true', help='the app is already built for this slot')
    a = ap.parse_args(argv)
    os.makedirs(a.out, exist_ok=True)
    name = os.path.basename(a.game.rstrip('/'))

    say(f'[{name}] build (mode {a.mode}, slot {a.slot})')
    if not a.no_build:
        r = subprocess.run([PY, DUO, 'build', a.game, '--keys', a.keys, '--mode', a.mode, '--bundle-id', a.slot],
                           cwd=ROOT)
        if r.returncode:
            sys.exit(f'[{name}] build failed')

    say(f'[{name}] install + launch')
    app = None
    work = os.path.join(os.path.dirname(a.game.rstrip('/')), os.path.basename(a.game.rstrip('/')) + '_build')
    for root, dirs, files in os.walk(work):
        if root.endswith('Release-iphoneos/DmIOS.app'):
            app = root
            break
    if not app:
        sys.exit(f'[{name}] no built DmIOS.app under {work}')
    subprocess.run(['xcrun', 'devicectl', 'device', 'install', 'app', '--device', os.environ.get('DUO_DEVICE', ''), app],
                   check=False)
    subprocess.run([PY, DEV, 'launch', a.slot])

    waits = [float(x) for x in a.waits.split(',')]
    keys = [k for k in a.keyscript.split(',') if k]
    frames = []
    time.sleep(waits[0] if waits else 20)
    for i, k in enumerate(keys):
        p = os.path.join(a.out, f'{name.replace(" ", "_")}-{i}.png')
        subprocess.run([PY, DEV, 'shot', p], check=False)
        frames.append(p)
        subprocess.run([PY, DEV, 'key', a.slot, k], check=False)
        time.sleep(waits[i + 1] if i + 1 < len(waits) else 10)
    p = os.path.join(a.out, f'{name.replace(" ", "_")}-final.png')
    subprocess.run([PY, DEV, 'shot', p], check=False)
    frames.append(p)

    say(f'[{name}] frames')
    shots(frames)
    if a.baseline:
        say(f'[{name}] HUD shape vs {a.baseline}')
        for p in frames[-2:]:
            subprocess.run([PY, HUD, p, a.baseline])


if __name__ == '__main__':
    main(sys.argv[1:])
