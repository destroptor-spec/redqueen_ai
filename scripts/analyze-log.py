#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
from pathlib import Path


if len(sys.argv) != 2:
    print(f"Usage: {Path(sys.argv[0]).name} /path/to/game.log", file=sys.stderr)
    raise SystemExit(2)

log_path = Path(sys.argv[1])
if not log_path.is_file():
    print(f"Log does not exist: {log_path}", file=sys.stderr)
    raise SystemExit(2)

lines = log_path.read_text(encoding="utf-8", errors="replace").splitlines()
red_queen = [line for line in lines if "[RedQueen]" in line]
red_queen_failures = [
    line
    for line in lines
    if re.search(
        r"(?i)(\[RedQueen\]\[ERROR\]|"
        r"warning:.*(?:error|failed).*?(?:mods[/\\]theredqueen)|"
        r"warning:.*(?:mods[/\\]theredqueen).*(?:error|failed|attempt|nonexistent|bad argument|expected)|"
        r"desync)",
        line,
    )
]
LUA_FAILURE = re.compile(r"(?i)warning:\s+Error running lua script")
RED_QUEEN_SOURCE = re.compile(r"(?i)(mods[/\\]theredqueen|\bRedQueen)")

engine_lua_failures = [line for line in lines if LUA_FAILURE.search(line)]
# Only Red Queen-attributable engine errors may fail the gate. A comparison run
# against stock AIs or a modded map can log unrelated stack traces, and failing
# on those turns the gate into noise.
red_queen_lua_failures = [
    line for line in engine_lua_failures if RED_QUEEN_SOURCE.search(line)
]
foreign_lua_failures = [
    line for line in engine_lua_failures if not RED_QUEEN_SOURCE.search(line)
]
manager_warnings = [
    line
    for line in lines
    if re.search(r"(?i)\*AI WARNING:.*Invalid location", line)
]
# Defeat markers vary by launcher and reporting path, so accept several shapes
# and report explicitly when none matched rather than silently skipping the
# post-defeat leak check.
DEFEAT_MARKER = re.compile(
    r"(?i)(GameResult\s+\d+\s+defeat"
    r"|GpgNetSend.*\bdefeat\b"
    r"|\bis\s+defeated\b"
    r"|OnDefeat\b)"
)
defeat_indices = [
    index for index, line in enumerate(lines) if DEFEAT_MARKER.search(line)
]
first_defeat_index = min(defeat_indices) if defeat_indices else None
post_defeat_lua_failures = []
if first_defeat_index is not None:
    post_defeat_lua_failures = [
        line for line in lines[first_defeat_index:] if LUA_FAILURE.search(line)
    ]
# A leaked task after defeat is a Red Queen contract violation regardless of
# which script the engine names, so these always fail the gate. A single line can
# match several patterns, so keep first-seen order and report it once.
failures = []
_seen_failures = set()
for line in red_queen_failures + red_queen_lua_failures + post_defeat_lua_failures:
    if line not in _seen_failures:
        _seen_failures.add(line)
        failures.append(line)
starts = [line for line in red_queen if " started version=" in line]
contracts = [line for line in red_queen if "income contract" in line]
states = [line for line in red_queen if "state objective=" in line]
defense_alerts = [line for line in red_queen if "defense alert " in line]
tier_policies = [line for line in red_queen if "tier policy " in line]
forward_bases = [line for line in red_queen if "forward base " in line]

if not starts:
    failures.append("No Red Queen brain startup was found in the log")

print(f"Red Queen lines: {len(red_queen)}")
print(f"Brains started: {len(starts)}")
print(f"Income contracts: {len(contracts)}")
print(f"State samples: {len(states)}")
print(f"Defense alerts: {len(defense_alerts)}")
print(f"Tier policy changes: {len(tier_policies)}")
print(f"Forward base events: {len(forward_bases)}")
print(f"Engine Lua failures: {len(engine_lua_failures)}")
print(f"Red Queen Lua failures: {len(red_queen_lua_failures)}")
print(f"Unattributed Lua failures: {len(foreign_lua_failures)}")
if first_defeat_index is None:
    print("Post-defeat Lua failures: not checked (no defeat marker in log)")
else:
    print(f"Post-defeat Lua failures: {len(post_defeat_lua_failures)}")
print(f"Invalid manager locations: {len(manager_warnings)}")
print(f"Potential failures: {len(failures)}")

for line in contracts:
    print(line)
for line in defense_alerts:
    print(line)
for line in tier_policies:
    print(line)
for line in forward_bases:
    print(line)
for line in failures[:20]:
    print(line)
for line in [l for l in foreign_lua_failures if l not in _seen_failures][:20]:
    print(line)
for line in manager_warnings[:20]:
    print(line)

raise SystemExit(1 if failures else 0)
