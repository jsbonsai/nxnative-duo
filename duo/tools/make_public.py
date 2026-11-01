#!/usr/bin/env python3
"""make_public.py — export this repository's HEAD as the public tree, check it, and optionally commit it fresh.

    make_public.py [--target DIR] [--force] [--commit] [--version vX.Y.Z] [--author "Name <email>"]

1. `git archive HEAD` of this repository is unpacked into DIR (default: ../nxnative-duo-public beside the repository).
   DIR must be empty or absent; --force empties it first, keeping only its .git.
2. The checks of docs/PUBLISHING.md §1 run against the exported files: no game files, keys, build outputs or signing
   material; no home-directory paths, tokens or private keys in text; no CI secrets; none of the owner's identifiers
   (in any file, binary or not).
3. --commit (only when every check passed): one commit "nxnative-duo <version>: experimental iPhone Duo fork of
   nxnative" on branch main, with no parent: the history starts again each time (an existing .git keeps its remotes).
   The author is --author, never the Mac's git identity.

Prints one line per check; exits 1 when any check fails. Only uncommitted changes are left out (it exports HEAD).
Python 3.9+, standard library only.
"""
import argparse
import io
import os
import re
import shutil
import subprocess
import sys
import tarfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
DEFAULT_AUTHOR = 'nxnative-duo <nxnative-duo@users.noreply.github.com>'

# Each pattern is written so that it does not match its own text (the [x] classes), so this file and
# docs/PUBLISHING.md, which quote them, pass their own checks.
IDENTIFIERS = re.compile(r'0000816[0]-|0000814[0]-|anmolsing[h]|jsbonsa[i]|james\.stings|4qgg47c2f[2]|EJ592MXD4[H]'
                         r'|/Volumes/(T5-500[B]|SD12[8])|Rosevill[e]', re.I)
HOME_PATH = re.compile(r'/User[s]/')
TOKENS = re.compile(r'(gh[p]_|github_pa[t]_|sk-[A-Za-z0-9]{20}|AKIA[0-9A-Z]{16}|BEGIN [A-Z ]*PRIVATE KE[Y])')
GAME_FILES = re.compile(r'\.(nsp|xci|nsz|xcz|nca|nro|kip|romfs)$|romfs\.img$', re.I)
KEY_FILES = re.compile(r'prod\.keys|title\.keys|\.keys$', re.I)
BUILD_FILES = re.compile(r'\.(ipa|app|mobileprovision|provisionprofile|p12|pem|cer|xcarchive)$', re.I)


def git(*args, cwd=REPO, env=None, data=None):
    r = subprocess.run(['git', *args], cwd=str(cwd), env=env, input=data, capture_output=True)
    if r.returncode:
        sys.exit('git {}: {}'.format(' '.join(args[:2]), r.stderr.decode(errors='replace').strip()))
    return r.stdout


def safe_target(target):
    """Refuse a target that is, or holds, this repository, or is the filesystem root or the home folder."""
    t = target.resolve()
    if t in (Path('/'), Path.home().resolve()) or t == REPO or t in REPO.parents or REPO in t.parents:
        sys.exit('refusing target {}: it is this repository, inside it, above it, or the home folder'.format(t))
    return t


def prepare(target, force):
    if target.exists() and not target.is_dir():
        sys.exit('{} exists and is not a folder'.format(target))
    target.mkdir(parents=True, exist_ok=True)
    entries = [p for p in target.iterdir()]
    if entries and not force:
        sys.exit('{} is not empty: use --force to replace its files (its .git is kept)'.format(target))
    for p in entries:
        if p.name == '.git':
            continue
        if p.is_dir() and not p.is_symlink():
            shutil.rmtree(p)
        else:
            p.unlink()


def export(target):
    data = git('archive', '--format=tar', 'HEAD')
    with tarfile.open(fileobj=io.BytesIO(data)) as tar:
        if hasattr(tarfile, 'data_filter'):
            tar.extractall(str(target), filter='data')
        else:
            tar.extractall(str(target))
    return git('rev-parse', '--short', 'HEAD').decode().strip()


def files(root):
    for d, dirs, names in os.walk(str(root)):
        dirs[:] = [x for x in dirs if not (Path(d) == root and x == '.git')]
        for x in dirs:
            yield Path(d, x).relative_to(root), True
        for x in names:
            yield Path(d, x).relative_to(root), False


def is_text(blob):
    return b'\0' not in blob[:8000]


