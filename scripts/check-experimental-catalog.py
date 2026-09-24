#!/usr/bin/env python3
"""Cross-check the experimental catalog against the engine's own data.

`lua/AI/RedQueen/Experimentals.lua` asserts, per faction, that a FAF template key
resolves to a particular blueprint and that the blueprint is an experimental.
Both halves are facts about the game, not about this mod, so a FAF update can
falsify them silently -- and three of those mappings are already wrong in ways
that matter (see docs/experimental-classification.md).

This compares the catalog against extracted game files. It needs those files, so
it is not part of `validate.sh`; run it when updating the catalog or after a FAF
update.

    scripts/check-experimental-catalog.py \\
        --templates /path/to/lua/BuildingTemplates.lua \\
        --units /path/to/extracted/units

`--units` is a directory containing `<ID>/<ID>_unit.bp` (the layout `units.nx2`
extracts to).
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

FACTION_NAMES = {1: "UEF", 2: "Aeon", 3: "Cybran", 4: "Seraphim"}

parser = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
parser.add_argument("--templates", type=Path, required=True)
parser.add_argument("--units", type=Path, required=True)
parser.add_argument("--catalog", type=Path,
                    default=Path(__file__).resolve().parent.parent
                    / "lua/AI/RedQueen/Experimentals.lua")
args = parser.parse_args()

for path in (args.templates, args.units, args.catalog):
    if not path.exists():
        print(f"missing input: {path}", file=sys.stderr)
        raise SystemExit(2)

problems: list[str] = []


def blueprint_categories(unit_id: str) -> set[str] | None:
    """Categories for a blueprint id, or None when the blueprint is absent."""
    for candidate in (unit_id.upper(), unit_id.lower()):
        matches = list(args.units.glob(f"**/{candidate}_unit.bp"))
        if matches:
            text = matches[0].read_text(errors="replace")
            block = re.search(r"Categories\s*=\s*\{(.*?)\n\s*\}", text, re.S)
            return set(re.findall(r'"([A-Z0-9_]+)"', block.group(1))) if block else set()
    return None


# --- The engine's mapping ----------------------------------------------------
#
# Faction blocks are delimited by their "-- <Faction> Building List" comment.
# Anchoring on those rather than on line numbers keeps this working when FAF
# adds entries, which shifts every line below the insertion.
templates_text = args.templates.read_text(errors="replace")
faction_bounds: list[tuple[int, int]] = []
starts = [(m.start(), m.group(1)) for m in
          re.finditer(r"--\s*(UEF|Aeon|Cybran|Seraphim)\s+Building List", templates_text)]
if len(starts) != 4:
    print(f"expected 4 faction blocks in {args.templates}, found {len(starts)}", file=sys.stderr)
    raise SystemExit(2)
name_to_index = {name: index for index, name in FACTION_NAMES.items()}
engine: dict[tuple[int, str], str] = {}
for position, (offset, name) in enumerate(starts):
    end = starts[position + 1][0] if position + 1 < len(starts) else len(templates_text)
    block = templates_text[offset:end]
    for match in re.finditer(r"'([A-Za-z0-9]+)',\s*\n\s*'([a-z0-9]{7})'", block):
        engine[(name_to_index[name], match.group(1))] = match.group(2)

# --- The catalog's claims ----------------------------------------------------
catalog_text = args.catalog.read_text(errors="replace")
catalog_half = re.split(r"(?m)^Rejected = \{", catalog_text, maxsplit=1)[0]
claims: list[tuple[int, str, str]] = []
for faction_match in re.finditer(r"\[(\d)\] = \{(.*?)\n    \},", catalog_half, re.S):
    faction = int(faction_match.group(1))
    for entry in re.finditer(
        r'Template = "([A-Za-z0-9]+)",\s*\n\s*Blueprint = "([a-z0-9]{7})"',
        faction_match.group(2),
    ):
        claims.append((faction, entry.group(1), entry.group(2)))

if not claims:
    print("parsed no catalog entries; the catalog format may have changed", file=sys.stderr)
    raise SystemExit(2)

for faction, template, expected in claims:
    actual = engine.get((faction, template))
    if actual is None:
        problems.append(
            f"{FACTION_NAMES[faction]} {template}: catalog expects {expected} "
            "but the engine has no such key for this faction")
        continue
    if actual != expected:
        problems.append(
            f"{FACTION_NAMES[faction]} {template}: catalog expects {expected}, "
            f"engine resolves to {actual}")
        continue
    cats = blueprint_categories(expected)
    if cats is None:
        problems.append(f"{FACTION_NAMES[faction]} {template}: blueprint {expected} not found")
    elif "EXPERIMENTAL" not in cats:
        problems.append(
            f"{FACTION_NAMES[faction]} {template}: {expected} is not an EXPERIMENTAL "
            f"(categories include {sorted(cats)[:6]})")

# --- The rejections ----------------------------------------------------------
#
# A rejection must still be true. If FAF fixes one of these, the catalog should
# gain the entry rather than keep refusing it.
rejected_parts = re.split(r"(?m)^Rejected = \{", catalog_text, maxsplit=1)
rejected_half = rejected_parts[1] if len(rejected_parts) > 1 else ""
for entry in re.finditer(
    r'\{ Faction = (\d), Template = "([A-Za-z0-9]+)", Blueprint = "([a-z0-9]{7})"',
    rejected_half,
):
    faction, template, expected = int(entry.group(1)), entry.group(2), entry.group(3)
    actual = engine.get((faction, template))
    if actual != expected:
        problems.append(
            f"{FACTION_NAMES[faction]} {template}: recorded as rejected because it "
            f"resolves to {expected}, but the engine now resolves it to {actual}; "
            "re-check whether it should be admitted")

print(f"checked {len(claims)} catalog entries against {len(engine)} engine mappings")
if problems:
    for problem in problems:
        print(f"  MISMATCH {problem}")
    raise SystemExit(1)
print("catalog agrees with the engine")
