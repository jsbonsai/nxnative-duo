"""bin/duo's .iso (ps2) path: the card's shape, `duo info`'s dispatch, the ps2build command line and its forwarded
events, the sentences its errors become, and doctor's PS2 items (docs/ARCHITECTURE.md §7 in the ps2-duo checkout).
The pipeline's tools are faked or mocked; no game image is read."""
import contextlib
import importlib.machinery
import importlib.util
import io
import json
import os
import tempfile
import types
import unittest
from pathlib import Path
from unittest import mock

REPO = Path(__file__).resolve().parents[3]


def load_duo():
    loader = importlib.machinery.SourceFileLoader('duo_cli', str(REPO / 'bin' / 'duo'))
    spec = importlib.util.spec_from_loader('duo_cli', loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


duo = load_duo()

INFO = {'platform': 'ps2', 'serial': 'SCUS-97399', 'title': 'God of War', 'region': 'NTSC-U', 'size_bytes': 8_522_792_960,
        'layers': 2, 'boot': 'SCUS_973.99', 'boot_crc': 'D6385328', 'boot_sha256': 'ec' * 32, 'boot_bytes': 1_911_580,
        'support': 'verified', 'support_notes': 'reaches in-game', 'profile': 'games/SCUS-97399/game.tsv', 'bios': 'no',
        'modules': 10, 'multielf': 10, 'patch_file': '_D6385328.pnach'}


def fake_root(tmp):
    """A ps2-duo-shaped folder: only the two tools this wrapper spawns have to exist."""
    root = Path(tmp) / 'ps2-duo'
    (root / 'tools').mkdir(parents=True)
    for name in ('ps2info', 'ps2build'):
        p = root / 'tools' / name
        p.write_text('#!/bin/sh\nexit 0\n')
        p.chmod(0o755)
    return root


class Case(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = Path(tmp.name)
        self.root = fake_root(self.tmp)
        self.iso = self.tmp / 'God of War (USA).iso'
        self.iso.write_bytes(b'ISO' * 8)
        self.out = self.tmp / 'out'
        patch = mock.patch.object(duo, 'ps2_root', return_value=str(self.root))
        patch.start()
        self.addCleanup(patch.stop)
        self.addCleanup(setattr, duo, 'JSON_OUT', duo.JSON_OUT)

    def run_cli(self, fn, args):
        """Run one command function: its stdout, its stderr, and the exit code it stopped with (0 when it returned)."""
        out, err = io.StringIO(), io.StringIO()
        code = 0
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            try:
                fn(args)
            except SystemExit as e:
                code = e.code
        return out.getvalue(), err.getvalue(), code


class InfoCard(Case):
    def info(self, payload, rc=0):
        with mock.patch.object(duo, 'capture', return_value=(rc, payload, '')):
            return duo.ps2_info(str(self.iso))

    def test_a_pretty_printed_document_is_parsed(self):
        self.assertEqual(self.info(json.dumps(INFO, indent=2))['serial'], 'SCUS-97399')

    def test_the_card_carries_the_shared_fields_and_ps2_verbatim(self):
        d = self.info(json.dumps(INFO, indent=2))
        card = duo.ps2_card(d, str(self.iso))
        self.assertEqual(card['game']['title'], 'SCUS-97399')
        self.assertEqual(card['game']['name'], 'God of War')
        self.assertEqual(card['game']['bytes'], INFO['size_bytes'])
        self.assertEqual(card['base'], {'file': str(self.iso), 'kind': 'iso', 'name': 'God of War'})
        self.assertEqual(card['support']['state'], 'verified')
        self.assertEqual(card['problems'], [])
        self.assertIs(card['ps2'], d)

    def test_every_documented_error_is_a_sentence_not_a_trace(self):
        for error in ('iso_missing', 'not_iso9660', 'no_system_cnf', 'no_boot2', 'no_boot_elf'):
            with self.subTest(error=error):
                payload = json.dumps({'error': error, 'message': 'raw ps2info text'})
                with mock.patch.object(duo, 'capture', return_value=(1, payload, '')):
                    out, err, status = self.run_cli(duo.cmd_ps2_info, types.SimpleNamespace(files=[str(self.iso)], json=False))
                self.assertEqual(status, 1)
                self.assertEqual(err.strip(), 'error: ' + duo.PS2_INFO_ERRORS[error])
                self.assertNotIn('Traceback', err)
                self.assertEqual(out, '')

    def test_exit_two_is_a_usage_error(self):
        payload = json.dumps({'error': 'iso_missing', 'message': 'x'})
        with mock.patch.object(duo, 'capture', return_value=(2, payload, '')):
            _, _, code = self.run_cli(duo.cmd_ps2_info, types.SimpleNamespace(files=[str(self.iso)], json=False))
        self.assertEqual(code, 2)

    def test_json_prints_the_card(self):
        with mock.patch.object(duo, 'capture', return_value=(0, json.dumps(INFO, indent=2), '')):
            out, _, code = self.run_cli(duo.cmd_ps2_info, types.SimpleNamespace(files=[str(self.iso)], json=True))
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(out)['ps2']['boot_crc'], 'D6385328')

    def test_duo_info_dispatches_an_iso_and_never_reads_keys(self):
        seen = []
        with mock.patch.object(duo, 'cmd_ps2_info', side_effect=seen.append):
            duo.cmd_info(types.SimpleNamespace(files=[str(self.iso)], keys=None, title_id=None, json=False))
        self.assertEqual(seen[0].files, [str(self.iso)])

    def test_a_package_and_an_iso_cannot_be_dropped_together(self):
        _, _, code = self.run_cli(duo.cmd_ps2_info, types.SimpleNamespace(files=[str(self.iso), '/tmp/game.nsp'], json=False))
        self.assertEqual(code, 2)

    def test_one_image_at_a_time(self):
        _, _, code = self.run_cli(duo.cmd_ps2_info, types.SimpleNamespace(files=[str(self.iso), str(self.iso)], json=False))
        self.assertEqual(code, 2)
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            duo.only_iso(['/tmp/one.iso', '/tmp/two.iso'])


class Build(Case):
    def args(self, **over):
        a = dict(iso=str(self.iso), game=None, out=str(self.out), install=False, device=None, bios=None, setting=[],
                 progress='lines')
        a.update(over)
        return types.SimpleNamespace(**a)

    def test_the_ps2build_command_line(self):
        cmd = duo.ps2_build_argv('/p', '/i.iso', 'SCUS-97399', '/o', ['scale=2', 'aspect=16:9'], '/b/sce.bin')
        self.assertEqual(cmd, ['/p/tools/ps2build', '--game', 'SCUS-97399', '--iso', '/i.iso', '--out', '/o',
                               '--progress', 'json', '--bios', '/b/sce.bin',
                               '--setting', 'scale=2', '--setting', 'aspect=16:9'])
        self.assertEqual(duo.ps2_build_argv('/p', '/i.iso', 'S', '/o')[-2:], ['--progress', 'json'])

    def test_the_pipelines_stages_nest_under_ours(self):
        seen = set()
        line = duo.ps2_progress_event({'event': 'stage', 'stage': 'translating', 'percent': 8, 'message': 'x'}, seen)
        self.assertEqual((line['ev'], line['k'], line['n'], line['sub']), ('stage', 3, len(duo.PS2_STAGES), True))
        self.assertIsNone(duo.ps2_progress_event({'event': 'stage', 'stage': 'translating'}, seen),
                          'a repeated stage is not announced twice')
        progress = duo.ps2_progress_event({'event': 'progress', 'stage': 'exploring', 'message': 'round 1'}, seen)
        self.assertEqual((progress['ev'], progress['k'], progress['note']), ('progress', 4, 'round 1'))
        self.assertIsNone(duo.ps2_progress_event({'event': 'done', 'stage': 'pipeline'}, seen))
        # the fields ProgressEvent.swift decodes; anything else would be dropped by the app
        decodable = {'ev', 'k', 'n', 'name', 'step', 'done', 'total', 'unit', 'est', 'note', 'frac', 'eta', 'elapsed', 'ok',
                     'summary', 'msg', 'sub'}
        self.assertLessEqual(set(line) | set(progress), decodable)
        self.assertIn(line['ev'], ('stage', 'step', 'progress', 'stage_end', 'say'))

    def test_the_build_runs_ps2build_with_the_serial_the_image_names(self):
        seen = []

        def run(cmd, cwd, on_event):
            seen.append((cmd, cwd))
            on_event({'event': 'stage', 'stage': 'translating', 'percent': 8, 'message': 'translating'})
            on_event({'event': 'done', 'stage': 'pipeline', 'status': 'ok', 'verdict': 'pass',
                      'binary': str(self.out / 'ps2run'), 'out': str(self.out)})
            return 0

        with mock.patch.object(duo, 'capture', return_value=(0, json.dumps(INFO, indent=2), '')), \
                mock.patch.object(duo, 'free_bytes', return_value=10**13), \
                mock.patch.object(duo, 'ps2_run', side_effect=run):
            out, _, _ = self.run_cli(duo.cmd_ps2_build, self.args(setting=['scale=2'], progress='json'))
        self.assertEqual(seen[0][0],
                         [str(self.root / 'tools' / 'ps2build'), '--game', 'SCUS-97399', '--iso', str(self.iso),
                          '--out', str(self.out), '--progress', 'json', '--setting', 'scale=2'])
        self.assertEqual(seen[0][1], str(self.root), 'ps2build runs from its own checkout')
        events = [json.loads(line) for line in out.splitlines()]
        self.assertEqual([e['name'] for e in events if e['ev'] == 'stage' and not e.get('sub')],
                         ['Reading the game', 'Rebuilding the game'])
        self.assertTrue(any(e.get('sub') is True and e['name'] == 'translating' for e in events))
        self.assertTrue(any(e['ev'] == 'stage_end' and e['k'] == 2 for e in events))

    def test_a_full_drive_stops_before_the_build(self):
        with mock.patch.object(duo, 'capture', return_value=(0, json.dumps(INFO, indent=2), '')), \
                mock.patch.object(duo, 'free_bytes', return_value=1 * 2**30), \
                mock.patch.object(duo, 'ps2_run') as run:
            _, _, code = self.run_cli(duo.cmd_ps2_build, self.args())
        self.assertEqual(code, 1)
        run.assert_not_called()

    def test_a_missing_bios_or_a_bare_setting_is_refused_before_building(self):
        with mock.patch.object(duo, 'capture', return_value=(0, json.dumps(INFO, indent=2), '')), \
                mock.patch.object(duo, 'free_bytes', return_value=10**13), \
                mock.patch.object(duo, 'ps2_run') as run:
            for a in (self.args(bios='/nope/sce.bin'), self.args(setting=['bogus'])):
                with self.subTest(args=a):
                    _, _, code = self.run_cli(duo.cmd_ps2_build, a)
                self.assertEqual(code, 2)
        run.assert_not_called()

    def test_the_build_errors_become_sentences(self):
        for code in ('iso_missing', 'no_profile', 'out_not_writable', 'bios_missing', 'bios_invalid', 'bash4_missing',
                     'translate_failed', 'vu_aot_failed', 'log_empty', 'link_failed'):
            with self.subTest(code=code):
                sentence = duo.ps2_build_failure(code, 'raw log line', 'SCUS-97399')
                self.assertTrue(sentence and '\n' not in sentence)
                self.assertNotIn('Traceback', sentence)
        self.assertIn('no profile', duo.ps2_build_failure('no_profile', '', 'SCUS-97399'))
        self.assertEqual(duo.ps2_build_failure('', 'the last line ps2build said'), 'the last line ps2build said')

    def test_the_reader_forwards_events_and_says_the_prose(self):
        script = self.root / 'tools' / 'ps2build'
        script.write_text('#!/bin/sh\n'
                          'echo "prose on stderr" >&2\n'
                          "printf '%s\\n' '{\"event\":\"stage\",\"stage\":\"translating\",\"percent\":8}'\n"
                          "printf '%s\\n' '{\"event\":\"done\",\"stage\":\"pipeline\",\"status\":\"ok\",\"verdict\":\"pass\"}'\n")
        script.chmod(0o755)
        events, said = [], []
        with mock.patch.object(duo, 'say', side_effect=said.append):
            rc = duo.ps2_run([str(script)], str(self.root), events.append)
        self.assertEqual(rc, 0)
        self.assertEqual([e['event'] for e in events], ['stage', 'done'])
        self.assertIn('prose on stderr', said)

    def test_install_stops_when_the_phone_cannot_hold_the_disc(self):
        device = {'udid': 'U', 'name': 'iPhone'}
        with mock.patch.object(duo, 'capture', return_value=(0, json.dumps(INFO, indent=2), '')), \
                mock.patch.object(duo, 'free_bytes', return_value=10**13), \
                mock.patch.object(duo, 'ps2_run', return_value=0), \
                mock.patch.object(duo, 'pick_device', return_value=device), \
                mock.patch.object(duo, 'personal_teams', return_value=[('TEAM', 'Name', True)]), \
                mock.patch.object(duo, 'apple_id_signed_in', return_value=True), \
                mock.patch.object(duo, 'ps2_phone_space', return_value=(1, 256 * 10**9)), \
                mock.patch.object(duo, 'ps2_app_build') as app_build:
            _, err, code = self.run_cli(duo.cmd_ps2_build, self.args(install=True))
        self.assertEqual(code, 2)
        self.assertIn('delete a game', err)
        app_build.assert_not_called()

    def test_install_needs_the_apple_id_in_xcode_not_only_a_team(self):
        device = {'udid': 'U', 'name': 'iPhone'}
        with mock.patch.object(duo, 'capture', return_value=(0, json.dumps(INFO, indent=2), '')), \
                mock.patch.object(duo, 'free_bytes', return_value=10**13), \
                mock.patch.object(duo, 'pick_device', return_value=device), \
                mock.patch.object(duo, 'personal_teams', return_value=[('TEAM', 'Name', True)]), \
                mock.patch.object(duo, 'apple_id_signed_in', return_value=False), \
                mock.patch.object(duo, 'ps2_run') as run, \
                mock.patch.object(duo, 'ps2_app_build') as app_build:
            _, err, code = self.run_cli(duo.cmd_ps2_build, self.args(install=True))
        self.assertEqual(code, 1)
        self.assertIn('sign in to Xcode once', err)
        run.assert_not_called()
        app_build.assert_not_called()

    def test_the_phone_is_checked_before_the_long_build(self):
        device = {'udid': 'U', 'name': 'iPhone'}
        with mock.patch.object(duo, 'capture', return_value=(0, json.dumps(INFO, indent=2), '')), \
                mock.patch.object(duo, 'free_bytes', return_value=10**13), \
                mock.patch.object(duo, 'pick_device', return_value=device), \
                mock.patch.object(duo, 'personal_teams', return_value=[('TEAM', 'Name', True)]), \
                mock.patch.object(duo, 'apple_id_signed_in', return_value=True), \
                mock.patch.object(duo, 'ps2_phone_space', return_value=(1, 256 * 10**9)), \
                mock.patch.object(duo, 'ps2_run') as run:
            _, err, code = self.run_cli(duo.cmd_ps2_build, self.args(install=True))
        self.assertEqual(code, 2)
        run.assert_not_called()


class Phone(Case):
    def test_the_app_id_names_ps2_and_the_serial(self):
        self.assertEqual(duo.ps2_bundle_id('SCUS-97399', 'TEAM123456'), 'org.nxnativeduo.team123456.ps2.scus97399')
        with mock.patch.dict(os.environ, {'DUO_PS2_BUNDLE_ID': 'org.example.ps2'}):
            self.assertEqual(duo.ps2_bundle_id('SCUS-97399', 'T'), 'org.example.ps2')

    def test_the_disc_lands_in_the_apps_documents(self):
        cmd = duo.ps2_copy_argv('UDID', 'org.example.ps2', '/games/God of War.iso')
        self.assertEqual(cmd[cmd.index('--domain-identifier') + 1], 'org.example.ps2')
        self.assertEqual(cmd[cmd.index('--destination') + 1], 'Documents/ps2.iso')
        self.assertEqual(cmd[cmd.index('--source') + 1], '/games/God of War.iso')

    def test_a_full_phone_reads_as_one_sentence_with_the_size(self):
        sentence = duo.ps2_copy_failure('ERROR: failed to copy: No space left on device', 9 * 2**30)
        self.assertIn('needs 9.0 GB', sentence)
        self.assertIn('delete a game', sentence)
        self.assertEqual(duo.ps2_copy_failure('', 0), 'the phone refused the copy')

    def test_the_free_space_figure_is_only_used_when_it_is_plausible(self):
        support = self.tmp / 'support'
        details = {'result': {'properties': {'hardware': {'internalStorageCapacity': 256_000_000_000},
                                             'storage': {'freeSpaceBytes': 90_000_000_000}}}}

        def capture(cmd, timeout=60, env=None):
            Path(cmd[cmd.index('--json-output') + 1]).write_text(json.dumps(details))
            return 0, '', ''

        with mock.patch.object(duo, 'SUPPORT', str(support)), mock.patch.object(duo, 'capture', side_effect=capture):
            self.assertEqual(duo.ps2_phone_space('UDID'), (90_000_000_000, 256_000_000_000))
        details['result']['properties']['storage']['freeSpaceBytes'] = 10**13     # a FUSE mount lying about the phone
        with mock.patch.object(duo, 'SUPPORT', str(support)), mock.patch.object(duo, 'capture', side_effect=capture):
            self.assertEqual(duo.ps2_phone_space('UDID'), (None, 256_000_000_000))

    def test_the_build_volume_follows_duo_ps2_out(self):
        with mock.patch.dict(os.environ, {'DUO_PS2_OUT': str(self.tmp / 'big')}):
            self.assertEqual(duo.ps2_volume(), str(self.tmp / 'big'))
            self.assertEqual(duo.ps2_out_default('SCUS-97399'), str(self.tmp / 'big' / 'SCUS-97399'))


class Doctor(Case):
    def doctor(self, root):
        quiet = (0, '', '')
        with mock.patch.object(duo, 'ps2_root', return_value=root), \
                mock.patch.object(duo, 'xcode_dir', return_value=None), \
                mock.patch.object(duo, 'which', return_value=None), \
                mock.patch.object(duo, 'capture', return_value=quiet), \
                mock.patch.object(duo, 'dotnet', return_value=None), \
                mock.patch.object(duo, 'pipeline_python', return_value=None), \
                mock.patch.object(duo, 'apple_id_signed_in', return_value=True), \
                mock.patch.object(duo, 'personal_teams', return_value=[]), \
                mock.patch.object(duo, 'devices', return_value=[]), \
                mock.patch.object(duo, 'find_keys', return_value=None), \
                mock.patch.object(duo, 'free_bytes', return_value=10**13), \
                mock.patch.object(duo, 'ps2_tools_state', return_value=(True, 'ready')), \
                mock.patch.object(duo, 'ps2_volume', return_value='/big'):
            return duo.doctor()

    def test_ps2_items_appear_only_where_the_pipeline_is_installed(self):
        without = {i['id'] for i in self.doctor(None)['items']}
        self.assertNotIn('ps2-tools', without)
        self.assertNotIn('ps2-space', without)
        with_root = {i['id'] for i in self.doctor(str(self.root))['items']}
        self.assertIn('ps2-tools', with_root)
        self.assertIn('ps2-space', with_root)

    def test_the_fix_is_the_one_brew_line_the_contract_names(self):
        with mock.patch.object(duo, 'which', side_effect=lambda t: '/opt/homebrew/bin/brew' if t == 'brew' else None), \
                mock.patch.object(duo, 'stream', return_value=0) as streamed, \
                contextlib.redirect_stdout(io.StringIO()):
            duo.cmd_fix(types.SimpleNamespace(item='ps2-tools', json=False))
        self.assertEqual(streamed.call_args[0][0], ['/opt/homebrew/bin/brew', 'install', 'bash', 'cmake', 'ninja', 'xcodegen'])


if __name__ == '__main__':
    unittest.main()
