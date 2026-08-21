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
failures = [
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

raise SystemExit(1 if failures else 0)
