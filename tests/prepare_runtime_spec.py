"""Exercise generated launch factions together with the simulation hook."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
# Native command-line launch loop, with UI dependencies replaced by table stubs.
LAUNCH = """
local defaultOptions = { Victory = 'demoralization' }
table.copy = function(source)
    local result = {}
    for key, value in pairs(source) do result[key] = value end
    return result
end
local function GetCommandLineOptions()
    local options = table.copy(defaultOptions)
    return options
end
function GetRandomFaction() return 4 end
function GetDefaultPlayerOptions() return {} end
function Setup(armies)
    local sessionInfo = { teamInfo = {} }
    sessionInfo.scenarioInfo = { Options = GetCommandLineOptions() }
    sessionInfo.teamInfo[1] = { ArmyName = armies[1], Human = true, Faction = 4 }
    if true then
        local name
        for index = 2, table.getn(armies) do
            name = armies[index]
            local aiOptions = GetDefaultPlayerOptions(sessionInfo.playerName)
            aiOptions.AIPersonality = 'rush'
            aiOptions.Faction = GetRandomFaction()
            aiOptions.Human = false
            aiOptions.ArmyName = name
            sessionInfo.teamInfo[index] = aiOptions
        end
    end
    return sessionInfo
end
"""
CHECK = """
local markers = {}
function import(path)
    if path == '/lua/sim/ScenarioUtilities.lua' then
        return { GetMarker = function(name)
            return markers[name] and { position = markers[name] }
        end }
    end
    if path == '/lua/redqueen-test-teams.lua'
        or path == '/mods/TheRedQueen/lua/AI/RedQueen/TeamLayout.lua'
    then
        local file = path == '/lua/redqueen-test-teams.lua'
            and string.gsub(arg[1], 'SinglePlayerLaunch.lua', 'redqueen-test-teams.lua')
            or 'lua/AI/RedQueen/TeamLayout.lua'
        local env = setmetatable({}, { __index = _G })
        setfenv(assert(loadfile(file)), env)()
        return env
    end
    error('unexpected import ' .. path)
end
function doscript(path, env)
    local entries = {}
    for name, position in pairs(markers) do entries[name] = { position = position } end
    env.Scenario = { MasterChain = { _MASTERCHAIN_ = { Markers = entries } } }
end
if arg[6] == 'saltrock' then
    markers = {
        ARMY_1 = { 114.5, 19, 313.5 }, ARMY_2 = { 398.5, 19, 314.5 },
        ARMY_3 = { 304.5, 19, 147.5 }, ARMY_4 = { 167.5, 19, 400.5 },
        ARMY_5 = { 350.5, 19, 406.5 }, ARMY_6 = { 203.5, 19, 153.5 },
    }
