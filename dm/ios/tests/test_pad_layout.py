"""Compile and run the layout editor's model (DmPadLayout.m) on macOS: storage, migration, clamps, pinch target. No simulator or UI required."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[3]


@unittest.skipUnless(sys.platform == 'darwin' and shutil.which('xcrun'), 'needs the macOS toolchain')
class PadLayoutTests(unittest.TestCase):
    def test_pad_layout_model(self):
        with tempfile.TemporaryDirectory() as tmp:
            exe = Path(tmp) / 'pad_layout_check'
            c = subprocess.run(['xcrun', '-sdk', 'macosx', 'clang', '-fobjc-arc', '-Wall', '-Werror', '-I', str(REPO / 'dm/ios/Sources'),
                                str(REPO / 'dm/ios/Sources/DmPadLayout.m'), str(Path(__file__).with_name('pad_layout_check.m')),
                                '-framework', 'Foundation', '-framework', 'CoreGraphics', '-o', str(exe)], capture_output=True, text=True, timeout=300)
            self.assertEqual(c.returncode, 0, c.stdout + c.stderr)
            r = subprocess.run([str(exe)], capture_output=True, text=True, timeout=60)
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            self.assertIn('pad layout: 0 failed', r.stdout)


if __name__ == '__main__':
    unittest.main()
