"""Duo aspect stubs: make a game's camera and viewport take the drawable's aspect.

Used by dm/tools/patch_nso.py when DM_DUO=1 (see duo/DESIGN.md). The mechanism is
reimplemented from MacNativeGames (MIT), which ships it for TotK on iPhone; no code is
copied, only the documented instruction forms and the stub layout.

A site holds an instruction that leaves the game's 16:9 ratio in s<d>:

    (ins & 0xffe0fc00) == 0x1e201800   fdiv s<d>, s<n>, s<m>   (the ratio computed)
    (ins & 0xffc00000) == 0xbd400000   ldr  s<d>, [x<n>, #imm]  (the ratio loaded)

It is replaced by a branch to an 8-word stub that runs it and, while the state page's
slot holds a non-zero ratio, substitutes the drawable's.
"""
import json
import os
import struct

SLOT = 0x40          # state page offset: float bits of width/height (0 = the game's own)
STUB_WORDS = 8


def branch(frm, to):
    d = to - frm
    if d & 3 or not (-(1 << 27) <= d < (1 << 27)):
        return 0
    return 0x14000000 | ((d >> 2) & 0x3ffffff)


def adrp(reg, at, to):
    pages = (to >> 12) - (at >> 12)
    if not (-(1 << 20) <= pages < (1 << 20)):
        return 0
    imm = pages & 0x1fffff
    return 0x90000000 | ((imm & 3) << 29) | ((imm >> 2) << 5) | reg


def form_ok(ins):
    return (ins & 0xffe0fc00) == 0x1e201800 or (ins & 0xffc00000) == 0xbd400000


