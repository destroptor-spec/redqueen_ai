#!/usr/bin/env python3
"""Exercise recall against installed FAF disband and engineer task scheduling."""
import argparse
from pathlib import Path
import subprocess
import tempfile
import zipfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("archive", type=Path)
args = parser.parse_args()


def method(source, name):
    start = source.index(f"    {name} = function")
    end = source.index("\n    end,", start) + len("\n    end,")
    return source[start:end]


with zipfile.ZipFile(args.archive) as archive:
    engineer = archive.read("lua/sim/EngineerManager.lua").decode()
    platoon = archive.read("lua/platoon.lua").decode()
methods = [method(engineer, name) for name in ("TaskFinished", "ForkEngineerTask", "DelayAssign", "Wait")]
disband = method(platoon, "PlatoonDisband").replace(
    "for k,v in self:GetPlatoonUnits() do", "for k,v in pairs(self:GetPlatoonUnits()) do")
source = "NativeRecallEngineerManager = {\n" + "\n".join(methods) + "\n}\n"
source += "NativeRecallPlatoon = {\n" + disband + "\n}\n"
source += 'dofile("tests/engineer_recall_spec.lua")\n'
with tempfile.NamedTemporaryFile(mode="w", suffix=".lua") as fixture:
    fixture.write(source)
    fixture.flush()
    subprocess.run(["luajit", fixture.name], check=True)
print("Installed FAF disband and task scheduling passed; movement and build assignment stubbed")
