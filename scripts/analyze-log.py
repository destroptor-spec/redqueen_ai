#!/usr/bin/env python3
"""Summarise a Forged Alliance game log for Red Queen behaviour and failures.

Exit status is 1 when the log contains a Red Queen-attributable failure.

Design note: failures are reported with an occurrence count per distinct
message. Match 27741743 contained the same production-task crash 52 times and
an earlier version of this script, which de-duplicated by exact line text,
reported it as a single "potential failure". A defect that fires 52 times is a
different signal from one that fires once, and the gate must say so.
"""
from __future__ import annotations

import json
import re
import sys
from collections import Counter
from pathlib import Path


if len(sys.argv) != 2:
    print(f"Usage: {Path(sys.argv[0]).name} /path/to/game.log", file=sys.stderr)
    raise SystemExit(2)

log_path = Path(sys.argv[1])
if not log_path.is_file():
    print(f"Log does not exist: {log_path}", file=sys.stderr)
    raise SystemExit(2)

lines = log_path.read_text(encoding="utf-8", errors="replace").splitlines()

RED_QUEEN_SOURCE = re.compile(r"(?i)(mods[/\\]theredqueen|\bRedQueen)")
LUA_FAILURE = re.compile(r"(?i)warning:\s+Error running lua script")
SCHEDULER_FAILURE = re.compile(r"\[RedQueen\]\[ERROR\].*scheduler task '([a-z]+)' failed")
RED_QUEEN_ERROR = re.compile(r"\[RedQueen\]\[ERROR\]")
INVALID_LOCATION = re.compile(r"(?i)\*AI WARNING:\s*(\w+)\s*-\s*Invalid location\s*-\s*(.+)$")
DESYNC = re.compile(r"(?i)desync")
# A Red Queen frame in an engine traceback names the failing module function,
# which is what turns "a task failed" into "StartForwardBase failed". The engine
# truncates long paths from the left, so a frame arrives as
# "...ds\theredqueen\lua\ai\redqueen\productionmanager.lua(1234)" with "mo"
# already cut off; anchor on the mod directory name alone.
RED_QUEEN_FRAME = re.compile(
    r"(?i)theredqueen[/\\].*?\(\d+\):\s*in function [`']([A-Za-z_]+)'"
)
# A traceback frame inside this mod's own files. Deliberately path-based: the
# "[RedQueen]" log prefix must never be mistaken for a stack frame.
RED_QUEEN_PATH = re.compile(r"(?i)theredqueen[/\\][^\s]*\.lua")
DEFEAT_MARKER = re.compile(
    r"(?i)(GameResult\s+\d+\s+defeat"
    r"|GpgNetSend.*\bdefeat\b"
    r"|\bis\s+defeated\b"
    r"|OnDefeat\b)"
)


def normalise(message: str) -> str:
    """Collapse varying numbers so repeats of one defect group together."""
    return re.sub(r"\d+", "N", message)


red_queen = [line for line in lines if "[RedQueen]" in line]

# --- Red Queen scheduler failures, with the function each traceback names ----
scheduler_failures: Counter[str] = Counter()
scheduler_functions: dict[str, Counter[str]] = {}
for index, line in enumerate(lines):
    match = SCHEDULER_FAILURE.search(line)
    if not match:
        continue
    task = match.group(1)
    detail = normalise(line.split("failed:", 1)[-1].strip())
    key = f"{task}: {detail}"
    scheduler_failures[key] += 1
    # The traceback follows the failure line; find the deepest Red Queen frame.
    named = scheduler_functions.setdefault(key, Counter())
    for follow in lines[index + 1 : index + 12]:
        frame = RED_QUEEN_FRAME.search(follow)
        if frame:
            named[frame.group(1)] += 1
            break

other_red_queen_errors = Counter(
    normalise(line)
    for line in lines
    if RED_QUEEN_ERROR.search(line) and not SCHEDULER_FAILURE.search(line)
)

