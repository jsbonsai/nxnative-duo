#!/usr/bin/env python3
"""find_aspect.py — candidate camera/viewport aspect sites in a Switch module.

    find_aspect.py <module.nso> [--window N] [--all]

The Duo aspect patch (duo/DESIGN.md) replaces the instruction that produces the game's
16:9 ratio with a stub that substitutes the drawable's. This finds candidates:

  * every `fdiv s<d>, s<n>, s<m>` (the ratio being computed), with a window of the
    instructions around it;
  * `str s<d>, [x<n>, #0xb0]` shortly after a division — the sead projection's aspect
    field, the strongest camera signal (the reference project's camera sites look like
    this);
  * `str s<d>, [x<n>, #0xac]` shortly before — the tangent that goes with it;
  * the float 1.7777778 (0x3FE38E39) in rodata, i.e. a 16:9 constant.

Validated against Tears of the Kingdom 1.4.3, whose four known sites
(0x628c74, 0xb43460, 0x1ff04f4, 0x253fbb0) must appear in the fdiv list.
"""
import argparse
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.normpath(os.path.join(HERE, '..', '..', 'dm', 'tools')))
import nso  # noqa: E402

try:
    from capstone import Cs, CS_ARCH_ARM64, CS_MODE_ARM
except ImportError:
    sys.exit('find_aspect: capstone is not installed (pip install capstone)')

FDIV_MASK, FDIV_VAL = 0xffe0fc00, 0x1e201800
LDR_S_MASK = 0xffc00000
LDR_S_VAL = 0xbd400000
STR_S_MASK = 0xffc00000
STR_S_VAL = 0xbd000000
F16_9 = 0x3FE38E39   # 1.7777778f


def is_fdiv(w): return (w & FDIV_MASK) == FDIV_VAL
def is_ldr_s(w): return (w & LDR_S_MASK) == LDR_S_VAL
def is_str_s(w): return (w & STR_S_MASK) == STR_S_VAL


def str_s_off(w):
    """the byte offset of `str s, [x, #imm]`"""
    return ((w >> 10) & 0xfff) * 4


def str_s_base(w):
    """the base register of `str s, [x, #imm]` (31 is sp: a stack slot, not a projection)"""
    return (w >> 5) & 31


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('module')
    ap.add_argument('--window', type=int, default=8, help='instructions either side to print')
    ap.add_argument('--all', action='store_true', help='print every fdiv, not only scored ones')
    a = ap.parse_args()

    m = nso.cli_read(a.module)
    text_size = m.segments[0][1]
    text = bytes(m.image[:text_size])
    ro_off, ro_size = m.segments[1][0], m.segments[1][1]

    md = Cs(CS_ARCH_ARM64, CS_MODE_ARM)
    md.skipdata = True   # keep going past data words inside text
    insns = list(md.disasm(text, 0))
    by_off = {i.address: i for i in insns}

    # 16:9 constants in rodata
    hits = []
    ro = bytes(m.image[ro_off:ro_off + ro_size])
    for i in range(0, len(ro) - 3, 4):
        if struct.unpack_from('<I', ro, i)[0] == F16_9:
            hits.append(ro_off + i)

    rows = []
    for ins in insns:
        w = struct.unpack_from('<I', text, ins.address)[0]
        kind = 'fdiv' if is_fdiv(w) else 'ldr' if is_ldr_s(w) else None
        if not kind:
            continue
        score, why = 0, []
        window = []
        for d in range(-a.window, a.window + 1):
            at = ins.address + 4 * d
            j = by_off.get(at)
            if j:
                window.append(('>> ' if d == 0 else '   ') + f'{at:#08x}  {j.mnemonic:8} {j.op_str}')
        for d in range(1, a.window + 1):
            j = by_off.get(ins.address + 4 * d)
            if not j:
                continue
            ww = struct.unpack_from('<I', text, j.address)[0]
            if is_str_s(ww) and str_s_base(ww) != 31:
                off = str_s_off(ww)
                if off == 0xb0:
                    score += 3; why.append('str #0xb0 (projection aspect)')
                elif off == 0xac:
                    score += 1; why.append('str #0xac (tangent)')
        for d in range(1, a.window + 1):
            j = by_off.get(ins.address - 4 * d)
            if not j:
                continue
            ww = struct.unpack_from('<I', text, j.address)[0]
            if is_str_s(ww) and str_s_base(ww) != 31 and str_s_off(ww) == 0xac:
                score += 2; why.append('str #0xac before (tangent)')
                break
        rows.append((score, ins.address, kind, why, window))

    rows.sort(key=lambda r: (-r[0], r[1]))
    print(f'# {a.module}')
    print(f'# build id {m.build_id[:16].hex()}')
    print(f'# text {text_size:#x} bytes, {len(insns)} instructions, {len(rows)} fdiv, 16:9 constants at {[hex(x) for x in hits[:6]]}')
    shown = 0
    for score, off, kind, why, window in rows:
        if score == 0 and not a.all:
            continue
        print(f'\n{off:#08x}  {kind}  score {score}  {" ; ".join(sorted(set(why))) or "-"}')
        for line in window:
            print('   ' + line)
        shown += 1
    print(f'\n# {shown} candidate(s) shown of {len(rows)} fdiv/ldr')


if __name__ == '__main__':
    main()
