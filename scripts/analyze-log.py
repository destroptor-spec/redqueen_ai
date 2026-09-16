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
# Locations this mod registers, matched the way the simulation matches them:
# BaseLifecycle and StrategyDirector both test `string.sub(name, 1, 5) == "RQFB_"`,
# so the prefix is the convention and the rest of the name is free. Keying this
# on `RQFB_%d_%d` meant the lifecycle fixture's own site, RQFB_LIFECYCLE_TEST,
# could not be attributed -- in the one run whose whole purpose is to destroy
# and rebuild bases, an invalid-location warning for our own site was filed as
# somebody else's advisory.
RED_QUEEN_OWNED_LOCATION = re.compile(r"(?i)\bRQFB_\w+")
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
    r"|OnDefeat\b|lifecycle game-result result=defeat)"
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
    if RED_QUEEN_ERROR.search(line)
    and not SCHEDULER_FAILURE.search(line)
    and not LUA_FAILURE.search(line)
)

engine_lua_failures = [line for line in lines if LUA_FAILURE.search(line)]
red_queen_lua_failures: Counter[str] = Counter()
foreign_lua_failures: Counter[str] = Counter()
desyncs = Counter(
    normalise(line) for line in lines
    if DESYNC.search(line) and not LUA_FAILURE.search(line)
    and not RED_QUEEN_ERROR.search(line)
)

defeat_indices = [i for i, line in enumerate(lines) if DEFEAT_MARKER.search(line)]
first_defeat_index = min(defeat_indices) if defeat_indices else None
# Post-defeat counters are subsets of the primary attribution counters.
#
# FAF's own BaseManagersDistressAI (platoon.lua:1555) dereferences
# locData.EngineerManager:GetLocationCoords() for every BuilderManagers entry
# with no nil guard, so it raises once per army at the moment its managers are
# torn down. That fires in any match with a defeat, Red Queen involved or not,
# and no traceback frame names this mod. Gating on it would leave the gate
# permanently red and bury a genuine Red Queen leak in noise.
post_defeat_lua_failures: Counter[str] = Counter()
post_defeat_foreign: Counter[str] = Counter()
for index, line in enumerate(lines):
    if not LUA_FAILURE.search(line):
        continue
    attributed = bool(RED_QUEEN_SOURCE.search(line))
    for frame in lines[index + 1 : index + 12]:
        # Never borrow attribution from the next failure. Interleaved ordinary
        # Red Queen diagnostics are not traceback evidence either.
        if LUA_FAILURE.search(frame) or SCHEDULER_FAILURE.search(frame):
            break
        if "[RedQueen]" not in frame and RED_QUEEN_PATH.search(frame):
            attributed = True
            break
    message = normalise(line)
    primary = red_queen_lua_failures if attributed else foreign_lua_failures
    primary[message] += 1
    if not attributed and DESYNC.search(line):
        # Desyncs still fail independently of mod attribution, but an already
        # attributed Lua failure must not enter the gate a second time.
        desyncs[message] += 1
    if first_defeat_index is not None and index >= first_defeat_index:
        subset = post_defeat_lua_failures if attributed else post_defeat_foreign
        subset[message] += 1

# Invalid manager locations are a Red Queen contract concern: builders it
# registered must be retired when their location's managers go away.
#
# But the warning is raised by FAF's own build conditions for *any* army, and
# every army's managers are torn down when it is defeated -- so in a team match
# a defeated opponent's teardown lands in our log looking identical. Measured
# across a 21-cell matrix, all 11 of these warnings named a native location
# (`MAIN`, `Large Expansion Area 6`), arrived after the first defeat, and were
# followed by a traceback wholly inside `adaptive-ai.lua`. Gating on those is a
# false positive, so attribution follows the same evidence rule as a Lua
# failure: a location Red Queen itself registered, or a Red Queen traceback
# frame. `RQFB_<army>_<n>` is the only location name this mod creates
# (ProductionManager.lua, `RQFB_%d_%d`), which is why the name alone is
# sufficient evidence -- a leaked builder for one of our retired sites still
# fails the gate, defeat or no defeat.
invalid_locations: Counter[str] = Counter()
advisory_invalid_locations: Counter[str] = Counter()
invalid_location_after_defeat = 0
for index, line in enumerate(lines):
    match = INVALID_LOCATION.search(line)
    if not match:
        continue
    location = match.group(2).strip()
    attributed = bool(RED_QUEEN_OWNED_LOCATION.search(location))
    if not attributed:
        for frame in lines[index + 1 : index + 12]:
            if INVALID_LOCATION.search(frame) or LUA_FAILURE.search(frame):
                break
            if "[RedQueen]" not in frame and RED_QUEEN_PATH.search(frame):
                attributed = True
                break
    (invalid_locations if attributed else advisory_invalid_locations)[location] += 1
    if first_defeat_index is not None and index >= first_defeat_index:
        invalid_location_after_defeat += 1

