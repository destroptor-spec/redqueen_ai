import argparse
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import time
import zipfile

parser = argparse.ArgumentParser(description='Verify observation fixes against native FAF orders')
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
ROOT = Path(__file__).resolve().parents[1]
OUT = args.output.resolve()
OUT.mkdir(parents=True, exist_ok=True)
OVERLAY = OUT / 'overlay'
LOG = OUT / 'game.log'
BINARY = Path('/home/andreas/.faforever/bin')
MOD = Path('/var/home/andreas/My Games/Gas Powered Games/Supreme Commander Forged Alliance/mods/TheRedQueen')
assert MOD.is_symlink() and MOD.resolve() == ROOT.resolve()
assert not LOG.exists(), 'Refusing to overwrite existing evidence'
env = dict(os.environ, FAF_RQ_FACTION='1', FAF_OPP_FACTION='3', FAF_SEED='2071971', FAF_MIXED='1')
init = subprocess.check_output(['python3', str(ROOT / 'scripts/prepare-runtime.py'), str(BINARY), str(OVERLAY), '1'], cwd=ROOT, env=env, text=True).strip()
with zipfile.ZipFile(BINARY.parent / 'gamedata/lua.nx2') as archive:
    sim = archive.read('lua/simInit.lua').decode()
sim += "\nlocal RQObservationOriginalBeginSession = BeginSession\nfunction BeginSession()\n    RQObservationOriginalBeginSession()\n    ForkThread(import('/lua/rq-observation-fixture.lua').Run)\nend\n"
(OVERLAY / 'lua/simInit.lua').write_text(sim)
(OVERLAY / 'lua/rq-observation-fixture.lua').write_bytes((ROOT / 'tests/runtime/observation_fixes.lua').read_bytes())
source_path = OVERLAY / 'sources.json'
sources = json.loads(source_path.read_text())
sources['overlay'] = {str(p.relative_to(OVERLAY)): hashlib.sha256(p.read_bytes()).hexdigest() for p in OVERLAY.rglob('*.lua')}
source_path.write_text(json.dumps(sources, indent=2) + '\n')
env.update(FAF_WRAPPER='/var/home/andreas/faf-linux/launchwrapper', FAF_EXE=str(BINARY / 'ForgedAlliance.exe'), FAF_PREFS='RQTest1.prefs', FAF_INIT=init, FAF_FIXED_RUNTIME='0')
started = time.monotonic()
stopped = []
reason = 'timeout'
with (OUT / 'launcher.log').open('w') as output:
    process = subprocess.Popen([str(ROOT / 'scripts/run-smoke.sh'), 'SCMP_018', str(LOG)], cwd=ROOT, env=env, stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
    try:
        while time.monotonic() - started < 240:
            content = LOG.read_text(errors='replace') if LOG.exists() else ''
            if '[RQObservationFixes] PASS ' in content:
                reason = 'pass'
                break
            if '[RQObservationFixes] FAIL ' in content:
                reason = 'fixture-failed'
                break
            if process.poll() is not None:
                reason = 'process-exit'
                break
            time.sleep(1)
    finally:
        # Never signal the wrapper or a Wine service. Require executable,
        # /redqueen, and this exact /log before opening a pidfd.
        for line in subprocess.check_output(['ps', '-eo', 'pid,comm'], text=True).splitlines()[1:]:
            pid, name = line.split(None, 1)
            if not name.startswith('ForgedAlliance'):
                continue
            try:
                words = [w.decode(errors='replace') for w in (Path('/proc') / pid / 'cmdline').read_bytes().split(b'\0') if w]
                if not words or not words[0].lower().endswith('forgedalliance.exe') or '/redqueen' not in words or '/log' not in words:
                    continue
                index = words.index('/log')
                if index + 1 >= len(words) or words[index + 1] != str(LOG):
                    continue
                descriptor = os.pidfd_open(int(pid))
                try:
                    signal.pidfd_send_signal(descriptor, signal.SIGTERM)
                finally:
                    os.close(descriptor)
                stopped.append(int(pid))
            except (OSError, ProcessLookupError, PermissionError):
                continue
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            print('Wrapper still running; left untouched', flush=True)
manifest_path = Path(str(LOG) + '.manifest.json')
manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
changed = [name for name, digest in manifest.get('files', {}).items() if hashlib.sha256((ROOT / name).read_bytes()).hexdigest() != digest]
result = {'reason': reason, 'wall_seconds': round(time.monotonic() - started, 1), 'stopped_pids': stopped, 'changed_payload_files': changed}
(OUT / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result), flush=True)
if LOG.exists():
    with (OUT / 'analysis.txt').open('w') as output:
        analysis = subprocess.run(['python3', str(ROOT / 'scripts/analyze-log.py'), str(LOG)], cwd=ROOT, stdout=output, stderr=subprocess.STDOUT)
    if analysis.returncode:
        reason = 'analysis-failed'
raise SystemExit(0 if reason == 'pass' and not changed else 1)
