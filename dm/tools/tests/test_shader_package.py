"""The shader split is reused on its key alone; a run stopped while splitting empties shader/pkg but leaves the key, so the
reuse must also see every package the profile's map names (Disney: a killed 3D World split left the shader step failing on a
missing package file)."""
import importlib.util
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]


def pipeline():
    spec = importlib.util.spec_from_file_location('build_ipa_from_nsp', REPO / 'scripts/build_ipa_from_nsp.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class Game:
    """The only part of a game profile packages_complete reads: a table path."""

    def __init__(self, map_path):
        self.map_path = map_path

    def table(self, name):
        return self.map_path if name == 'shader_map.tsv' else Path('/nonexistent') / name


class PackagesComplete(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.root = Path(self.dir.name)
        self.pkg = self.root / 'pkg'
        self.pkg.mkdir()
        self.map = self.root / 'shader_map.tsv'

    def tearDown(self):
        self.dir.cleanup()

    def check(self):
        return pipeline().packages_complete(Game(self.map), self.pkg)

    def test_a_complete_package_is_reused(self):
        self.map.write_text('# kind: evidence\npackage\tindex\tstage\tdm_ctl_sha16\tsource\n'
                            'vs_effect.bin\t0\tvs\t0123456789abcdef\tromfs:/a\nps_main.bin\t1\tps\t0123456789abcdef\tromfs:/b\n')
        (self.pkg / 'vs_effect.bin').write_bytes(b'a')
        (self.pkg / 'ps_main.bin').write_bytes(b'b')
        self.assertTrue(self.check())

    def test_an_emptied_package_is_not_reused(self):
        self.map.write_text('vs_effect.bin\t0\tvs\t0123456789abcdef\tromfs:/a\nps_main.bin\t1\tps\t0123456789abcdef\tromfs:/b\n')
        (self.pkg / 'vs_effect.bin').write_bytes(b'a')
        self.assertFalse(self.check(), 'a package the map names is missing: the split must run again')

    def test_a_game_without_a_map_is_not_held_back(self):
        self.assertTrue(self.check())

    def test_other_files_do_not_count(self):
        self.map.write_text('vs_effect.bin\t0\tvs\t0123456789abcdef\tromfs:/a\n')
        (self.pkg / 'vs_effect.bin').write_bytes(b'a')
        (self.pkg / 'notes.txt').write_text('x')
        self.assertTrue(self.check())


if __name__ == '__main__':
    unittest.main()
