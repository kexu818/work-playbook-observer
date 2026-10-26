import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
from types import SimpleNamespace
import unittest
from unittest import mock

BASE = Path(__file__).parents[1]
spec = importlib.util.spec_from_file_location('codex_runner', BASE / 'backend/codex_runner.py')
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
spec = importlib.util.spec_from_file_location('history_portable', BASE / 'backend/history.py')
history = importlib.util.module_from_spec(spec)
spec.loader.exec_module(history)


class RunnerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.base = Path(self.temp.name)
        self.home = self.base / '.codex'
        self.home.mkdir()
        (self.home / 'auth.json').write_text('{"auth_mode":"chatgpt","test_only":true}')
        (self.home / 'config.toml').write_text('private_sentinel = "do-not-copy"\n')
        (self.home / 'AGENTS.md').write_text('private global instructions: do-not-copy')
        self.task = self.base / 'task.txt'
        self.task.write_text('Analyze this synthetic packet only.')
        self.cli = self.base / 'fake-codex'
        self.output = self.base / 'runtime'
        self.args = SimpleNamespace(cwd=self.base, task_file=self.task, output_dir=self.output,
                                    timeout=3, codex_bin=self.cli, sandbox='read-only')

    def tearDown(self):
        self.temp.cleanup()

    def fake(self, body):
        self.cli.write_text('#!' + sys.executable + '\n' + body)
        self.cli.chmod(0o700)

    def receipt(self):
        return json.loads((self.output / 'run.json').read_text())

    def test_isolated_copy_no_config_or_api_credentials_and_cleanup(self):
        before = (self.home / 'auth.json').read_bytes()
        self.fake('''import json, os, pathlib, sys
home = pathlib.Path(os.environ['CODEX_HOME'])
out = pathlib.Path(sys.argv[sys.argv.index('--output-last-message') + 1])
probe = {'files': sorted(p.name for p in home.iterdir()), 'argv': sys.argv,
         'api_env': [k for k in os.environ if k in ('OPENAI_API_KEY', 'CODEX_API_KEY', 'OPENAI_BASE_URL')]}
(out.parent / 'probe.json').write_text(json.dumps(probe))
(home / 'auth.json').write_text('refreshed temporary credential')
out.write_text('{"candidates":[],"note":"synthetic"}')
''')
        with mock.patch.dict(os.environ, {'OPENAI_API_KEY': 'fake-key', 'CODEX_API_KEY': 'fake-key', 'OPENAI_BASE_URL': 'https://invalid.example'}):
            self.assertEqual(runner.execute(self.args, self.home), 0)
        probe = json.loads((self.output / 'probe.json').read_text())
        self.assertEqual(probe['files'], ['AGENTS.md', 'auth.json'])
        self.assertEqual(probe['api_env'], [])
        self.assertIn('shell_tool', probe['argv'])
        self.assertIn('--ignore-user-config', probe['argv'])
        self.assertEqual((self.home / 'auth.json').read_bytes(), before)
        self.assertTrue(self.receipt()['isolated_home_removed'])
        self.assertTrue(self.receipt()['protected_unchanged'])
        self.assertEqual(self.output.stat().st_mode & 0o777, 0o700)

    def test_timeout_stops_child_and_removes_auth_copy(self):
        self.fake('import time\ntime.sleep(30)\n')
        self.args.timeout = 0.1
        self.assertEqual(runner.execute(self.args, self.home), 124)
        self.assertTrue(self.receipt()['timed_out'])
        self.assertTrue(self.receipt()['isolated_home_removed'])

    def test_non_subscription_auth_never_launches(self):
        (self.home / 'auth.json').write_text('{"auth_mode":"apikey"}')
        with mock.patch.object(runner.subprocess, 'Popen') as launch:
            self.assertEqual(runner.execute(self.args, self.home), 1)
            launch.assert_not_called()
        self.assertTrue(self.receipt()['isolated_home_removed'])

    def test_failed_launch_still_removes_credentials(self):
        self.assertEqual(runner.execute(self.args, self.home), 1)
        self.assertTrue(self.receipt()['isolated_home_removed'])

    def test_nonzero_exit_remains_failure(self):
        self.fake('raise SystemExit(7)\n')
        self.assertEqual(runner.execute(self.args, self.home), 7)
        self.assertTrue(self.receipt()['isolated_home_removed'])

    def test_sigterm_cleans_auth_and_stops_runner(self):
        self.fake('''import pathlib, sys, time
out = pathlib.Path(sys.argv[sys.argv.index('--output-last-message') + 1]).parent
(out / 'ready').write_text('synthetic')
time.sleep(30)
''')
        command = [sys.executable, str(BASE / 'backend/codex_runner.py'), '--cwd', str(self.base),
                   '--task-file', str(self.task), '--output-dir', str(self.output), '--codex-bin', str(self.cli)]
        process = subprocess.Popen(command, env=dict(os.environ, HOME=str(self.base)))
        try:
            until = time.monotonic() + 5
            while not (self.output / 'ready').exists() and time.monotonic() < until:
                time.sleep(0.02)
            self.assertTrue((self.output / 'ready').exists())
            process.terminate()
            self.assertEqual(process.wait(timeout=5), 143)
            self.assertTrue(self.receipt()['isolated_home_removed'])
        finally:
            if process.poll() is None:
                process.kill(); process.wait()

    def test_bundled_analysis_end_to_end_with_fake_cli(self):
        candidate = {'title': 'Synthetic workflow', 'problem': 'Synthetic problem', 'why': 'Fixture only',
                     'trigger': 'Test', 'steps': ['Check'], 'checks': ['Verified'], 'missing': [], 'sourceIds': ['e-1']}
        response = json.dumps({'candidates': [candidate], 'note': 'Fixture only'})
        self.fake('''import json, pathlib, sys
if sys.argv[1:3] == ['login', 'status']:
    print('Logged in using ChatGPT')
else:
    path = pathlib.Path(sys.argv[sys.argv.index('--output-last-message') + 1])
    path.write_text(%r)
''' % response)
        packet = {'window': {'start': '2026-10-26T00:00:00Z', 'end': '2026-10-26T01:00:00Z'},
                  'sources': [{'id': 'e-1', 'text': 'Synthetic task', 'type': 'event', 'at': '2026-10-26T00:30:00Z'}],
                  'coverage': {'totalEvents': 1, 'includedEvents': 1, 'totalSummaries': 0,
                               'includedSummaries': 0, 'textCharacters': 14, 'truncated': False}}
        with mock.patch.dict(os.environ, {'HOME': str(self.base), 'PLAYBOOK_CODEX_BIN': str(self.cli)}), mock.patch.object(history.Path, 'home', return_value=self.base):
            record = history.run_analysis(packet, self.base / 'data', runner=history.BUNDLED_RUNNER)
        self.assertEqual(record['candidates'][0]['status'], 'draft')
        self.assertTrue((self.base / 'data/state.json').is_file())
        receipt = json.loads((Path(record['path']) / 'runtime/run.json').read_text())
        self.assertTrue(receipt['isolated_home_removed'])


if __name__ == '__main__':
    unittest.main()