def stub(ins, at, site, data_off, slot):
    """The 8 words for a site, or None when a branch is out of range."""
    a = adrp(10, at + 8, data_off)
    back = branch(at + 28, site + 4)
    if not a or not back:
        return None
    return [ins,                                                      # the game's own ratio
            0xf81f0fea,                                               # str x10, [sp, #-16]!
            a,                                                        # adrp x10, <state page>
            0xb9400000 | (((slot - data_off) // 4) << 10) | (10 << 5) | 10,  # ldr w10, [x10, #slot]
            0x3400004a,                                               # cbz w10, +8 (off)
            0x1e270000 | (10 << 5) | (ins & 31),                      # fmov s<d>, w10
            0xf84107ea,                                               # ldr x10, [sp], #16
            back]                                                     # b site + 4


def pack():
    """The Duo patch pack this build applies: DUO_PATCH names a *.duopatch.json (duo/patches/README.md, the contract), or
    nothing is patched. The research tables in duo/research/ are notes, never read by a build."""
    path = os.environ.get('DUO_PATCH')
    if not path:
        return None
    try:
        with open(path, encoding='utf-8') as f:
            p = json.load(f)
    except (OSError, ValueError) as e:
        raise SystemExit(f'duo patch: cannot read {path}: {e}')
    if p.get('format') != 1:
        raise SystemExit(f'duo patch: {path}: format {p.get("format")!r}, this rewriter reads format 1')
    return p


def _pack_for(build_id):
    """The pack when it was made for this main build; a pack for another build stops the rewrite rather than being
    skipped, so a build never looks patched when it is not (DRAGON QUEST VII, 2026-10-30)."""
    p = pack()
    if p is None:
        return None
    want = str(p.get('main_build_id', '')).lower()
    if want != build_id.lower():
        raise SystemExit(f'duo patch: {p.get("name", "the pack")} is for main {want}, this game\'s main is {build_id}')
    return p


def res_for(build_id):
    """[(offset, old_w, old_h, new_w, new_h)] the pack's canvas rows for this build."""
    p = _pack_for(build_id)
    return [tuple(int(str(x), 0) for x in row) for row in (p or {}).get('canvas', [])]


def install_res(build_id, img, put, stat=None):
    """Rewrite the engine's render-size pairs. Returns how many were patched."""
    n = 0
    for off, ow, oh, nw, nh in res_for(build_id):
        if off + 8 > len(img):
            raise SystemExit(f'duo res: pair {off:#x} outside the module')
        got = struct.unpack_from('<II', img, off)
        if got != (ow, oh):
            raise SystemExit(f'duo res: {off:#x} holds {got[0]:#x},{got[1]:#x}, expected {ow:#x},{oh:#x}')
        # the second word is the neighbour instruction: asserted, never written
        put(off, [nw], f'duo res: {ow:#010x} -> {nw:#010x} at {off:#x} (neighbour {oh:#010x} unchanged)')
        if stat:
            stat('duo_res')
        n += 1
    return n


def sites_for(build_id):
    """([(site offset, inverse)], rodata 16:9 constant offset or None) from the pack for this build.
    A site written '~0x…' computes the inverse ratio (UE4's height/width branch) and gets 1/ratio."""
    p = _pack_for(build_id)
    if p is None:
        return [], None
    cam = p.get('camera') or {}
    sites = []
    for x in cam.get('sites') or []:
        x = str(x).strip()
        inv = x.startswith('~')   # '~0x…': the instruction computes height/width, so it must get 1/ratio
        sites.append((int(x.lstrip('~'), 16), inv))
    const = cam.get('const')
    return sites, (int(str(const), 16) if const not in (None, '', '-') else None)


def ratio_bits():
    """(float bits, value) of the drawable ratio DM_DUO_ASPECT ('w:h', 'wxh' or a number; default the Duo's 2853:2007)."""
    ratio = os.environ.get('DM_DUO_ASPECT', '2853:2007')
    try:
        if ':' in ratio:
            w, h = ratio.split(':', 1)
        elif 'x' in ratio:
            w, h = ratio.split('x', 1)
        else:
            w, h = float(ratio), 1.0
        v = float(w) / float(h)
    except (ValueError, ZeroDivisionError):
        raise SystemExit(f'duo aspect: DM_DUO_ASPECT={ratio!r} is not w:h or a ratio')
    return struct.unpack('<I', struct.pack('<f', v))[0], v


def install_const(build_id, img, put, stat=None):
    """Replace the game's 16:9 rodata constant with the drawable ratio. No state page."""
    _sites, const = sites_for(build_id)
    if const is None:
        return 0
    if const + 4 > len(img):
        raise SystemExit(f'duo aspect: constant {const:#x} outside the module')
    word = struct.unpack_from('<I', img, const)[0]
    if word != 0x3FE38E39:
        raise SystemExit(f'duo aspect: {const:#x} holds {word:08x}, not the 16:9 float 3FE38E39')
    val, v = ratio_bits()
    put(const, [val], f'duo aspect: 16:9 constant {const:#x} -> drawable ratio {v:.4f}')
    if stat:
        stat('duo_aspect_const')
    return 1


def ldr_s_literal(d, off):
    """ldr s<d>, <pc + off> (LDR literal, 32-bit SIMD&FP; off a multiple of 4 within +-1 MB)."""
    assert off % 4 == 0 and -(1 << 20) <= off < (1 << 20)
    return 0x1C000000 | (((off >> 2) & 0x7FFFF) << 5) | d


def const_stub(ins, at, site, bits):
    """The 3 words for a site in a build without a frame-step state page: the site's register gets the
    drawable ratio as a constant (the game's own division or load is dropped: it has no side effect),
    then execution goes back to the instruction after the site. None when the branch back is out of range.

        at+0: ldr s<d>, at+8     the ratio, from the literal below
        at+4: b   site+4
        at+8: .float ratio
    """
    back = branch(at + 4, site + 4)
    if not back:
        return None
    return [ldr_s_literal(ins & 31, 8), back, bits]


def movz_movk_form(img, off):
    """The register of a `movz w<d>, #imm16` + `movk w<d>, #imm16, lsl #16` pair at off (the two instructions that
    put a 32-bit constant — a float by its bits — into a w register), or None. Engines that never keep 16:9 as
    rodata build it this way (Assassin's Creed The Ezio Collection: 11 such pairs, the camera one at 0xff4ef0)."""
    if off + 8 > len(img):
        return None
    a, b = struct.unpack_from('<II', img, off)
    if (a & 0xFF800000) != 0x52800000:   # movz w<d>, #imm16 (hw = 0)
        return None
    if (b & 0xFFE00000) != 0x72A00000:   # movk w<d>, #imm16, lsl #16 (hw = 1 is bit 21, inside the mask)
        return None
    return (a & 31) if (a & 31) == (b & 31) else None


def ldr_w_literal(d, off):
    """ldr w<d>, <pc + off> (LDR literal, 32-bit integer; off a multiple of 4 within +-1 MB)."""
    assert off % 4 == 0 and -(1 << 20) <= off < (1 << 20)
    return 0x18000000 | (((off >> 2) & 0x7FFFF) << 5) | d


def const_stub_pair(at, site, bits, rd):
    """The 3 words replacing a movz/movk pair (site .. site+8): the register gets the ratio, then execution goes on
    at site+8. `ldr w<d>, at+8` · `b site+8` · `.float ratio`."""
    back = branch(at + 4, site + 8)
    if not back:
        return None
    return [ldr_w_literal(rd, 8), back, bits]


def install_sites_const(build_id, img, text_end, here, emit, put, site_ok, stat=None):
    """Per-site constant stubs for a build without FRAME_STEP (no state page): each listed site (an fdiv or
    ldr leaving the game's 16:9 ratio in s<d>) is replaced by a branch to const_stub. site_ok(off) asserts the
    site is not an instruction the rewriter itself rewrites. Returns how many sites."""
    sites, _const = sites_for(build_id)
    if not sites:
        return 0
    bits, v = ratio_bits()
    for site, inv in sites:
        if site + 4 > text_end:
            raise SystemExit(f'duo aspect: site {site:#x} outside main\'s text')
        ins = struct.unpack_from('<I', img, site)[0]
        rd = movz_movk_form(img, site)
        if not form_ok(ins) and rd is None:
            raise SystemExit(f'duo aspect: {site:#x} holds {ins:08x}, not an aspect instruction (fdiv/ldr s or a movz+movk pair)')
        site_ok(site)
        b = struct.unpack('<I', struct.pack('<f', 1.0 / v))[0] if inv else bits
        at = here()
        words = const_stub_pair(at, site, b, rd) if rd is not None else const_stub(ins, at, site, b)
        to = branch(site, at)
        if not words or not to:
            raise SystemExit(f'duo aspect: stub for {site:#x} is out of branch range')
        for w in words:
            emit(w)
        put(site, [to], f'duo aspect: s{ins & 31} = {1.0 / v if inv else v:.5f} at {site:#x} (constant stub at {at:#x})')
        if stat:
            stat('duo_aspect_site_const')
    return len(sites)


def install_sites(build_id, img, text_end, state_off, here, emit, put, stat=None):
    """Emit the per-site stubs (needs the frame-step state page). Returns how many sites."""
    sites, _const = sites_for(build_id)
    n = 0
    if not sites:
        return 0
    slot = state_off + SLOT
    for site, _inv in sites:
        if site + 4 > text_end:
            raise SystemExit(f'duo aspect: site {site:#x} outside main\'s text')
        ins = struct.unpack_from('<I', img, site)[0]
        if not form_ok(ins):
            raise SystemExit(f'duo aspect: {site:#x} holds {ins:08x}, not an aspect instruction')
        at = here()
        words = stub(ins, at, site, state_off, slot)
        if not words:
            raise SystemExit(f'duo aspect: stub for {site:#x} is out of branch range')
        for w in words:
            emit(w)
        put(site, [branch(site, at)], 'duo aspect: branch to the ratio stub')
        if stat:
            stat('duo_aspect')
    return len(sites)