def line_hits(rel, blob, pattern, out, limit=10):
    for n, line in enumerate(blob.decode('utf-8', errors='replace').split('\n'), 1):
        if pattern.search(line) and len(out) < limit:
            out.append('{}:{}: {}'.format(rel, n, line.strip()[:160]))


def check(root):
    """[(name, hits)] for the exported tree; a check passes when its hits are empty."""
    found = {k: [] for k in ('game files', 'keys', 'build outputs and signing material', 'home-directory paths',
                             'tokens and private keys', 'CI secrets', 'owner identifiers')}
    for rel, is_dir in files(root):
        name = rel.as_posix()
        if GAME_FILES.search(name) and not is_dir:
            found['game files'].append(name)
        if KEY_FILES.search(name) and not is_dir:
            found['keys'].append(name)
        if BUILD_FILES.search(name):
            found['build outputs and signing material'].append(name)
        if IDENTIFIERS.search(name):
            found['owner identifiers'].append(name + ' (file name)')
        path = root / rel
        if is_dir or path.is_symlink():
            continue
        blob = path.read_bytes()
        if is_text(blob):
            line_hits(name, blob, HOME_PATH, found['home-directory paths'])
            line_hits(name, blob, TOKENS, found['tokens and private keys'])
            if rel.parts[0] == '.github':
                line_hits(name, blob, re.compile(r'secrets\.'), found['CI secrets'])
            line_hits(name, blob, IDENTIFIERS, found['owner identifiers'])
        elif IDENTIFIERS.search(blob.decode('latin-1')):
            found['owner identifiers'].append(name + ' (binary)')
    return list(found.items())


def commit(target, version, author):
    m = re.fullmatch(r'\s*(.+?)\s*<([^<>\s]+@[^<>\s]+)>\s*', author)
    if not m:
        sys.exit('--author must look like "Name <email>"')
    if IDENTIFIERS.search(author):
        sys.exit('--author carries an owner identifier')
    env = dict(os.environ, GIT_AUTHOR_NAME=m.group(1), GIT_AUTHOR_EMAIL=m.group(2),
               GIT_COMMITTER_NAME=m.group(1), GIT_COMMITTER_EMAIL=m.group(2))
    if not (target / '.git').exists():
        git('init', '-q', cwd=target)
    git('add', '-A', cwd=target)
    tree = git('write-tree', cwd=target).decode().strip()
    message = 'nxnative-duo {}: experimental iPhone Duo fork of nxnative\n'.format(version)
    sha = git('commit-tree', tree, cwd=target, env=env, data=message.encode()).decode().strip()   # no parent: a new root
    git('update-ref', 'refs/heads/main', sha, cwd=target)
    git('symbolic-ref', 'HEAD', 'refs/heads/main', cwd=target)
    git('reset', '-q', cwd=target)
    for ref in git('for-each-ref', '--format=%(refname)', 'refs/heads', 'refs/tags', cwd=target).decode().split():
        if ref != 'refs/heads/main':
            git('update-ref', '-d', ref, cwd=target)
    git('reflog', 'expire', '--expire=now', '--all', cwd=target)
    git('gc', '-q', '--prune=now', cwd=target)
    meta = git('log', '-1', '--format=%an <%ae> %cn <%ce>', cwd=target).decode()
    if IDENTIFIERS.search(meta) or git('rev-list', '--count', '--all', cwd=target).decode().strip() != '1':
        sys.exit('the new commit is not a single clean root commit: {}'.format(meta.strip()))
    return sha[:12]


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--target', type=Path, default=REPO.parent / 'nxnative-duo-public')
    ap.add_argument('--force', action='store_true', help='empty a non-empty target first (its .git is kept)')
    ap.add_argument('--commit', action='store_true', help='make one fresh root commit on main when every check passes')
    ap.add_argument('--version', default='v0.1.0')
    ap.add_argument('--author', default=DEFAULT_AUTHOR)
    a = ap.parse_args(argv)
    target = safe_target(a.target)
    if git('status', '--porcelain').strip():
        print('note: this checkout has uncommitted changes; they are not exported (HEAD is)')
    prepare(target, a.force)
    head = export(target)
    print('exported {} at {} → {}'.format(REPO.name, head, target))
    failed = 0
    for name, hits in check(target):
        print('{} {}'.format('PASS' if not hits else 'FAIL', name))
        for h in hits:
            print('     ' + h)
        failed += bool(hits)
    if failed:
        print('{} check(s) failed: nothing committed'.format(failed))
        return 1
    if a.commit:
        print('committed {} on main in {}'.format(commit(target, a.version, a.author), target))
    print('all checks passed')
    return 0


if __name__ == '__main__':
    sys.exit(main())
