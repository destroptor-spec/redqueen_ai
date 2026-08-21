local RedQueenBrainReference = {
    "/mods/TheRedQueen/lua/AI/RedQueenBrain.lua",
    "AIBrain",
}

keyToBrain.redqueen = RedQueenBrainReference

-- Direct `/map` launches create Rush opponents before UI hooks are mounted.
-- The smoke runner carries an out-of-range skirmish difficulty sentinel into
-- the simulation. Lobby difficulty values never use 42.
local RedQueenSmoke = ScenarioInfo.Options.Difficulty
if RedQueenSmoke == 42 or RedQueenSmoke == "42" then
    keyToBrain.rush = RedQueenBrainReference
end
