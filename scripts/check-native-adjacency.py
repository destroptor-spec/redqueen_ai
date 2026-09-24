#!/usr/bin/env python3
"""Check installed FAF mass-storage placement offline, with engine search stubbed.

Executes native AIBuildAdjacency, its ordinary-placement fallback, and its queue
helper under LuaJIT. Uses installed blueprint skirt sizes for all four factions.
Does not launch FAF, change the mod, or prove engine collision/adjacency callbacks.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile
import zipfile


def physics(archive, names, unit):
    source = archive.read(names[f"units/{unit}/{unit}_unit.bp"]).decode()
    block = re.search(r"\bPhysics\s*=\s*\{(.*?)^    \}", source, re.M | re.S)
    if not block:
        raise ValueError(f"Cannot find Physics block for {unit}")
    fields = {}
    for key in ("SkirtSizeX", "SkirtSizeZ", "SkirtOffsetX", "SkirtOffsetZ"):
        match = re.search(rf"\b{key}\s*=\s*(-?\d+(?:\.\d+)?)", block[1])
        if not match:
            raise ValueError(f"Missing {unit}.Physics.{key}; inspect this FAF version")
        fields[key] = float(match[1])
    return "{ Physics = { " + ", ".join(f"{k} = {v}" for k, v in fields.items()) + " } }"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path, help="installed lua.nx2")
    parser.add_argument("units", type=Path, help="installed units.nx2")
    args = parser.parse_args()
    with zipfile.ZipFile(args.archive) as archive:
        source = archive.read("lua/AI/aibuildstructures.lua").decode()
    helpers = source[source.index("function AddToBuildQueue("):source.index("local AntiSpamList")]
    execute = source[source.index("function AIExecuteBuildStructure("):source.index("function AIBuildBaseTemplate(")]
    adjacency = source[source.index("function AIBuildAdjacency("):source.index("function AINewExpansionBase(")]
    # Only adapt the two FAF generic table loops reached by this fixture.
    execute = execute.replace("for Key, Data in buildingTemplate do", "for Key, Data in pairs(buildingTemplate) do")
    adjacency = adjacency.replace("for k,v in reference do", "for k,v in ipairs(reference) do")
    setup = ["local blueprints = {}"]
    with zipfile.ZipFile(args.units) as archive:
        names = {name.lower(): name for name in archive.namelist()}
        for faction in ("ueb", "uab", "urb", "xsb"):
            for suffix in ("1106", "1202", "1302"):
                unit = faction + suffix
                setup.append(f"blueprints[{json.dumps(unit)}] = {physics(archive, names, unit)}")
    fixture = "\n".join(setup) + "\n" + r'''
local AIUtils = { EngineerTryReclaimCaptureArea = function() end }
ScenarioInfo = { size = { 512, 512 } }
''' + helpers + execute + adjacency + r'''
local function touches(point, position, storage, extractor)
    -- The installed mex and storage use identical skirt offsets, so offsets
    -- cancel in this edge-to-edge comparison. Refuse that assumption if changed.
    assert(storage.SkirtOffsetX == extractor.SkirtOffsetX)
    assert(storage.SkirtOffsetZ == extractor.SkirtOffsetZ)
    local dx = math.abs(point[1] - position[1])
    local dz = math.abs(point[2] - position[3])
    local sx = (storage.SkirtSizeX + extractor.SkirtSizeX) / 2
    local sz = (storage.SkirtSizeZ + extractor.SkirtSizeZ) / 2
    return (dx == sx and dz < sz) or (dz == sz and dx < sx)
end

for factionIndex, faction in ipairs({ "ueb", "uab", "urb", "xsb" }) do
    for _, tier in ipairs({ "1202", "1302" }) do
        local storageId, extractorId = faction .. "1106", faction .. tier
        local storage, extractor = blueprints[storageId].Physics, blueprints[extractorId].Physics
        local position = { 100, 0, 120 }
        local engineerPosition = { 160, 0, 180 }
        local occupied, orders, mode, fallbackCalls = {}, {}, "open", 0
        local target = {
            GetBlueprint = function() return blueprints[extractorId] end,
            GetPosition = function() return { position[1], position[2], position[3] } end,
        }
        local baseTemplate = { { { "MassStorage" }, { 40, 40, 0 } } }
        local engineer = {
            GetPosition = function() return engineerPosition end,
            BuilderManagerData = { EngineerManager = {
                GetLocationCoords = function() return engineerPosition end,
            } },
        }
        local brain = {
            GetFactionIndex = function() return factionIndex end,
            DecideWhatToBuild = function() return storageId end,
            GetUnitBlueprint = function(_, id) return blueprints[id] end,
            FindPlaceToBuild = function(_, kind, id, template, relative)
                if template == baseTemplate then
                    fallbackCalls = fallbackCalls + 1
                    assert(relative == true, "ordinary placement uses engineer-relative coordinates")
                    return { 40, 40, 0 }
                end
                assert(relative == false, "adjacency positions must be absolute")
                local choices = template[1]
                if mode == "open" then
                    assert(#choices == 5, "a clear 2x2 extractor must offer four skirt positions")
                    for i = 2, #choices do
                        assert(touches(choices[i], position, storage, extractor), "candidate misses extractor skirt")
                    end
                end
                for i = 2, #choices do
                    local point = choices[i]
                    assert(point[1] > 8 and point[1] < 504 and point[2] > 8 and point[2] < 504,
                        "native candidate violated map-edge exclusion")
                    local key = point[1] .. ":" .. point[2]
                    if mode == "open" and not occupied[key] then
                        return { point[1], point[2], point[3] }
                    end
                end
                return false
            end,
            BuildStructure = function(_, builder, id, point, relative)
                assert(builder == engineer and id == storageId and relative == false)
                orders[#orders + 1] = { point[1], point[2], point[3] }
                occupied[point[1] .. ":" .. point[2]] = true
            end,
        }
        local function build(references)
            return AIBuildAdjacency(brain, engineer, "MassStorage", false, false,
                { { "MassStorage", storageId } }, baseTemplate, references)
        end
        -- Simulate each selected footprint becoming occupied. This models
        -- collision responses, not the engine actually constructing four units.
        for i = 1, 4 do
            assert(build({ target }) and #orders == i)
            assert(touches(orders[i], position, storage, extractor))
            assert(engineer.EngineerBuildQueue[i][3] == false)
        end
        assert(fallbackCalls == 0)
        print(extractorId .. ": four skirt-touching orders, no fallback")

        local function expectFallback(references, reason)
            local before = #orders
            local callsBefore = fallbackCalls
            assert(build(references), "native fallback should accept its ordinary site")
            assert(fallbackCalls == callsBefore + 1 and #orders == before + 1)
            local point = orders[#orders]
            assert(point[1] == 200 and point[2] == 220, "fallback coordinate conversion changed")
            assert(not touches(point, position, storage, extractor), "fixture fallback must be non-adjacent")
            print(extractorId .. ": " .. reason .. " -> non-adjacent order at 200,220")
        end
        expectFallback({ target }, "full ring")
        occupied, mode = {}, "blocked"
        expectFallback({ target }, "all skirt sites blocked")
        expectFallback({}, "no local target")
        target.Dead = true
        expectFallback({ target }, "dead target")
        target.Dead = false
        position = { 2, 0, 2 }
        expectFallback({ target }, "target inside map-edge exclusion")
    end
end
print("Offline native adjacency checks passed. Engine search/collision is stubbed; no units were built.")
'''
    print("Native Lua archive SHA256:", hashlib.sha256(args.archive.read_bytes()).hexdigest(), flush=True)
    print("Unit archive SHA256:", hashlib.sha256(args.units.read_bytes()).hexdigest(), flush=True)
    with tempfile.NamedTemporaryFile(mode="w", suffix=".lua") as script:
        script.write(fixture)
        script.flush()
        subprocess.run(["luajit", script.name], check=True)


if __name__ == "__main__":
    main()
