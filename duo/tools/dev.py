#!/usr/bin/env python3
"""dev.py — drive a built game on the device from the Mac: launch, press buttons, screenshot, pull the log.

    dev.py launch <bundle-id>                 terminate + relaunch with an empty control file
    dev.py key    <bundle-id> <keys> [...]    press keys (DM_CTL syntax: A, B, Plus, LUp, A+B, A~2.0 = hold 2 s)
    dev.py wait   <seconds>
    dev.py shot   <out.png>                   screenshot of the ACTIVE display (inner screen while unfolded)
    dev.py log    <bundle-id> <out.txt>       Documents/log.txt
    dev.py run    <bundle-id> <script>        one step per line: launch | key <keys> | wait <s> | shot <out.png>

Needs a build whose env file sets DM_CTL=Documents/ctl.txt (duo/test.env does). The host reads the control file
append-only (it remembers the byte offset), so this tool keeps a local copy per launch and pushes the whole file
after each append: never shrink it while the game runs; `launch` starts a new, empty one.

Device: $DUO_DEVICE, or the only connected iPhone. The active display is found with `devicectl device info displays`
(the inner screen while unfolded; without --display-unique-id devicectl captures the inactive outer screen,
which is black). Screens: inner 2007 x 2853 px upright, outer 1398 x 2034 px.
"""
import json
import os
import subprocess
import sys
import tempfile
import time

DEVICE = os.environ.get('DUO_DEVICE', '')
CTL_DIR = os.path.join(tempfile.gettempdir(), 'duo-ctl')


def device():
    """$DUO_DEVICE, or the UDID of the one connected real iPhone; with none or several, exit and ask for $DUO_DEVICE."""
    global DEVICE
    if DEVICE:
        return DEVICE
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as f:
        path = f.name
    try:
        subprocess.run(['xcrun', 'devicectl', 'list', 'devices', '--json-output', path, '--quiet'], check=True, capture_output=True)
        with open(path) as f:
            raw = json.load(f)['result']['devices']
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError):
        raw = []
    finally:
        os.unlink(path)
    ids = [d['hardwareProperties']['udid'] for d in raw
           if d.get('connectionProperties', {}).get('tunnelState') == 'connected'
           and d.get('hardwareProperties', {}).get('platform') == 'iOS' and d['hardwareProperties'].get('reality') != 'virtual'
           and d['hardwareProperties'].get('udid')]
    if len(ids) != 1:
        sys.exit('{} connected iPhones: export DUO_DEVICE=<udid> (see `xcrun devicectl list devices`)'.format(len(ids) or 'no'))
    DEVICE = ids[0]
    return DEVICE


def devicectl(*args, json_out=False):
    cmd = ['xcrun', 'devicectl', *args]
    if json_out:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as f:
            path = f.name
        subprocess.run(cmd + ['--json-output', path, '--quiet'], check=True, capture_output=True)
        with open(path) as f:
            data = json.load(f)
        os.unlink(path)
        return data
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode:
        sys.exit(f'devicectl {" ".join(args[:3])} failed: {(r.stderr or r.stdout).strip()[-400:]}')
    return r.stdout


def ctl_path(bundle):
    os.makedirs(CTL_DIR, exist_ok=True)
    return os.path.join(CTL_DIR, bundle + '.txt')


def push_ctl(bundle):
    devicectl('device', 'copy', 'to', '--device', device(), '--source', ctl_path(bundle), '--domain-type', 'appDataContainer',
              '--domain-identifier', bundle, '--destination', 'Documents/ctl.txt')


def launch(bundle):
    with open(ctl_path(bundle), 'w') as f:
        f.write('# dev.py\n')
    push_ctl(bundle)
    devicectl('device', 'process', 'launch', '--device', device(), '--terminate-existing', bundle)


def key(bundle, *keys):
    with open(ctl_path(bundle), 'a') as f:
        for k in keys:
            f.write(k + '\n')
    push_ctl(bundle)


def active_display():
    """The uniqueId of the screen in use on a foldable (the Duo's inner screen while unfolded), or None on a phone with one
    screen: its displays carry no uniqueId/active pair (iPhone 16 Pro: one `primary` LCD), and a screenshot needs no selector."""
    data = devicectl('device', 'info', 'displays', '--device', device(), json_out=True)
    found = []

    def walk(o):   # the JSON layout differs between Xcode releases: find the dicts that carry uniqueId + active
        if isinstance(o, dict):
            if 'uniqueId' in o and 'active' in o:
                found.append(o)
            for v in o.values():
                walk(v)
        elif isinstance(o, list):
            for v in o:
                walk(v)
    walk(data)
    if not found:
        return None
    for d in found:
        if d.get('active'):
            return str(d['uniqueId'])
    sys.exit('no active display reported (is the phone locked or folded with the outer screen off?)')


def shot(out):
    which = active_display()
    devicectl('device', 'capture', 'screenshot', '--device', device(), *(['--display-unique-id', which] if which else []), '--destination', out)


def log(bundle, out):
    devicectl('device', 'copy', 'from', '--device', device(), '--domain-type', 'appDataContainer', '--domain-identifier', bundle,
              '--source', 'Documents/log.txt', '--destination', out)


def run(bundle, script):
    for line in open(script):
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        cmd, _, arg = line.partition(' ')
        print(f'dev.py: {line}', flush=True)
        if cmd == 'launch':
            launch(bundle)
        elif cmd == 'key':
            key(bundle, *arg.split())
        elif cmd == 'wait':
            time.sleep(float(arg))
        elif cmd == 'shot':
            shot(arg)
        else:
            sys.exit(f'dev.py: unknown step {line!r}')


def main(argv):
    if len(argv) < 2:
        sys.exit(__doc__)
    cmd, args = argv[1], argv[2:]
    if cmd == 'launch' and len(args) == 1:
        launch(args[0])
    elif cmd == 'key' and len(args) >= 2:
        key(args[0], *args[1:])
    elif cmd == 'wait' and len(args) == 1:
        time.sleep(float(args[0]))
    elif cmd == 'shot' and len(args) == 1:
        shot(args[0])
    elif cmd == 'log' and len(args) == 2:
        log(*args)
    elif cmd == 'run' and len(args) == 2:
        run(*args)
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main(sys.argv)
