"""Avalanche Software's zips (end record first) and the .tfx effect files in them (Toy Story 3), without game data: every member is read, and each control section takes the code area
right before it."""
import contextlib
import io
from pathlib import Path
import shutil
import struct
import sys
import tempfile
import unittest
import zipfile
import zlib

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import shader_split as split


def shader(stage, tag):
    """A code area and the control section after it: GLSLC's full header (control +0x20 past 0x880), +0x704 the code area's length"""
    ctl, code = bytearray(0x928), bytearray(0x100)
    ctl[:4] = split.CTL_MAGIC
    struct.pack_into('<I', ctl, 0x20, len(ctl))
    struct.pack_into('<I', ctl, 0x704, len(code))
    ctl[0x100] = tag
    code[:4] = split.GFX_MAGIC
    struct.pack_into('<I', code, 0x30, (1 if stage == 'vs' else 5) << 10 | 1)
    if stage == 'ps': code[0x30 + 4 * 6] = 0xff   # SPH input map: reads generic attribute 0 (pixel_input_cover)
    return bytes(ctl), bytes(code)


def tfx(*shaders, pad=3):
    """A .tfx: its first word, a few bytes of tree, then each shader's code area and control section, unaligned"""
    d = split.AVA_TFX + b'\x3f\x8c\xcc\xcd' + b'Shaders\0Shader\0VS\0ByteOffset\0PS\0' + bytes(pad)
    for ctl, code in shaders: d += code + ctl + b'\0'
    return d


def front_zip(members, method=8):
    """A zip as Avalanche writes it: the end record at 0, the central directory right after it, then the local headers and data, and the same end record at the end"""
    cd, body = b'', b''
    names = list(members)
    base = 22 + sum(46 + len(n.encode()) for n in names)
    for name, d in members.items():
        n, c = name.encode(), (zlib.compress(d)[2:-4] if method == 8 else d)
        cd += struct.pack('<4s6H3I5H2I', b'PK\x01\x02', 20, 20, 0, method, 0, 0, 0, len(c), len(d), len(n), 0, 0, 0, 0, 0, base + len(body)) + n
        body += struct.pack('<4s5H3I2H', b'PK\x03\x04', 20, 0, method, 0, 0, 0, len(c), len(d), len(n), 0) + n + c
    end = struct.pack('<4s4H2IH', b'PK\x05\x06', 0, 0, len(names), len(names), len(cd), 22, 0)
    return end + cd + body + end


class FrontZip(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp(prefix='avalanche')); self.addCleanup(shutil.rmtree, self.dir, True)

    def write(self, name, data):
        p = self.dir / name; p.write_bytes(data); return str(p)

    def test_zipfile_refuses_the_layout(self):   # why the split reads these itself
        p = self.write('a.zip', front_zip({'a.txt': b'x' * 100}))
        with self.assertRaises(zipfile.BadZipFile): zipfile.ZipFile(p)

    def test_every_member_is_read(self):
        members = {'effects/a.tfx': tfx(shader('vs', 1), shader('ps', 2)), 'a.oct': b'\0' * 300, 'b.tfx': b'not one'}
        for method in (8, 0):
            with self.subTest(method=method):
                p = self.write('fx.zip', front_zip(members, method))
                with open(p, 'rb') as f:
                    index = split.front_zip_index(f, 'fx.zip')
                    self.assertEqual(list(index), list(members))
                    for nm, ent in index.items(): self.assertEqual(split.front_zip_member(f, ent, nm), members[nm])

    def test_the_split_reads_its_shaders(self):
        vs, ps = shader('vs', 1), shader('ps', 2)
        p = self.write('fx.zip', front_zip({'effects/a.tfx': tfx(vs, ps), 'b.oct': b'\0' * 64}))
        jobs, taken = split.zip_jobs([(p, 'assets/fx.zip')])
        self.assertEqual(taken, {p})
        self.assertEqual({j[2][0] for j in jobs}, {split.ZIP_FRONT})   # members in ranges of about equal length
        found = {}
        for j in jobs: found.update(split.scan_file(j)[1])
        self.assertEqual(set(found), {split.skey(*vs), split.skey(*ps)})
        self.assertEqual(sorted(v[1] for v in found.values()), ['ps', 'vs'])
        self.assertTrue(all(v[0].startswith('/assets/fx.zip/effects/a.tfx#TFX@') for v in found.values()))
        self.assertEqual(found[split.skey(*vs)][2:], vs)   # the control section whole, the code area as it is

    def test_a_directory_that_does_not_read_is_scanned_as_one_file(self):
        d = bytearray(front_zip({'a.tfx': b'x'})); d[22:26] = b'XXXX'
        p = self.write('bad.zip', bytes(d))
        out = io.StringIO()
        with contextlib.redirect_stdout(out): jobs, taken = split.zip_jobs([(p, 'bad.zip')])
        self.assertEqual((jobs, taken), ([], set()))
        self.assertIn('central directory entry 0', out.getvalue())


class Tfx(unittest.TestCase):
    def test_code_right_before_each_control_section(self):
        vs, ps = shader('vs', 1), shader('ps', 2)
        for pad in range(4):   # unaligned control sections
            with self.subTest(pad=pad):
                found = split.tfx_shaders(tfx(vs, ps, pad=pad), 'a.tfx')
                self.assertEqual([(f[1], f[2], f[3]) for f in found], [('vs', *vs), ('ps', *ps)])

    def test_a_section_without_its_code_area_is_left_out(self):
        vs, (ctl, _) = shader('vs', 1), shader('ps', 2)
        d = tfx(vs) + b'\0' * 0x40 + ctl   # no code area before the second control section
        out = io.StringIO()
        with contextlib.redirect_stdout(out): found = split.tfx_shaders(d, 'a.tfx')
        self.assertEqual([f[1] for f in found], ['vs'])
        self.assertIn('no code area right before it; left out', out.getvalue())

    def test_a_cut_section_is_left_out(self):
        vs = shader('vs', 1)
        d = tfx(vs)[:-0x200]   # the control section runs past the end
        with contextlib.redirect_stdout(io.StringIO()): self.assertEqual(split.tfx_shaders(d, 'a.tfx'), [])

    def test_scan_blob_takes_it_by_its_first_word(self):
        out = []; split.scan_blob(tfx(shader('ps', 3)), 'x.tfx', out)
        self.assertEqual([o[1] for o in out], ['ps'])

    def test_vertex_shaders_get_the_pixel_cover(self):
        vs, ps = shader('vs', 1), shader('ps', 2)
        keys = {split.skey(c, k): (w, s, c, k) for w, s, c, k in split.tfx_shaders(tfx(vs, ps), 'a.tfx')}
        pairs, cover = split.separable_pairs(keys)
        self.assertEqual(pairs, {(split.skey(*vs), split.skey(*ps))})


if __name__ == '__main__':
    unittest.main()
