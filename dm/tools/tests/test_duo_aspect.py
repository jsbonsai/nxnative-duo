"""The Duo aspect stub encoder (dm/tools/duo_aspect.py): instruction forms, branch
encodings and the state-page slot. No game files needed."""
import os
import struct
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import duo_aspect  # noqa: E402


class Forms(unittest.TestCase):
    def test_accepts_the_two_site_instructions(self):
        self.assertTrue(duo_aspect.form_ok(0x1e201800))   # fdiv s0, s0, s0
        self.assertTrue(duo_aspect.form_ok(0x1e231841))   # fdiv s1, s2, s3
        self.assertTrue(duo_aspect.form_ok(0xbd400000))   # ldr s0, [x0, #0]
        self.assertTrue(duo_aspect.form_ok(0xbd401c00))   # ldr s0, [x0, #0x1c]

    def test_rejects_everything_else(self):
        for ins in (0xd503201f,   # nop
                    0x1e202000,   # fadd
                    0xbd000000,   # str s0, [x0]
                    0xb9400000):  # ldr w0, [x0]
            self.assertFalse(duo_aspect.form_ok(ins), hex(ins))


class Encodings(unittest.TestCase):
    def test_branch_forward_and_back(self):
        self.assertEqual(duo_aspect.branch(0x2000, 0x1000), 0x17fffc00)
        self.assertEqual(duo_aspect.branch(0x1000, 0x2004), 0x14000401)

    def test_branch_refuses_unaligned_and_far(self):
        self.assertEqual(duo_aspect.branch(0x1000, 0x1002), 0)
        self.assertEqual(duo_aspect.branch(0, 1 << 28), 0)

    def test_adrp_pages(self):
        self.assertEqual(duo_aspect.adrp(10, 0x1008, 0x8000), 0xf000002a)
        self.assertEqual(duo_aspect.adrp(10, 0, 1 << 32), 0)


class Stub(unittest.TestCase):
    def test_word_layout(self):
        w = duo_aspect.stub(0xbd400000, 0x1000, 0x2000, 0x8000, 0x8040)
        self.assertEqual(w[0], 0xbd400000, "the game's own instruction runs first")
        self.assertEqual(w[1], 0xf81f0fea, "scratch register saved")
        self.assertEqual(w[3], 0xb940414a, "ldr w10, [x10, #0x40] (slot is page-relative)")
        self.assertEqual(w[4], 0x3400004a, "cbz w10, +8")
        self.assertEqual(w[5], 0x1e270140, "fmov s0, w10")
        self.assertEqual(w[7], 0x140003fa, "back to site + 4")

    def test_slot_uses_the_destination_register(self):
        w = duo_aspect.stub(0x1e201803, 0x1000, 0x2000, 0x8000, 0x8040)   # s3
        self.assertEqual(w[5], 0x1e270143)

    def test_out_of_range_is_refused(self):
        self.assertIsNone(duo_aspect.stub(0xbd400000, 0x1000, 0x2000, 1 << 40, 1 << 40))


class Pack(unittest.TestCase):
    """The rewriter reads exactly one Duo patch pack (DUO_PATCH), and only for the build it names (duo/patches/README.md)."""
    TOTK = os.path.join(os.path.dirname(__file__), '..', '..', '..', 'duo', 'patches', 'totk-1.4.3.duopatch.json')

    def setUp(self):
        self._env = os.environ.pop('DUO_PATCH', None)

    def tearDown(self):
        os.environ.pop('DUO_PATCH', None)
        if self._env is not None:
            os.environ['DUO_PATCH'] = self._env

    def _pack(self, **over):
        import json, tempfile
        p = {'format': 1, 'name': 't', 'game': 'g', 'version': '1', 'title_id': '0' * 16, 'main_build_id': 'ab' * 16,
             'camera': {'sites': ['0x10', '~0x20'], 'const': '0x30'}, 'canvas': [], 'author': 'a', 'checked': 'c'}
        p.update(over)
        f = tempfile.NamedTemporaryFile('w', suffix='.duopatch.json', delete=False)
        json.dump(p, f)
        f.close()
        os.environ['DUO_PATCH'] = f.name

    def test_no_pack_patches_nothing(self):
        # the research tables are never read: without a pack every game builds unpatched
        self.assertEqual(duo_aspect.sites_for('277178b7dba1b6d4949a84778d4abc58'), ([], None))
        self.assertEqual(duo_aspect.res_for('277178b7dba1b6d4949a84778d4abc58'), [])

    def test_the_shipped_totk_pack(self):
        os.environ['DUO_PATCH'] = self.TOTK
        sites, const = duo_aspect.sites_for('277178b7dba1b6d4949a84778d4abc58')
        self.assertEqual(sites, [(0x628c74, False), (0xb43460, False), (0x1ff04f4, False), (0x253fbb0, False)])
        self.assertIsNone(const)

    def test_inverse_sites_and_constant(self):
        self._pack()
        self.assertEqual(duo_aspect.sites_for('ab' * 16), ([(0x10, False), (0x20, True)], 0x30))

    def test_a_pack_for_another_build_stops_the_rewrite(self):
        # skipped silently, a build would look patched when it is not
        self._pack(main_build_id='cd' * 16)
        with self.assertRaises(SystemExit):
            duo_aspect.sites_for('ab' * 16)

    def test_an_unknown_format_is_refused(self):
        self._pack(format=2)
        with self.assertRaises(SystemExit):
            duo_aspect.sites_for('ab' * 16)