end
dofile(arg[1])
local armies = {}
for index = 1, tonumber(arg[2]) do armies[index] = 'ARMY_' .. index end
if arg[4] == 'reversed' then
    -- Preserve the human slot, scramble the numeric launch order.
    for index = 2, math.floor((#armies + 1) / 2) do
        local other = #armies + 2 - index
        armies[index], armies[other] = armies[other], armies[index]
    end
end
local session = Setup(armies)
ScenarioInfo = { ArmySetup = {}, Options = session.scenarioInfo.Options }
ScenarioInfo.Options.Difficulty = tonumber(arg[3])
for _, setup in ipairs(session.teamInfo) do ScenarioInfo.ArmySetup[setup.ArmyName] = setup end
ArmyBrains = {}
keyToBrain = {}
dofile('hook/lua/aibrains/index.lua')
local scouting = setmetatable({}, { __index = _G })
setfenv(assert(loadfile('lua/AI/RedQueen/ScoutingConfig.lua')), scouting)()
local config = scouting.Create(ScenarioInfo.Options)
assert(config.Mode == (arg[5] or 'combined'), 'launch must carry the scouting mode into simulation')
assert(config.AdaptiveProduction == (config.Mode ~= 'dispatch-only'))
assert(config.DirectedDispatch == (config.Mode ~= 'production-only'))
for name, setup in pairs(ScenarioInfo.ArmySetup) do
    if not setup.Human and not setup.Civilian then
        local expected = setup.AIPersonality == 'redqueen' and 1 or 3
        assert(setup.Faction == expected, name .. ' ' .. setup.AIPersonality
            .. ' got faction ' .. setup.Faction .. ', expected ' .. expected)
    end
end
"""


class PrepareRuntimeSpec(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name)
        self.binary = self.base / "bin"
        self.binary.mkdir()
        (self.binary / "init_faf.lua").write_text("path = {}\n")
        (self.base / "gamedata").mkdir()
        with zipfile.ZipFile(self.base / "gamedata/lua.nx2", "w") as archive:
            archive.writestr("lua/SinglePlayerLaunch.lua", LAUNCH)
            archive.writestr("lua/ui/game/gamemain.lua", "function OnFirstUpdate() end\n")
        self.check = self.base / "check.lua"
        self.check.write_text(CHECK)
        # A fake executable and wrapper: these tests never start FAF or Wine.
        self.executable = self.binary / "fake-game.exe"
        self.executable.touch()
        self.wrapper = self.base / "fake-wrapper"
        self.wrapper.write_text('#!/bin/sh\nprintf "%s\\n" "$@"\n')
        self.wrapper.chmod(0o755)
        active_mod = self.base / "TheRedQueen"
        active_mod.symlink_to(ROOT, target_is_directory=True)
        self.env = dict(os.environ, FAF_RQ_FACTION="1", FAF_OPP_FACTION="3",
                        FAF_NO_HUMAN="0", FAF_FIXED_RUNTIME="1", FAF_LAYOUT="",
                        FAF_MIXED="1", FAF_SCOUTING_MODE="combined",
                        FAF_WRAPPER=str(self.wrapper), FAF_EXE=str(self.executable),
                        FAF_MOD_PATH=str(active_mod), FAF_PRODUCTION_TRACE="0",
                        FAF_LIFECYCLE_FIXTURE="0", FAF_DEFENSE_FIXTURE="0")

    def test_scouting_modes_reach_simulation_and_manifest_through_launcher(self):
        for mode in ("combined", "production-only", "dispatch-only"):
            with self.subTest(mode=mode):
                log = self.base / f"{mode}.log"
                result = subprocess.run(
                    ["bash", "scripts/run-smoke.sh", "SCMP_037", str(log)],
                    cwd=ROOT, env=dict(self.env, FAF_SCOUTING_MODE=mode),
                    capture_output=True, text=True,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(str(self.executable), result.stdout)
                manifest = json.loads(Path(str(log) + '.manifest.json').read_text())
                runtime = Path(str(log) + '.runtime')
                self.assertEqual(manifest['scouting_mode'], mode)
                self.assertEqual(json.loads((runtime / 'sources.json').read_text())['scouting_mode'], mode)
                checked = subprocess.run(
                    ["luajit", str(self.check), str(runtime / "lua/SinglePlayerLaunch.lua"),
                     "10", "44", "numeric", mode], cwd=ROOT, capture_output=True, text=True,
                )
                self.assertEqual(checked.returncode, 0, checked.stderr)

    def test_invalid_or_untransmitted_modes_fail_before_launch(self):
        for mode, fixed in (("production-only", "0"), ("dispatch-only", "0"),
                            ("typo", "1"), ("", "1")):
            with self.subTest(mode=mode, fixed=fixed):
                log = self.base / "rejected.log"
                result = subprocess.run(
                    ["bash", "scripts/run-smoke.sh", "SCMP_037", str(log)],
                    cwd=ROOT, env=dict(self.env, FAF_SCOUTING_MODE=mode, FAF_FIXED_RUNTIME=fixed),
                    capture_output=True, text=True,
                )
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertIn("FAF_SCOUTING_MODE", result.stderr)
                self.assertEqual(result.stdout, "", "the fake game must never be invoked")
                self.assertFalse(Path(str(log) + '.manifest.json').exists())

    def test_factions_follow_personalities_for_every_layout_and_start_order(self):
        for count, difficulty in [(1, 43), (1, 44), (2, 45), (2, 46),
                                  (1, 47), (1, 48), (1, 49), (1, 50)]:
            destination = self.base / str(difficulty)
            subprocess.run(
                ["python3", "scripts/prepare-runtime.py", str(self.binary), str(destination), str(count)],
                cwd=ROOT, env=self.env,
                check=True, capture_output=True, text=True,
            )
            for starts in (4, 6, 10, 12):
                for order in ("numeric", "reversed"):
                    with self.subTest(difficulty=difficulty, starts=starts, order=order):
                        result = subprocess.run(
                            ["luajit", str(self.check), str(destination / "lua/SinglePlayerLaunch.lua"),
                             str(starts), str(difficulty), order],
                            cwd=ROOT, capture_output=True, text=True,
                        )
                        self.assertEqual(result.returncode, 0, result.stderr)

    def test_saltrock_factions_match_proximity_teams_with_and_without_human(self):
        for human in ("0", "1"):
            for count, difficulty in ((2, 45), (2, 46), (1, 49), (1, 50)):
                destination = self.base / f"saltrock-{human}-{difficulty}"
                subprocess.run(
                    ["python3", "scripts/prepare-runtime.py", str(self.binary), str(destination), str(count)],
                    cwd=ROOT, env=dict(self.env, FAF_NO_HUMAN=human), check=True, capture_output=True,
                )
                for order in ("numeric", "reversed"):
                    with self.subTest(no_human=human, difficulty=difficulty, order=order):
                        result = subprocess.run(
                            ["luajit", str(self.check), str(destination / "lua/SinglePlayerLaunch.lua"),
                             "6", str(difficulty), order, "combined", "saltrock"],
                            cwd=ROOT, capture_output=True, text=True,
                        )
                        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
