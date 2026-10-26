#!/usr/bin/env python3
"""Subscription-only analysis runner with a disposable local Codex home.

No user configuration, instructions, hooks, plugins or MCP credentials are copied.
The app prefers an existing ke-codex-verify runner when one is installed.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time

SIGNALS = (signal.SIGTERM, signal.SIGINT, signal.SIGHUP)


def private_write(path, data):
    with path.open('xb') as stream:
        os.fchmod(stream.fileno(), 0o600)
        stream.write(data)


def fingerprint(home):
    return {name: hashlib.sha256((home / name).read_bytes()).hexdigest() if (home / name).is_file() else None
            for name in ('auth.json', 'config.toml')}


def stop_group(process):
    if process is None:
        return
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(process.pid, sig)
        except ProcessLookupError:
            pass
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            continue
    process.wait()


def execute(args, source_home=None):
    source_home = source_home or Path.home() / '.codex'
    os.umask(0o077)
    output = args.output_dir.absolute()
    output.mkdir(mode=0o700, exist_ok=False)
    record = {'ephemeral': True, 'sandbox': 'read-only', 'isolated_home_removed': True,
              'external_mcp_enabled': False, 'hooks_enabled': False, 'notifications_enabled': False}
    before = fingerprint(source_home)
    process = None
    code = 1
    started = time.monotonic()
    previous = {sig: signal.getsignal(sig) for sig in SIGNALS}

    def terminate(signum, frame):
        for sig in SIGNALS:
            signal.signal(sig, signal.SIG_IGN)
        raise SystemExit(128 + signum)

    try:
        for sig in SIGNALS:
            signal.signal(sig, terminate)
        auth_file = source_home / 'auth.json'
        auth_bytes = auth_file.read_bytes()
        auth = json.loads(auth_bytes)
        if auth.get('auth_mode') != 'chatgpt' or auth.get('OPENAI_API_KEY'):
            raise ValueError('ChatGPT file-based login is required; API-key fallback is disabled')
        prompt = args.task_file.read_bytes()
        with tempfile.TemporaryDirectory(prefix='.codex-home-', dir=output) as temp:
            home = Path(temp)
            record['isolated_home'] = str(home)
            private_write(home / 'auth.json', auth_bytes)
            private_write(home / 'AGENTS.md', b'Analyze only the supplied packet. Do not run tools or perform work.\n')
            command = [str(args.codex_bin), 'exec', '--ephemeral', '--json', '--skip-git-repo-check',
                       '--ignore-user-config', '--ignore-rules', '--cd', str(args.cwd),
                       '--sandbox', 'read-only', '--output-last-message', str(output / 'result.md'),
                       '--disable', 'shell_tool', '--disable', 'hooks',
                       '-c', 'approval_policy="never"', '-c', 'web_search="disabled"',
                       '-c', 'notify=[]', '-c', 'memories.use_memories=false',
                       '-c', 'memories.generate_memories=false', '-']
            allowed = ('PATH', 'HOME', 'TMPDIR', 'LANG', 'LC_ALL', 'TERM',
                       'SSL_CERT_FILE', 'SSL_CERT_DIR', 'HTTPS_PROXY', 'HTTP_PROXY', 'NO_PROXY')
            env = {key: os.environ[key] for key in allowed if key in os.environ}
            env['CODEX_HOME'] = str(home)
            try:
                with (output / 'events.jsonl').open('xb') as events, (output / 'runtime.stderr').open('xb') as errors:
                    process = subprocess.Popen(command, cwd=args.cwd, env=env, stdin=subprocess.PIPE,
                                               stdout=events, stderr=errors, start_new_session=True)
                    try:
                        process.communicate(prompt, timeout=args.timeout)
                        code = process.returncode
                    except subprocess.TimeoutExpired:
                        code = 124
                        record['timed_out'] = True
            finally:
                for sig in SIGNALS:
                    signal.signal(sig, signal.SIG_IGN)
                stop_group(process)
    except BaseException as error:
        record['error_type'] = type(error).__name__
        code = error.code if isinstance(error, SystemExit) and isinstance(error.code, int) else 1
    finally:
        record['protected_unchanged'] = before == fingerprint(source_home)
        record['isolated_home_removed'] = not Path(record.get('isolated_home', output / '.not-created')).exists()
        code = code if record['protected_unchanged'] else 2
        record.update(exit_code=code, duration_seconds=round(time.monotonic() - started, 3))
        private_write(output / 'run.json', (json.dumps(record, indent=2) + '\n').encode())
        for sig, handler in previous.items():
            signal.signal(sig, handler)
    return code


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cwd', type=Path, required=True)
    parser.add_argument('--task-file', type=Path, required=True)
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--sandbox', choices=['read-only'], default='read-only')
    parser.add_argument('--timeout', type=int, default=360)
    parser.add_argument('--codex-bin', type=Path, default=shutil.which('codex'))
    args = parser.parse_args()
    if args.timeout < 1 or args.codex_bin is None:
        parser.error('A positive timeout and a Codex CLI executable are required')
    return execute(args)


if __name__ == '__main__':
    raise SystemExit(main())
