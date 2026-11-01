"""The public export's checks (duo/tools/make_public.py): a planted identifier is caught in text and binary files, and the
files that quote the patterns (the script itself, docs/PUBLISHING.md) do not trip them. No game files needed."""
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO / 'duo/tools'))
import make_public  # noqa: E402

UDID = '0000816' + '0-0000000000000000'   # split so this file holds no identifier itself


def failures(root):
    return {name: hits for name, hits in make_public.check(root) if hits}


class Checks(unittest.TestCase):
    def test_planted_identifier_is_caught(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            (root / 'notes.md').write_text('xcrun devicectl device info displays --device {}\n'.format(UDID))
            (root / 'shot.png').write_bytes(b'\x89PNG\0\0' + UDID.encode() + b'\0')
            hits = failures(root)
            self.assertEqual(list(hits), ['owner identifiers'])
            self.assertEqual(sorted(h.split(':')[0].split(' ')[0] for h in hits['owner identifiers']), ['notes.md', 'shot.png'])

    def test_files_quoting_the_patterns_pass(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            for rel in ('duo/tools/make_public.py', 'docs/PUBLISHING.md', 'dm/tools/tests/test_make_public.py'):
                (root / rel).parent.mkdir(parents=True, exist_ok=True)
                (root / rel).write_bytes((REPO / rel).read_bytes())
            self.assertEqual(failures(root), {})

    def test_refuses_the_repository_as_target(self):
        for t in (REPO, REPO / 'duo', REPO.parent):
            with self.assertRaises(SystemExit):
                make_public.safe_target(t)


if __name__ == '__main__':
    unittest.main()
