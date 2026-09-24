#!/usr/bin/env python3
"""Exercise the helper against installed FAF coordinate conversion, with engine placement stubbed."""
import argparse
from pathlib import Path
import subprocess
import tempfile
import zipfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('archive', type=Path)
args = parser.parse_args()
with zipfile.ZipFile(args.archive) as archive:
    source = archive.read('lua/AI/aibuildstructures.lua').decode()
helpers = source[source.index('function AddToBuildQueue('):source.index('local AntiSpamList')]
execute = source[source.index('function AIExecuteBuildStructure('):source.index('function AIBuildBaseTemplate(')]
execute = execute.replace('for Key, Data in buildingTemplate do', 'for Key, Data in pairs(buildingTemplate) do')
script = '''
local AIUtils = { EngineerTryReclaimCaptureArea = function() end }
''' + helpers + execute + '''
local native = { AIExecuteBuildStructure = AIExecuteBuildStructure }
function ClassSimple(definition) return definition end
function import(path)
    if path == "/lua/AI/aibuildstructures.lua" then return native end
    return {}
end
local file = assert(io.open("lua/AI/RedQueen/ProductionManager.lua"))
local source = file:read("*a")
file:close()
local helper = assert(loadstring(source .. "\\nreturn ExecuteBuildStructure"))()
local position = { 500, 0, 700 }
local found
local queued
local brain = {
    GetFactionIndex = function() return 2 end,
    DecideWhatToBuild = function() return "uab0101" end,
    FindPlaceToBuild = function() return found end,
    BuildStructure = function(_, _, blueprint, point) queued = point end,
}
local engineer = { BuilderManagerData = { EngineerManager = { GetLocationCoords = function() return position end } } }
local template = { { "T1LandFactory", "uab0101" } }
for _, mode in ipairs({ "relative", "absolute" }) do
    local mass = { "uab1103", { 12, 24, 0 }, false }
    engineer.EngineerBuildQueue = { mass }
    found = mode == "relative" and { 21, 30, 0 } or { 521, 730, 0 }
    local accepted, failure, entry = helper(brain, engineer, "T1LandFactory", template, {}, mode)
    assert(accepted and not failure)
    assert(queued[1] == 521 and queued[2] == 730, mode .. " coordinate conversion failed")
    assert(entry == engineer.EngineerBuildQueue[2] and entry ~= mass, "trace must identify the requested factory, not queue head")
    assert(entry[2][1] == 521 and entry[2][2] == 730)
end
print("Installed FAF shifted/unshifted placement contract passed at origin 500,700; engine search stubbed")
'''
with tempfile.NamedTemporaryFile(mode='w', suffix='.lua') as fixture:
    fixture.write(script)
    fixture.flush()
    subprocess.run(['luajit', fixture.name], check=True)