# --- Behaviour summaries -----------------------------------------------------
starts = [line for line in red_queen if " started version=" in line]
contracts = [line for line in red_queen if "income contract" in line]
states = [line for line in red_queen if "state objective=" in line]

# Objective slots. `pressure=yielded` counts the samples where a protective
# objective held the whole army, which is the failure the two-slot design
# exists to remove; `objective-held` counts the times a change was refused,
# which is the walk-back-and-forth this AI used to do and must not resume.
PRESSURE = re.compile(
    r"primary=(\S+?)/([0-9.]+) secondary=(\S+?)/([0-9.]+) pressure=(\w+)"
)


def pressure_state(primary_type, primary_units, secondary_units, reported):
    """Whether the attack actually received force.

    The flag the brain writes says only that the primary slot holds an
    offensive objective, which after the slots landed is nearly always true and
    so measures nothing. What matters is whether anything was sent: an attack
    dispatched no units while the defence was dispatched some has yielded the
    pressure however the slot is labelled, and an army with nothing to send at
    all is neither holding nor yielding.
    """
    if primary_type in ("none", "Stage") or reported == "yielded":
        return "yielded" if secondary_units > 0 else "idle"
    if primary_units > 0:
        return "held"
    if secondary_units > 0:
        return "yielded"
    return "idle"
OBJECTIVE_CHANGE = re.compile(
    r"strategy objective=(\w+) kind=(\w+) slot=(\w+) priority=(-?\d+) layer=(\w+) from=(\S+)"
)
OBJECTIVE_HELD = re.compile(
    r"strategy objective-held current=(\S+) wanted=(\S+) reason=(\S+)"
)
pressure_samples = [PRESSURE.search(line) for line in states]
pressure_samples = [m for m in pressure_samples if m]
pressure_states = [
    pressure_state(m.group(1), float(m.group(2)), float(m.group(4)), m.group(5))
    for m in pressure_samples
]
pressure_yielded = [state for state in pressure_states if state == "yielded"]
pressure_idle = [state for state in pressure_states if state == "idle"]
primary_kinds = Counter(m.group(1) for m in pressure_samples)
secondary_kinds = Counter(m.group(3) for m in pressure_samples if m.group(3) != "none")
objective_changes = [m for m in (OBJECTIVE_CHANGE.search(l) for l in red_queen) if m]
change_kinds = Counter(f"{m.group(6)} -> {m.group(1)}/{m.group(2)} [{m.group(3)}]"
                       for m in objective_changes)
objective_holds = [m for m in (OBJECTIVE_HELD.search(l) for l in red_queen) if m]
hold_reasons = Counter(f"{m.group(3)}: {m.group(1)} kept over {m.group(2)}"
                       for m in objective_holds)
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

# Which arm each alert qualified on. Defence is judged per arm -- surface, air,
# and the combined force -- so an alert count alone cannot say whether a change
# came from the fleet reading, the air reading or the two together, and severity
# is taxed off that arm's ratio.
alert_arms = Counter(
    match.group(1)
    for line in alert_samples
    for match in [re.search(r"alert=yes/[\d.]+/[\d.]+/(\w+)/", line)]
    if match
)