engine_lua_failures = [line for line in lines if LUA_FAILURE.search(line)]
red_queen_lua_failures = Counter(
    normalise(line) for line in engine_lua_failures if RED_QUEEN_SOURCE.search(line)
)
foreign_lua_failures = Counter(
    normalise(line) for line in engine_lua_failures if not RED_QUEEN_SOURCE.search(line)
)
desyncs = Counter(normalise(line) for line in lines if DESYNC.search(line))

defeat_indices = [i for i, line in enumerate(lines) if DEFEAT_MARKER.search(line)]
first_defeat_index = min(defeat_indices) if defeat_indices else None
# Post-defeat failures are split by attribution. Only those naming Red Queen
# fail the gate.
#
# FAF's own BaseManagersDistressAI (platoon.lua:1555) dereferences
# locData.EngineerManager:GetLocationCoords() for every BuilderManagers entry
# with no nil guard, so it raises once per army at the moment its managers are
# torn down. That fires in any match with a defeat, Red Queen involved or not,
# and no traceback frame names this mod. Gating on it would leave the gate
# permanently red and bury a genuine Red Queen leak in noise.
post_defeat_lua_failures: Counter[str] = Counter()
post_defeat_foreign: Counter[str] = Counter()
if first_defeat_index is not None:
    for index in range(first_defeat_index, len(lines)):
        line = lines[index]
        if not LUA_FAILURE.search(line):
            continue
        frames = lines[index : index + 12]
        # Attribute on traceback frames only. RED_QUEEN_SOURCE also matches the
        # "[RedQueen]" prefix of ordinary log lines, and the sim interleaves
        # those with tracebacks, so using it here would blame this mod for any
        # engine failure that happened to be logged next to its own output.
        attributed = any(RED_QUEEN_PATH.search(frame) for frame in frames)
        if attributed:
            post_defeat_lua_failures[normalise(line)] += 1
        else:
            post_defeat_foreign[normalise(line)] += 1

# Invalid manager locations are a Red Queen contract concern: builders it
# registered must be retired when their location's managers go away.
invalid_locations: Counter[str] = Counter()
invalid_location_after_defeat = 0
for index, line in enumerate(lines):
    match = INVALID_LOCATION.search(line)
    if not match:
        continue
    invalid_locations[match.group(2).strip()] += 1
    if first_defeat_index is not None and index >= first_defeat_index:
        invalid_location_after_defeat += 1

# --- Behaviour summaries -----------------------------------------------------
starts = [line for line in red_queen if " started version=" in line]
contracts = [line for line in red_queen if "income contract" in line]
states = [line for line in red_queen if "state objective=" in line]
defense_started = [line for line in red_queen if "defense alert started" in line]
tier_policies = [line for line in red_queen if "tier policy " in line]
forward_started = [line for line in red_queen if "forward base started" in line]
forward_established = [line for line in red_queen if "forward base established" in line]
forward_blocked = Counter(
    line.split("reason=", 1)[-1].strip()
    for line in red_queen
    if "forward base blocked reason=" in line
)
commitment_held = [line for line in red_queen if "commitment held" in line]
stagnation = [line for line in red_queen if re.search(r"economy (stagnant|declining)", line)]

# Endgame investment under alert: the V8 regression was that these never
# coexisted, so report the intersection directly rather than by eye.
alert_samples = [line for line in states if "alert=yes" in line]
alert_with_experimental = [
    line
    for line in alert_samples
    if re.search(r"X=(?!0\b)\d+", line)
]


def parse_json_stats() -> list[dict]:
    """Return the per-army stats block the engine emits at game end."""
    for line in reversed(lines):
        if "JsonStats" not in line:
            continue
        payload = line.split("JsonStats", 1)[-1].strip()
        start = payload.find("{")
        if start < 0:
            return []
        # The engine appends its own trailing punctuation after the object, so
        # decode the first complete value and ignore whatever follows.
        try:
            decoded, _ = json.JSONDecoder().raw_decode(payload[start:])
            return decoded.get("stats", [])
        except (ValueError, TypeError, AttributeError):
            return []
    return []


