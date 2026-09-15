#!/usr/bin/env python3
"""Run recorded isolated FAF cases to result or a simulation-time cap."""
import argparse
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import time

def stop_test_game(log):
    """Signal only the game explicitly launched with this unique test log."""
    stopped = []
    for entry in Path('/proc').iterdir():
        if not entry.name.isdigit(): continue
        try:
            words = [part.decode(errors='replace') for part in (entry / 'cmdline').read_bytes().split(b'\0') if part]
            if not words or not words[0].lower().endswith('forgedalliance.exe'): continue
            if '/log' not in words: continue
            index = words.index('/log')
            if index + 1 >= len(words) or words[index + 1] != str(log): continue
            descriptor = os.pidfd_open(int(entry.name))
            try: signal.pidfd_send_signal(descriptor, signal.SIGTERM)
            finally: os.close(descriptor)
            stopped.append(int(entry.name))
        except (OSError, ProcessLookupError, PermissionError): continue
    return stopped

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('case', choices=['detach', 'lifecycle', 'naval', 'sweepwing', 'series'])
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--seconds', type=int, default=2400)
args = parser.parse_args()
if args.case == 'detach':
    # Stop only this verifier's Python controller. Its FAF child owns a separate
    # session; leave every game and Wine service untouched.
    for entry in Path('/proc').iterdir():
        if not entry.name.isdigit() or int(entry.name) == os.getpid(): continue
        try: command = (entry / 'cmdline').read_bytes().split(b'\0')
        except (OSError, PermissionError): continue
        words = [part.decode(errors='replace') for part in command if part]
        if len(words) > 2 and Path(words[0]).name.startswith('python') and Path(words[1]).name == 'verify-runtime.py' and str(args.output) in words:
            os.kill(int(entry.name), signal.SIGTERM)
            print('Detached verifier controller ' + entry.name + '; game processes untouched', flush=True)
    raise SystemExit(0)
args.output.mkdir(parents=True, exist_ok=True)
root = Path(__file__).resolve().parents[1]
series = [('sweepwing', 'sweepwing_sanctum.v0003', 1), ('sentry', 'SCMP_018', 1),
          ('isis', 'SCMP_015', 1), ('syrtis', 'SCMP_017', 1), ('sludge', 'SCMP_037', 1),
          ('crossfire', 'SCMP_024', 2)]
cases = series if args.case == 'series' else [series[0] if args.case == 'sweepwing' else
    (args.case, 'SCMP_037' if args.case == 'naval' else 'SCMP_007', 1)]
for name, map_name, teams in cases:
    log = args.output / (name + '.log')
    if log.exists():
        raise SystemExit(f'Refusing to overwrite {log}')
    env = dict(os.environ, FAF_WRAPPER='/var/home/andreas/faf-linux/launchwrapper',
               FAF_EXE='/var/home/andreas/.faforever/bin/ForgedAlliance.exe', FAF_PREFS='RedQueenSmoke.prefs',
               FAF_FIXED_RUNTIME='1', FAF_PRODUCTION_TRACE='1', FAF_MIXED=str(teams))
    if args.case == 'lifecycle': env['FAF_LIFECYCLE_FIXTURE'] = '1'
    if args.case == 'naval': env['FAF_DEFENSE_FIXTURE'] = '1'
    with (args.output / (name + '.launcher.log')).open('w') as out:
        process = subprocess.Popen([str(root / 'scripts/run-smoke.sh'), map_name, str(log)], cwd=root,
                                   env=env, stdout=out, stderr=subprocess.STDOUT, start_new_session=True)
        started = time.monotonic()
        reason = 'process-exit'
        text = ''
        while process.poll() is None:
            time.sleep(2)
            text = log.read_text(errors='replace') if log.exists() else ''
            if 'GameEnded' in text:
                reason = 'outcome'
                time.sleep(5)  # collect result/stat notifications and cleanup failures
                break
            ticks = [int(n) for n in re.findall(r'production trace tick=(\d+)', text)]
            if ticks and max(ticks) >= args.seconds * 10:
                reason = 'time-capped'
                break
            if time.monotonic() - started > max(180, args.seconds * 3):
                reason = 'wall-time-abort'
                break
            attributed_error = re.search(r'Error running lua script:[^\n]*theredqueen', text, re.I)
            if attributed_error or 'production trace unavailable' in text or re.search(r'\[RedQueen\]\[ERROR\]', text):
                reason = 'error-abort'
                break
        if process.poll() is None:
            stopped = stop_test_game(log)
            try: process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                # Never signal a container, process group, or shared Wine server.
                print('Test wrapper remains running; left untouched', flush=True)
    result = {'case': name, 'map': map_name, 'teams': teams, 'stop': reason, 'exit': process.returncode,
              'wall_seconds': round(time.monotonic() - started, 1)}
    (args.output / (name + '.result.json')).write_text(json.dumps(result, indent=2) + '\n')
    for script in ['analyze-log.py', 'analyze-production-trace.py']:
        with (args.output / (name + '.' + script + '.txt')).open('w') as out:
            subprocess.run(['python3', str(root / 'scripts' / script), str(log)], stdout=out, stderr=subprocess.STDOUT)
    print(json.dumps(result), flush=True)
    if reason not in ['outcome', 'time-capped']: break
