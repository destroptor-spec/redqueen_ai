#!/usr/bin/env python3
"""Check completed strict 1v1 matches against a recorded reference.

Exit 0: every case is valid and every reference win is retained.
Exit 1: at least one reference win became a defeat.
Exit 2: evidence is missing, incomplete, inconsistent, or broken.
This checks recorded cases; it does not establish a general win probability.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess
import sys


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()


def case_key(settings):
    return f"{settings['map']}/{settings['seed']}/{settings['rq_faction']}-{settings['opponent_faction']}"


def read_match(path):
    path = Path(path)
    raw = path.read_bytes()
    text = raw.decode(errors="replace")
    manifest = json.loads(Path(str(path) + ".manifest.json").read_text())
    gate = subprocess.run([sys.executable, str(Path(__file__).with_name("analyze-log.py")), str(path)],
                          capture_output=True, text=True)
    require(gate.returncode == 0, f"{path}: analyzer failed\n{gate.stdout}{gate.stderr}")
    require("GameEnded" in text, f"{path}: match has not ended")
    starts = re.findall(r"\[RedQueen\]\[INFO\]\[army=(\d+)\] started version=\S+ faction=(\d+) victory=(\w+)", text)
    require(len(starts) == 1, f"{path}: expected exactly one Red Queen start")
    army, faction, victory = starts[0]
    own = "\n".join(line for line in text.splitlines() if f"[army={army}]" in line)
    require(re.findall(r"income contract allies=(\d+) enemies=(\d+) deficit=(\d+) income=([\d.]+)", own)
            == [("1", "1", "0", "1.00")], f"{path}: expected strict 1v1 income=1.00")
    contracts = re.findall(r"match-contract army=(\d+) name=\S+ faction=(\d+) side=(\w+) start=(\S+)", own)
    allies = [r for r in contracts if r[2] == "ally"]
    enemies = [r for r in contracts if r[2] == "enemy"]
    require(len(contracts) == 2 and len(allies) == 1 and len(enemies) == 1,
            f"{path}: expected two contestants")
    require(allies[0][:2] == (army, faction), f"{path}: own army does not match its contract")
    enemy = enemies[0]
    require(army != enemy[0], f"{path}: opponent is the own army")
    require(str(manifest["red_queen_faction"]) == faction
            and str(manifest["opponent_faction"]) == enemy[1], f"{path}: faction manifest mismatch")
    require(str(manifest["difficulty"]) == "44" and str(manifest["mixed"]) == "1"
            and str(manifest["fixed_runtime"]) == "1", f"{path}: expected fixed strict 1v1 harness")
    modes = re.findall(r"scouting mode=(\S+) production=(\S+) dispatch=(\S+)", own)
    require(modes == [("combined", "adaptive", "on")] and manifest["scouting_mode"] == "combined",
            f"{path}: expected combined scouting")
    results = re.findall(r"lifecycle game-result result=(\w+)", own)
    require(len(results) >= 1 and len(set(results)) == 1 and results[-1] in ("victory", "defeat"),
            f"{path}: missing or contradictory Red Queen result")
    stats_lines = [line[line.index('{"stats"'):] for line in text.splitlines() if '{"stats"' in line]
    require(bool(stats_lines), f"{path}: missing final JsonStats")
    stats = json.JSONDecoder().raw_decode(stats_lines[-1])[0]["stats"]
    require(0 < int(army) <= len(stats) and 0 < int(enemy[0]) <= len(stats), f"{path}: absent contestant statistics")
    contestants = [dict(stats[int(index) - 1]) for index in (army, enemy[0])]
    for row, expected_faction in zip(contestants, (faction, enemy[1])):
        require(row.get("type") == "AI" and str(row.get("faction")) == expected_faction,
                f"{path}: statistics do not match contestant factions")
        row.pop("name", None)
    general = contestants[0]["general"]
    killed, lost = general["kills"]["mass"], general["lost"]["mass"]
    require(all(isinstance(v, (int, float)) and math.isfinite(v) and v >= 0 for v in (killed, lost)),
            f"{path}: invalid mass statistics")
    payload = manifest["payload_sha256"]
    require(bool(re.fullmatch(r"[0-9a-f]{64}", payload)), f"{path}: missing payload fingerprint")
    require(digest(manifest["files"]) == payload, f"{path}: inconsistent payload fingerprint")
    runtime = json.loads((Path(str(path) + ".runtime") / "sources.json").read_text())
    native_archive = runtime["native_archive_sha256"]
    require(bool(re.fullmatch(r"[0-9a-f]{64}", native_archive)), f"{path}: missing native Lua fingerprint")
    settings = {"map": manifest["map"], "seed": int(manifest["seed"]), "rq_faction": int(faction),
                "opponent_faction": int(enemy[1]), "victory": victory, "income": "1.00",
                "starts": [allies[0][3], enemy[3]], "scouting": "combined", "difficulty": 44,
                "native_lua_sha256": native_archive}
    return {"settings": settings, "result": results[-1], "killed_mass": killed, "lost_mass": lost,
            "stats_sha256": digest(contestants), "payload_sha256": payload,
            "log": str(path), "log_sha256": hashlib.sha256(raw).hexdigest()}


def compare(reference, candidates):
    require(reference.get("format") == 1 and bool(reference.get("cases")), "invalid or empty reference")
    expected = {}
    for row in reference["cases"]:
        key = case_key(row["settings"])
        require(key not in expected, f"duplicate reference case {key}")
        require(row["result"] in ("victory", "defeat"), f"unfinished reference case {key}")
        expected[key] = row
    actual = {}
    for row in candidates:
        key = case_key(row["settings"])
        require(key not in actual, f"duplicate candidate case {key}")
        actual[key] = row
    require(set(expected) == set(actual),
            f"case coverage differs; missing={sorted(set(expected) - set(actual))}, unexpected={sorted(set(actual) - set(expected))}")
    require(len({r["payload_sha256"] for r in candidates}) == 1, "mixed candidate payloads")
    rows = []
    for key, old in expected.items():
        new = actual[key]
        require(old["settings"] == new["settings"], f"settings changed for {key}")
        rows.append({"case": key, "before": old["result"], "after": new["result"],
                     "identical_stats": old["stats_sha256"] == new["stats_sha256"],
                     "before_mass_kl": old["killed_mass"] / max(1, old["lost_mass"]),
                     "after_mass_kl": new["killed_mass"] / max(1, new["lost_mass"])})
    return {"cases": rows, "lost_wins": [r["case"] for r in rows if r["before"] == "victory" and r["after"] != "victory"],
            "gained_wins": [r["case"] for r in rows if r["before"] != "victory" and r["after"] == "victory"],
            "candidate_payload": candidates[0]["payload_sha256"]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference", required=True, type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("logs", nargs="+", type=Path)
    args = parser.parse_args()
    try:
        report = compare(json.loads(args.reference.read_text()), [read_match(path) for path in args.logs])
    except (OSError, ValueError, KeyError, TypeError, IndexError) as error:
        print(f"Invalid evidence: {error}", file=sys.stderr)
        if args.output:
            args.output.write_text(json.dumps({"status": "invalid", "error": str(error)}, indent=2) + "\n")
        return 2
    report["status"] = "regressed" if report["lost_wins"] else "passed"
    for row in report["cases"]:
        print(f"{row['case']}: {row['before']} -> {row['after']} "
              f"mass K/L {row['before_mass_kl']:.3f} -> {row['after_mass_kl']:.3f} "
              f"identical={row['identical_stats']}")
    print(f"Matched {len(report['cases'])}; lost wins={len(report['lost_wins'])}; gained wins={len(report['gained_wins'])}")
    if args.output:
        args.output.write_text(json.dumps(report, indent=2) + "\n")
    return 1 if report["lost_wins"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