# --- Report ------------------------------------------------------------------
print(f"Red Queen lines: {len(red_queen)}")
print(f"Brains started: {len(starts)}")
print(f"Income contracts: {len(contracts)}")
print(f"State samples: {len(states)}")
print(f"Defense alerts raised: {len(defense_started)}")
print(f"Tier policy changes: {len(tier_policies)}")
print(
    f"Forward bases: {len(forward_started)} started, "
    f"{len(forward_established)} established, {sum(forward_blocked.values())} blocked"
)
print(f"Commitment holds: {len(commitment_held)}")
print(f"Economy stagnation reports: {len(stagnation)}")
if alert_samples:
    print(
        f"Endgame investment under alert: {len(alert_with_experimental)}"
        f"/{len(alert_samples)} alert samples kept a non-zero experimental weight"
    )
print(f"Engine Lua failures: {len(engine_lua_failures)}")
print(f"Red Queen Lua failures: {sum(red_queen_lua_failures.values())}")
print(f"Red Queen scheduler failures: {sum(scheduler_failures.values())}")
print(f"Unattributed Lua failures: {sum(foreign_lua_failures.values())}")
if first_defeat_index is None:
    print("Post-defeat Lua failures: not checked (no defeat marker in log)")
else:
    print(
        f"Post-defeat Lua failures: {sum(post_defeat_lua_failures.values())}"
        f" attributed, {sum(post_defeat_foreign.values())} in FAF code (advisory)"
    )
print(
    f"Invalid manager locations: {sum(invalid_locations.values())}"
    f" ({invalid_location_after_defeat} after first defeat)"
)

if forward_blocked:
    print("\nForward base blockers:")
    for reason, count in forward_blocked.most_common():
        print(f"  {count:5d}  {reason}")

stats = parse_json_stats()
if stats:
    print("\nEnd-of-game army stats:")
    header = f"  {'army':<34}{'built$':>9}{'lost$':>9}{'kill$':>9}{'K/L':>7}{'exp':>6}"
    print(header)
    for row in stats:
        general = row.get("general", {})
        built = general.get("built", {}).get("mass", 0)
        lost = general.get("lost", {}).get("mass", 0)
        killed = general.get("kills", {}).get("mass", 0)
        ratio = killed / lost if lost else 0.0
        units = row.get("units", {})
        experimental = units.get("experimental", {})
        name = f"{row.get('name', '?')} ({row.get('type', '?')})"
        print(
            f"  {name[:33]:<34}{built / 1000:>8.0f}k{lost / 1000:>8.0f}k"
            f"{killed / 1000:>8.0f}k{ratio:>7.2f}"
            f"{experimental.get('built', 0):>4}/{experimental.get('lost', 0)}"
        )
    print("  (exp = experimentals built/lost; K/L is destroyed mass over lost mass)")

# --- Gate --------------------------------------------------------------------
failures: list[tuple[int, str]] = []
for key, count in scheduler_failures.most_common():
    named = scheduler_functions.get(key) or Counter()
    where = f" in {', '.join(name for name, _ in named.most_common(2))}" if named else ""
    failures.append((count, f"scheduler task {key}{where}"))
for source in (
    other_red_queen_errors,
    red_queen_lua_failures,
    post_defeat_lua_failures,
    desyncs,
):
    for message, count in source.most_common():
        failures.append((count, message.strip()))
if invalid_locations:
    for location, count in invalid_locations.most_common():
        failures.append(
            (count, f"invalid manager location - {location}")
        )
if not starts:
    failures.append((1, "No Red Queen brain startup was found in the log"))

print(f"\nFailures: {len(failures)} distinct, {sum(c for c, _ in failures)} occurrences")
for count, message in sorted(failures, key=lambda item: -item[0])[:20]:
    print(f"  {count:5d}x  {message[:200]}")

advisory = Counter(foreign_lua_failures)
advisory.update(post_defeat_foreign)
if advisory:
    print("\nUnattributed engine failures (advisory, not gated):")
    for message, count in advisory.most_common(10):
        print(f"  {count:5d}x  {message.strip()[:200]}")

raise SystemExit(1 if failures else 0)