# Units dispatched per layer. The fleet is the reason: a naval force given no
# destination receives no order at all, and no outcome figure shows it. Water
# staying at zero for a whole match on a map with water is the symptom.
dispatch_layers = {"L": 0, "A": 0, "W": 0, "M": 0, "H": 0}
dispatch_samples = 0
for line in states:
    match = re.search(r"dispatch=L(\d+),A(\d+),W(\d+),M(\d+),H(\d+)", line)
    if not match:
        continue
    dispatch_samples += 1
    for key, value in zip("LAWMH", match.groups()):
        dispatch_layers[key] = max(dispatch_layers[key], int(value))


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
if pressure_samples:
    held = len(pressure_samples) - len(pressure_yielded) - len(pressure_idle)
    contested = len(pressure_samples) - len(pressure_idle)
    share = (100.0 * len(pressure_yielded) / contested) if contested else 0.0
    print(
        f"Pressure: {held} held, {len(pressure_yielded)} yielded, "
        f"{len(pressure_idle)} idle of {len(pressure_samples)} samples "
        f"({share:.1f}% yielded where anything was sent)"
    )
    print(f"  primary slot:   {dict(primary_kinds)}")
    print(f"  secondary slot: {dict(secondary_kinds) or 'never filled'}")
ENGINEER_TIERS = re.compile(r"engtier=(\d+)/(\d+)/(\d+)")
tier_samples = [m for m in (ENGINEER_TIERS.search(l) for l in states) if m]
if tier_samples:
    peak = [max(int(m.group(i)) for m in tier_samples) for i in (1, 2, 3)]
    with_t2 = sum(1 for m in tier_samples if int(m.group(2)) > 0)
    print(
        f"Engineers by tier: peak T1={peak[0]} T2={peak[1]} T3={peak[2]}; "
        f"{with_t2}/{len(tier_samples)} samples had a Tech 2 engineer"
    )
ARMY_CENSUS = re.compile(r"army=(\d+)/(\d+)/(\d+)")
census_samples = [m for m in (ARMY_CENSUS.search(l) for l in states) if m]
if census_samples:
    owned = [int(m.group(1)) for m in census_samples]
    pooled = [int(m.group(2)) for m in census_samples]
    available = [int(m.group(3)) for m in census_samples]
    peak = max(owned) if owned else 0
    unreachable = [o - p for o, p in zip(owned, pooled)]
    print(
        f"Army census: peak owned={peak}, peak pooled={max(pooled) if pooled else 0}, "
        f"peak available={max(available) if available else 0}"
    )
    print(
        f"  units Red Queen cannot command (owned-pooled): "
        f"mean {sum(unreachable) / len(unreachable):.1f}, peak {max(unreachable)}"
    )
print(f"Objective changes: {len(objective_changes)}")
for description, count in change_kinds.most_common(12):
    print(f"  {count:5d}  {description}")
print(f"Objective changes refused: {len(objective_holds)}")
for description, count in hold_reasons.most_common(8):
    print(f"  {count:5d}  {description}")
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
if alert_arms:
    print(
        "Alert samples by qualifying arm: "
        + ", ".join(f"{arm} {count}" for arm, count in sorted(alert_arms.items()))
    )
if dispatch_samples:
    print(
        "Peak units dispatched per layer: "
        + ", ".join(f"{key}{dispatch_layers[key]}" for key in "LAWMH")
        + f" over {dispatch_samples} samples"
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
    f"Invalid manager locations: {sum(invalid_locations.values())} attributed,"
    f" {sum(advisory_invalid_locations.values())} in FAF code (advisory)"
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
failures: Counter[str] = Counter()
for key, count in scheduler_failures.most_common():
    named = scheduler_functions.get(key) or Counter()
    where = f" in {', '.join(name for name, _ in named.most_common(2))}" if named else ""
    failures[f"scheduler task {key}{where}"] += count
for source in (
    other_red_queen_errors,
    red_queen_lua_failures,
    desyncs,
):
    for message, count in source.most_common():
        failures[message.strip()] += count
if invalid_locations:
    for location, count in invalid_locations.most_common():
        failures[f"invalid manager location - {location}"] += count
if not starts:
    failures["No Red Queen brain startup was found in the log"] += 1

print(f"\nFailures: {len(failures)} distinct, {sum(failures.values())} occurrences")
for message, count in failures.most_common(20):
    print(f"  {count:5d}x  {message[:200]}")

if foreign_lua_failures or advisory_invalid_locations:
    print("\nUnattributed engine failures (advisory, not gated):")
    for message, count in foreign_lua_failures.most_common(10):
        print(f"  {count:5d}x  {message.strip()[:200]}")
    for location, count in advisory_invalid_locations.most_common(10):
        print(f"  {count:5d}x  invalid manager location - {location}")

raise SystemExit(1 if failures else 0)
