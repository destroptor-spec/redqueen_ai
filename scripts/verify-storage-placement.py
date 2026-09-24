#!/usr/bin/env python3
"""Run one bounded native storage fixture without installing the candidate.

Creates and validates a local candidate clone, then loads only its placement
module and hook through an isolated runtime overlay. The active mod stays on
the control. This is construction evidence, not a balance match.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import time
import zipfile


ROOT = Path(__file__).resolve().parents[1]
CONTROL = "24c0b34595dc28d08f1220b3a3b4db92f7262731b7d5b093e808397270d8dac5"
MOD = Path("/var/home/andreas/My Games/Gas Powered Games/Supreme Commander Forged Alliance/mods/TheRedQueen")
BINARY = Path("/home/andreas/.faforever/bin")
PREFS = Path("/var/home/andreas/faf-linux/prefix/drive_c/users/steamuser/AppData/Local/Gas Powered Games/Supreme Commander Forged Alliance")


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def payload(root):
    files = sorted([root / "mod_info.lua", *root.glob("lua/**/*.lua"), *root.glob("hook/**/*.lua")])
    hashes = {str(path.relative_to(root)): sha(path) for path in files}
    return hashlib.sha256(json.dumps(hashes, sort_keys=True).encode()).hexdigest()


def game_processes():
    for line in subprocess.check_output(["ps", "-eo", "pid,comm"], text=True).splitlines()[1:]:
        pid, name = line.split(None, 1)
        if not name.startswith("ForgedAlliance"):
            continue
        try:
            raw = (Path("/proc") / pid / "cmdline").read_bytes()
            words = [part.decode(errors="replace") for part in raw.split(b"\0") if part]
            yield int(pid), raw, words
        except (OSError, PermissionError):
            continue


def owns(words, log):
    if not words or not words[0].lower().endswith("forgedalliance.exe"):
        return False
    if any("/gpgnet" in word.lower() for word in words) or "/redqueen" not in words or "/log" not in words:
        return False
    index = words.index("/log")
    return index + 1 < len(words) and words[index + 1] == str(log)


def stop_owned(log):
    stopped = []
    for pid, original, words in game_processes():
        if not owns(words, log):
            continue
        try:
            descriptor = os.pidfd_open(pid)
            try:
                current = (Path("/proc") / str(pid) / "cmdline").read_bytes()
                if current == original:
                    signal.pidfd_send_signal(descriptor, signal.SIGTERM)
                    stopped.append(pid)
            finally:
                os.close(descriptor)
        except (OSError, PermissionError):
            continue
    return stopped


def preflight(slot):
    if not MOD.is_symlink() or MOD.resolve() != ROOT.resolve():
        raise SystemExit("Active TheRedQueen symlink must resolve to this control checkout")
    if payload(ROOT) != CONTROL:
        raise SystemExit("Control payload changed; review the fixture against the new tree before running")
    prefs_name = f"RQTest{slot}.prefs"
    uid = re.search(r'^uid\s*=\s*"([^"]+)"', (ROOT / "mod_info.lua").read_text(), re.M)[1]
    prefs = (PREFS / prefs_name).read_text()
    active = re.search(r"active_mods\s*=\s*\{(.*?)\}", prefs, re.S)
    if not active or not re.search(re.escape(uid) + r"['\"]\]\s*=\s*true", active[1]):
        raise SystemExit(f"{prefs_name} must activate mod {uid}")
    games = list(game_processes())
    if len(games) >= 2:
        raise SystemExit("Two game processes are already running; finish one before launching the fixture")
    for pid, _, words in games:
        user_game = any("/gpgnet" in word.lower() for word in words)
        if user_game:
            print(f"User game pid={pid}: left untouched", flush=True)
        if "/prefs" in words:
            index = words.index("/prefs")
            if index + 1 < len(words) and words[index + 1] == prefs_name:
                raise SystemExit(f"Preferences slot {slot} is already in use by pid={pid}")
        elif not user_game:
            raise SystemExit(f"Unidentified test game pid={pid}; finish it before running this fixture")
    available = re.search(r"MemAvailable:\s+(\d+)", Path("/proc/meminfo").read_text())
    if not available or int(available[1]) < 4 * 1024 * 1024:
        raise SystemExit("At least 4 GiB available memory is required")
    return prefs_name


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path, help="new evidence directory outside the checkout")
    parser.add_argument("--slot", type=int, choices=range(1, 7), default=1)
    # Sentry Point resolves in about 16 game minutes and the eighth case needs
    # roughly 17, so the fixture lost Seraphim Tech 3 to the match ending rather
    # than to any failure. A larger map simply lives longer; the fixture itself
    # is map-independent.
    parser.add_argument("--map", default="SCMP_018")
    args = parser.parse_args()
    out = args.output.expanduser().resolve()
    if out == ROOT.resolve() or ROOT.resolve() in out.parents:
        raise SystemExit("Keep the evidence directory outside the checkout to avoid recursive copies")
    if out.exists():
        raise SystemExit(f"Refusing to overwrite evidence: {out}")
    prefs_name = preflight(args.slot)
    out.mkdir(parents=True)
    candidate = out / "candidate"
    overlay = out / "overlay"
    log = out / "game.log"
    patch = ROOT / "docs/balance/storage-mass-only.patch"
    subprocess.run(["git", "clone", "--no-hardlinks", "--quiet", str(ROOT), str(candidate)], check=True)
    subprocess.run(["rsync", "-a", "--delete", "--exclude=.git", "--exclude=storage-candidate.tmp",
                    str(ROOT) + "/", str(candidate) + "/"], check=True)
    subprocess.run(["git", "-C", str(candidate), "apply", str(patch)], check=True)
    # These checks run only when the user invokes this verifier. No FAF launch
    # is allowed after a failed contract or hook-target check.
    subprocess.run([str(candidate / "scripts/validate.sh")], cwd=candidate, check=True)
    subprocess.run(["python3", str(candidate / "scripts/check-hook-targets.py"),
                    str(BINARY.parent / "gamedata/lua.nx2")], cwd=candidate, check=True)
    preflight(args.slot)
    env = dict(os.environ, FAF_RQ_FACTION="2", FAF_OPP_FACTION="3", FAF_SEED="2071971",
               FAF_MIXED="1", FAF_NO_HUMAN="0", FAF_LAYOUT="", FAF_SCOUTING_MODE="combined",
               FAF_PRODUCTION_TRACE="0", FAF_LIFECYCLE_FIXTURE="0", FAF_DEFENSE_FIXTURE="0")
    init = subprocess.check_output(["python3", str(ROOT / "scripts/prepare-runtime.py"),
                                    str(BINARY), str(overlay), "1"], cwd=ROOT, env=env, text=True).strip()
    with zipfile.ZipFile(BINARY.parent / "gamedata/lua.nx2") as archive:
        sim = archive.read("lua/simInit.lua").decode()
    sim += "\nlocal RQStorageBeginSession = BeginSession\nfunction BeginSession()\n    RQStorageBeginSession()\n    ForkThread(import('/lua/rq-storage-fixture.lua').Run)\nend\n"
    (overlay / "lua/simInit.lua").write_text(sim)
    copies = {
        "lua/rq-storage-fixture.lua": ROOT / "tests/runtime/storage_placement.lua",
        "lua/rq-storage-hook.lua": candidate / "hook/lua/AI/aibuildstructures.lua",
        "mods/TheRedQueen/lua/AI/RedQueen/MassStorage.lua": candidate / "lua/AI/RedQueen/MassStorage.lua",
    }
    for relative, source in copies.items():
        target = overlay / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(source.read_bytes())
    source_path = overlay / "sources.json"
    sources = json.loads(source_path.read_text())
    sources.update({
        "scope": "candidate placement helper and hook; control AI; civilian fixture army; no builder-selection or balance claim",
        "control_payload_sha256": CONTROL,
        "candidate_payload_sha256": payload(candidate),
        "candidate_patch_sha256": sha(patch),
        "units_archive_sha256": sha(BINARY.parent / "gamedata/units.nx2"),
        "overlay": {str(p.relative_to(overlay)): sha(p) for p in sorted(overlay.rglob("*.lua"))},
    })
    source_path.write_text(json.dumps(sources, indent=2) + "\n")
    env.update(FAF_WRAPPER="/var/home/andreas/faf-linux/launchwrapper",
               FAF_EXE=str(BINARY / "ForgedAlliance.exe"), FAF_PREFS=prefs_name,
               FAF_MOD_PATH=str(MOD), FAF_INIT=init, FAF_FIXED_RUNTIME="0")
    def interrupt(signum, frame):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, interrupt)
    print(f"Launching one bounded storage fixture; evidence: {out}", flush=True)
    started = time.monotonic()
    reason = "timeout"
    content = ""
    printed = 0
    with (out / "launcher.log").open("w") as output:
        process = subprocess.Popen([str(ROOT / "scripts/run-smoke.sh"), args.map, str(log)],
                                   cwd=ROOT, env=env, stdout=output, stderr=subprocess.STDOUT,
                                   start_new_session=True)
        try:
            while time.monotonic() - started < 600:
                content = log.read_text(errors="replace") if log.exists() else ""
                progress = [line for line in content.splitlines() if "[RQStorageFixture]" in line]
                for line in progress[printed:]:
                    print(line, flush=True)
                printed = len(progress)
                if "[RQStorageFixture] FAIL " in content:
                    reason = "fixture-failed"
                    break
                if "[RQStorageFixture] PASS cases=8 " in content:
                    reason = "pass"
                    time.sleep(2)
                    break
                if process.poll() is not None:
                    reason = "process-exit"
                    break
                if "GameEnded" in content:
                    reason = "match-ended-before-fixture"
                    break
                time.sleep(1)
        except KeyboardInterrupt:
            reason = "interrupted"
        finally:
            stopped = stop_owned(log)
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                print("Wrapper still running; left untouched", flush=True)
    content = log.read_text(errors="replace") if log.exists() else ""
    analysis_code = None
    if log.exists():
        with (out / "analysis.txt").open("w") as output:
            analysis_code = subprocess.run(["python3", str(ROOT / "scripts/analyze-log.py"), str(log)],
                                           cwd=ROOT, stdout=output, stderr=subprocess.STDOUT).returncode
    observed = re.findall(r"\[RQStorageFixture\] CASE blueprint=(\w+)", content)
    expected = sorted(prefix + tier for prefix in ("ueb", "uab", "urb", "xsb") for tier in ("1202", "1302"))
    unchanged = payload(ROOT) == CONTROL
    overlay_unchanged = all(sha(overlay / name) == digest for name, digest in sources["overlay"].items())
    still_running = [pid for pid, _, words in game_processes() if owns(words, log)]
    passed = (reason == "pass" and analysis_code == 0 and sorted(observed) == expected
              and unchanged and overlay_unchanged and not still_running
              and "[RQStorageFixture] FAIL " not in content)
    result = {"status": "passed" if passed else "incomplete-or-failed", "stop": reason,
              "analyzer_exit": analysis_code, "cases": observed, "control_unchanged": unchanged,
              "overlay_unchanged": overlay_unchanged,
              "stopped_pids": stopped, "remaining_owned_pids": still_running,
              "wall_seconds": round(time.monotonic() - started, 1), "runtime_sources": str(source_path)}
    (out / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    progress = [line for line in content.splitlines() if "[RQStorageFixture]" in line]
    for line in progress[printed:]:
        print(line)
    print(json.dumps(result), flush=True)
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
