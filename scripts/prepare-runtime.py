#!/usr/bin/env python3
"""Create an isolated launch overlay; never modify the installed FAF archives."""
import hashlib
import json
import os
from pathlib import Path
import sys
import zipfile

binary, destination, team_size = Path(sys.argv[1]), Path(sys.argv[2]), int(sys.argv[3])
scouting_mode = os.environ.get('FAF_SCOUTING_MODE', 'combined')
if scouting_mode not in ('combined', 'production-only', 'dispatch-only'):
    raise SystemExit(f'Unknown FAF_SCOUTING_MODE: {scouting_mode!r}')
# Factions are pinned so a result is comparable across runs. They are overridable
# because pinning one pairing forever makes every conclusion a claim about that
# pairing only: the hover/amphibious fix, the largest single gain measured so
# far, is inert on Cybran and decisive on Aeon.
red_queen_faction = int(os.environ.get('FAF_RQ_FACTION', '2'))
adaptive_faction = int(os.environ.get('FAF_OPP_FACTION', '3'))
destination.mkdir(parents=True, exist_ok=True)
archive = binary.parent / 'gamedata/lua.nx2'
with zipfile.ZipFile(archive) as source:
    launch = source.read('lua/SinglePlayerLaunch.lua').decode()
    options = 'local options = table.copy(defaultOptions)'
    assert launch.count(options) == 1, 'Native command-line options contract changed'
    launch = launch.replace(options, options + '\n    options.RedQueenScoutingMode = '
                            + json.dumps(scouting_mode), 1)
    needle = 'aiOptions.Faction = GetRandomFaction()'
    assert launch.count(needle) == 1, 'Native launch contract changed'
    # Pin from the same team grouping used by simulation, before army creation.
    loop = 'local name\n        for index = 2, table.getn(armies) do'
    assert launch.count(loop) == 1, 'Native contestant loop changed'
    # FAF_NO_HUMAN=1 hands the launching player's start to an AI as well, so
    # every standard army is a contestant. A layout needs teams * size AI
    # starts and the human otherwise consumes one, which is why a 2v2v2 would
    # not fit a six-army map like Saltrock Colony.
    #
    # LaunchSinglePlayerSession is engine-side, so whether a session runs with
    # no human at all was not answerable from Lua. Measured instead: Saltrock
    # reported `allies=2 enemies=4 deficit=2 income=1.20` with all six armies
    # contesting. run-smoke.sh therefore defaults this on for layouts.
    if os.environ.get('FAF_NO_HUMAN') == '1':
        first = 'local name\n        for index = 2, table.getn(armies) do'
        launch = launch.replace(first, 'local name\n        for index = 1, table.getn(armies) do', 1)
        launch = launch.replace('playerOptions.Human = true', 'playerOptions.Human = false')
        loop = 'local name\n        for index = 1, table.getn(armies) do'
    launch = launch.replace(loop, '''local redQueenNames = {}
        for index = REDQUEEN_FIRST_ARMY, table.getn(armies) do
            table.insert(redQueenNames, armies[index])
        end
        table.sort(redQueenNames)
        local redQueenSelected = {}
        if REDQUEEN_TEAM_SIZE > 1 then
            local saveData = {}
            local loaded = pcall(function()
                doscript('/lua/dataInit.lua', saveData)
                doscript(sessionInfo.scenarioInfo.save, saveData)
            end)
            local chain = loaded and saveData.Scenario and saveData.Scenario.MasterChain
            local markers = chain and chain._MASTERCHAIN_ and chain._MASTERCHAIN_.Markers or {}
            local teams = import('/lua/redqueen-test-teams.lua').ProximityTeams(
                redQueenNames, 2, REDQUEEN_TEAM_SIZE, function(armyName)
                    local marker = markers[armyName]
                    return marker and (marker.position or marker.Position)
                end)
            for _, armyName in ipairs(teams[1] or {}) do
                redQueenSelected[armyName] = true
            end
        elseif redQueenNames[1] then
            redQueenSelected[redQueenNames[1]] = true
        end
        ''' + loop)
    launch = launch.replace('REDQUEEN_FIRST_ARMY',
        '1' if os.environ.get('FAF_NO_HUMAN') == '1' else '2')
    launch = launch.replace('REDQUEEN_TEAM_SIZE', str(team_size))
    launch = launch.replace(needle, f'aiOptions.Faction = redQueenSelected[name] and {red_queen_faction} or {adaptive_faction}')
    launch = launch.replace("GameSpeed = 'normal'", "GameSpeed = 'adjustable'")
    ui = source.read('lua/ui/game/gamemain.lua').decode()
    ui += '''
local RedQueenNativeFirstUpdate = OnFirstUpdate
function OnFirstUpdate()
    RedQueenNativeFirstUpdate()
    ForkThread(function()
        WaitSeconds(2)
        SetGameSpeed(10)
        LOG("RedQueen test launcher requested game speed +10")
    end)
end
'''
team_layout = (Path(__file__).resolve().parents[1] / 'lua/AI/RedQueen/TeamLayout.lua').read_text()
for name, text in {'lua/SinglePlayerLaunch.lua': launch, 'lua/ui/game/gamemain.lua': ui,
                   'lua/redqueen-test-teams.lua': team_layout}.items():
    target = destination / name
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text)
# The init remains the installed init, with its original InitFileDir and one
# additional higher-priority UI overlay. Simulation sources remain unchanged.
def wine(path):
    return 'Z:' + str(path.resolve())
init = (binary / 'init_faf.lua').read_text()
init = 'InitFileDir = ' + json.dumps(wine(binary)) + '\n' + init
init += '\ntable.insert(path, 1, { dir = ' + json.dumps(wine(destination)) + ', mountpoint = "/" })\n'
(destination / 'init.lua').write_text(init)
(destination / 'sources.json').write_text(json.dumps({
    'native_archive_sha256': hashlib.sha256(archive.read_bytes()).hexdigest(),
    'overlay': {str(p.relative_to(destination)): hashlib.sha256(p.read_bytes()).hexdigest()
                for p in destination.rglob('*.lua')},
    'team_size': team_size, 'factions': {'RedQueen': red_queen_faction, 'Adaptive': adaptive_faction},
    'scouting_mode': scouting_mode,
}, indent=2) + '\n')
print(wine(destination / 'init.lua'))