class Install(unittest.TestCase):
    def _run(self, img, sites_hex, text_end=0x4000):
        emitted = []
        puts = []
        original = duo_aspect.sites_for
        duo_aspect.sites_for = lambda bid: ([(int(x.lstrip('~'), 16), x.startswith('~')) for x in sites_hex.split(',')], None)
        try:
            n = duo_aspect.install_sites('x', img, text_end, 0x8000, lambda: 0x3000 + len(emitted),
                                   emitted.append, lambda off, words, why: puts.append((off, words)), None)
        finally:
            duo_aspect.sites_for = original
        return n, emitted, puts

    def test_installs_a_branch_per_site(self):
        img = bytearray(0x4000)
        struct.pack_into('<I', img, 0x1000, 0xbd400000)
        n, emitted, puts = self._run(img, '0x1000')
        self.assertEqual(n, 1)
        self.assertEqual(len(emitted), 8)
        self.assertEqual(puts[0][0], 0x1000)
        self.assertEqual(len(puts[0][1]), 1)

    def test_refuses_a_site_that_is_not_an_aspect_load(self):
        img = bytearray(0x4000)
        struct.pack_into('<I', img, 0x1000, 0xd503201f)   # nop
        with self.assertRaises(SystemExit):
            self._run(img, '0x1000')


class Res(unittest.TestCase):
    def test_asserts_both_words_and_writes_one(self):
        img = bytearray(0x100)
        struct.pack_into('<II', img, 0x40, 0x52808702, 0x9101c3e0)
        puts = []
        original = duo_aspect.res_for
        duo_aspect.res_for = lambda bid: [(0x40, 0x52808702, 0x9101c3e0, 0x5280a8c2, 0x9101c3e0)]
        try:
            def put(off, words, why):
                puts.append((off, words))
                for i, w in enumerate(words):
                    struct.pack_into('<I', img, off + 4 * i, w)
            n = duo_aspect.install_res('x', img, put, None)
        finally:
            duo_aspect.res_for = original
        self.assertEqual(n, 1)
        self.assertEqual(puts, [(0x40, [0x5280a8c2])])
        self.assertEqual(struct.unpack_from('<II', img, 0x40), (0x5280a8c2, 0x9101c3e0))

    def test_refuses_a_mismatched_neighbour(self):
        img = bytearray(0x100)
        struct.pack_into('<II', img, 0x40, 0x52808702, 0xdeadbeef)
        original = duo_aspect.res_for
        duo_aspect.res_for = lambda bid: [(0x40, 0x52808702, 0x9101c3e0, 0x5280a8c2, 0x9101c3e0)]
        try:
            with self.assertRaises(SystemExit):
                duo_aspect.install_res('x', img, lambda *a: None, None)
        finally:
            duo_aspect.res_for = original

