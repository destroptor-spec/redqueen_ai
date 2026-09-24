#!/usr/bin/env python3
"""Verify every hook captures a symbol the file it hooks actually defines.

A hook file at `hook/lua/<path>` is appended to the environment of the native
`lua/<path>`. Capturing a native symbol therefore only works if *that* file
defines it. Hook the wrong file and the capture reads a name absent from the
environment -- and `system/config.lua` installs a strict metatable that raises
on exactly that, which aborts the import and takes the simulation down before
the first frame.

That happened: the engineer travel hook was placed in `hook/lua/platoon.lua`,
where `EngineerMoveWithSafePath` is only *used* (as
`AIUtils.EngineerMoveWithSafePath`), while it is *defined* in
`lua/AI/aiutilities.lua`. The contract gate could not see it, because the specs
supply the hook's environment themselves.

Needs the installed game archive, so it is not part of validate.sh:

    scripts/check-hook-targets.py ~/.faforever/gamedata/lua.nx2
"""
from __future__ import annotations

import argparse
import re
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
# The convention these hooks follow: the captured native implementation is bound
# to a local whose name begins with "Native".
CAPTURE = re.compile(r"^\s*local\s+Native\w*\s*=\s*([A-Za-z_][\w]*)", re.M)

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("archive", type=Path)
arguments = parser.parse_args()

failures: list[str] = []
checked = 0

with zipfile.ZipFile(arguments.archive) as archive:
    # The archive's casing is not the repository's, so resolve case-insensitively.
    by_lower = {name.lower(): name for name in archive.namelist()}
    for hook_path in sorted((ROOT / "hook" / "lua").rglob("*.lua")):
        relative = hook_path.relative_to(ROOT / "hook").as_posix()
        native_name = by_lower.get(relative.lower())
        if native_name is None:
            failures.append(f"{hook_path.relative_to(ROOT)}: no native {relative} in the archive")
            continue
        native = archive.read(native_name).decode("utf-8", "replace")
        for symbol in CAPTURE.findall(hook_path.read_text(encoding="utf-8")):
            checked += 1
            defined = (
                re.search(rf"(?m)^\s*function\s+{re.escape(symbol)}\s*\(", native)
                or re.search(rf"(?m)^\s*{re.escape(symbol)}\s*=", native)
                or re.search(rf"(?m)^\s*local\s+{re.escape(symbol)}\s*=", native)
            )
            if not defined:
                failures.append(
                    f"{hook_path.relative_to(ROOT)} captures '{symbol}', which "
                    f"{native_name} does not define. Hook the file that defines it, "
                    "or the strict global metatable aborts the import"
                )

for failure in failures:
    print("FAIL: " + failure, file=sys.stderr)
print(f"checked {checked} captured symbols across hook/lua")
raise SystemExit(1 if failures else 0)