class ConstStub(unittest.TestCase):
    """Builds without a frame-step state page: the site's s-register gets the ratio from a literal."""
    def test_stub_loads_the_ratio_into_the_sites_register_and_returns_after_it(self):
        from capstone import Cs, CS_ARCH_ARM64, CS_MODE_ARM
        site, at = 0x901640, 0x1b60000
        ins = 0x1e211800                                   # fdiv s0, s0, s1 (3D World's camera aspect)
        bits = struct.unpack('<I', struct.pack('<f', 2853 / 2007))[0]
        words = duo_aspect.const_stub(ins, at, site, bits)
        md = Cs(CS_ARCH_ARM64, CS_MODE_ARM)
        ldr = next(md.disasm(struct.pack('<I', words[0]), at))
        b = next(md.disasm(struct.pack('<I', words[1]), at + 4))
        self.assertEqual((ldr.mnemonic, ldr.op_str), ('ldr', f's0, #{at + 8:#x}'))
        self.assertEqual((b.mnemonic, b.op_str), ('b', f'#{site + 4:#x}'))
        self.assertEqual(words[2], bits)

    def test_keeps_the_destination_register(self):
        from capstone import Cs, CS_ARCH_ARM64, CS_MODE_ARM
        words = duo_aspect.const_stub(0xbd40b007, 0x2000, 0x1000, 0x3fb5f485)   # ldr s7, [x0, #0xb0]
        ldr = next(Cs(CS_ARCH_ARM64, CS_MODE_ARM).disasm(struct.pack('<I', words[0]), 0x2000))
        self.assertTrue(ldr.op_str.startswith('s7,'), ldr.op_str)

    def test_install_branches_each_site_to_its_stub(self):
        img = bytearray(0x4000)
        struct.pack_into('<I', img, 0x1000, 0x1e211800)   # fdiv s0, s0, s1
        area, puts, checked = [], [], []
        original = duo_aspect.sites_for
        duo_aspect.sites_for = lambda bid: ([(0x1000, False)], None)
        try:
            n = duo_aspect.install_sites_const('x', img, 0x4000, lambda: 0x3000 + 4 * len(area), area.append,
                                               lambda off, words, why: puts.append((off, words)), checked.append)
        finally:
            duo_aspect.sites_for = original
        self.assertEqual(n, 1)
        self.assertEqual(checked, [0x1000])
        self.assertEqual(puts, [(0x1000, [duo_aspect.branch(0x1000, 0x3000)])])
        self.assertEqual(len(area), 3)



class ConstStubPair(unittest.TestCase):
    """Engines that build the 16:9 value with movz + movk (Assassin's Creed): the pair becomes the ratio."""
    MOVZ = 0x52800000 | (0x8E39 << 5) | 8    # movz w8, #0x8e39
    MOVK = 0x72A00000 | (0x3FE3 << 5) | 8    # movk w8, #0x3fe3, lsl #16

    def test_recognises_the_pair_and_nothing_else(self):
        img = bytearray(0x20)
        struct.pack_into('<II', img, 0x10, self.MOVZ, self.MOVK)
        self.assertEqual(duo_aspect.movz_movk_form(img, 0x10), 8)
        other = bytearray(0x20)                                    # movz w8 + movk w9: not one constant
        struct.pack_into('<II', other, 0x10, self.MOVZ, self.MOVK & ~31 | 9)
        self.assertIsNone(duo_aspect.movz_movk_form(other, 0x10))
        single = bytearray(0x20)                                   # a movz alone is not a pair
        struct.pack_into('<II', single, 0x10, self.MOVZ, 0xD503201F)
        self.assertIsNone(duo_aspect.movz_movk_form(single, 0x10))
        self.assertIsNone(duo_aspect.movz_movk_form(bytearray(0x20), 0x10))   # zeros

    def test_stub_loads_the_ratio_into_the_pairs_register_and_returns_after_both(self):
        from capstone import Cs, CS_ARCH_ARM64, CS_MODE_ARM
        site, at = 0xff4ef0, 0x22d0000
        bits = struct.unpack('<I', struct.pack('<f', 2853 / 2007))[0]
        words = duo_aspect.const_stub_pair(at, site, bits, 8)
        md = Cs(CS_ARCH_ARM64, CS_MODE_ARM)
        ldr = next(md.disasm(struct.pack('<I', words[0]), at))
        b = next(md.disasm(struct.pack('<I', words[1]), at + 4))
        self.assertEqual((ldr.mnemonic, ldr.op_str), ('ldr', f'w8, #{at + 8:#x}'))
        self.assertEqual((b.mnemonic, b.op_str), ('b', f'#{site + 8:#x}'))   # after movz + movk
        self.assertEqual(words[2], bits)



class InverseSite(unittest.TestCase):
    """UE4 divides height by width on its default branch, so that site must get 1/ratio (DQ VII)."""
    def test_a_tilde_site_gets_the_reciprocal(self):
        img = bytearray(0x4000)
        struct.pack_into('<I', img, 0x1000, 0x1e21180a)     # fdiv s10, s0, s1
        area, puts = [], []
        original = duo_aspect.sites_for
        duo_aspect.sites_for = lambda bid: ([(0x1000, True)], None)
        try:
            duo_aspect.install_sites_const('x', img, 0x4000, lambda: 0x3000 + 4 * len(area), area.append,
                                           lambda off, words, why: puts.append((off, words)), lambda off: None)
        finally:
            duo_aspect.sites_for = original
        v = 2853 / 2007 if not os.environ.get('DM_DUO_ASPECT') else None
        lit = struct.unpack('<f', struct.pack('<I', area[2]))[0]
        self.assertAlmostEqual(lit, 2007 / 2853, places=5)
        self.assertAlmostEqual(lit * (2853 / 2007), 1.0, places=5)



if __name__ == '__main__':
    unittest.main()
