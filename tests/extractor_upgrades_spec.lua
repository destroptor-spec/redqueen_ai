-- Environment-as-module, the way the engine's import behaves.
local function LoadModule(path)
    local environment = setmetatable({}, { __index = _G })
    setfenv(assert(loadfile(path)), environment)()
    return environment
end
local constants, alertScope, upgrades
function import(path)
    if path == '/mods/TheRedQueen/lua/AI/RedQueen/Constants.lua' then return constants end
    if path == '/mods/TheRedQueen/lua/AI/RedQueen/AlertScope.lua' then return alertScope end
    return upgrades
end
-- The real alert extent and the real radius: whether an alert reaches a given
-- extractor is the behaviour under test, not something a stub should answer.
constants = LoadModule('lua/AI/RedQueen/Constants.lua')
alertScope = LoadModule('lua/AI/RedQueen/AlertScope.lua')
upgrades = LoadModule('lua/AI/RedQueen/ExtractorUpgrades.lua')
local nativeCalls = 0
Platoon = { ForkThread = function() end, UnitUpgradeAI = function(self)
    nativeCalls = nativeCalls + 1
    for _, unit in ipairs(self.Units) do unit.Stopped = true; unit.NewUpgrade = true end
end }
setfenv(assert(loadfile('hook/lua/platoon.lua')), getfenv(1))()
local function Unit(extractor, running, position)
    return { Running = running,
        GetBlueprint = function() return { CategoriesHash = { STRUCTURE = true, MASSEXTRACTION = extractor } } end,
        GetPosition = position and function() return position end or nil,
        IsUnitState = function() return running end }
end
local function Run(units, redqueen, state, alert)
    local pool = { Units = {} }
    local brain = { RedQueenLobbyPersonality = redqueen,
        RedQueenModules = { Economy = { State = state }, Strategy = { ProductionDemand = { DefenseAlert = alert } } },
        GetPlatoonUniquelyNamed = function() return pool end }
    local platoon = setmetatable({ Units = units, GetBrain = function() return brain end,
        GetPlatoonUnits = function(self) return self.Units end,
        PlatoonDisband = function(self)
            assert(#self.Units == 0, 'disband must never cancel withheld extractors')
            self.Disbanded = true
        end }, { __index = Platoon })
    brain.AssignUnitsToPlatoon = function(_, target, moved)
        local retained = {}
        for _, unit in ipairs(platoon.Units) do
            local remove = false
            for _, candidate in ipairs(moved) do if candidate == unit then remove = true end end
            if remove then table.insert(target.Units, unit) else table.insert(retained, unit) end
        end
        platoon.Units = retained
    end
    platoon:UnitUpgradeAI()
    return brain, platoon, pool
end
for _, reason in ipairs({ 'attack', 'stall' }) do
    local mex = Unit(true, false)
    local brain, platoon, pool = Run({ mex }, 'redqueen', { StallRisk = reason == 'stall' }, { Active = reason == 'attack' })
    assert(not mex.NewUpgrade and not mex.Stopped and platoon.Disbanded and pool.Units[1] == mex)
    assert(brain.RedQueenExtractorBlocks == 1, 'blocked native starts must be observable')
end
local mex, running, factory = Unit(true, false), Unit(true, true), Unit(false, false)
local brain, platoon, pool = Run({ mex, running, factory }, 'redqueen', {}, { Active = true })
assert(factory.NewUpgrade and not mex.NewUpgrade and not running.Stopped and #pool.Units == 2,
    'mixed platoons must preserve factories and upgrades already underway')
mex = Unit(true, false)
Run({ mex }, 'redqueen', {}, { Active = false })
assert(mex.NewUpgrade, 'upgrades resume after the alert clears')
running = Unit(true, true)
Run({ running }, 'redqueen', {}, {})
assert(not running.Stopped, 'an upgrade already underway must not be restarted even without an alert')
mex = Unit(true, false)
Run({ mex }, nil, { StallRisk = true }, { Active = true })
assert(mex.NewUpgrade, 'stock AI upgrade plans remain untouched')
assert(upgrades.BlockReason({}, {}) == nil)

-- An alert is a place, not an army-wide switch.
--
-- `mexgate=under-attack` was the dominant sample on every LandLarge cell of the
-- control matrix -- 26 of 35 on Syrtis Major 8675309 -- because any alert
-- anywhere withheld every extractor from upgrading, Red Queen's own and
-- native's. Both directions are contracted: an alert on top of the extractor
-- still stops it, one at an expansion does not.
local radius = constants.Policy.DefenseAlertWorkRadius
local far = { Active = true, AnchorPosition = { 500, 0, 500 } }
local near = { Active = true, AnchorPosition = { 10, 0, 10 } }

local home = Unit(true, false, { 10, 0, 10 })
Run({ home }, 'redqueen', {}, far)
assert(home.NewUpgrade, 'an alert at an expansion must not withhold the extractor at home')

local attacked = Unit(true, false, { 10, 0, 10 })
local brain2 = Run({ attacked }, 'redqueen', {}, near)
assert(not attacked.NewUpgrade, 'an alert on top of the extractor still withholds it')
assert(brain2.RedQueenExtractorBlocks == 1, 'a scoped block stays observable')

-- The boundary itself, from both sides of the radius.
local inside = Unit(true, false, { 10 + radius - 1, 0, 10 })
Run({ inside }, 'redqueen', {}, near)
assert(not inside.NewUpgrade, 'inside the radius is covered')
local outside = Unit(true, false, { 10 + radius + 1, 0, 10 })
Run({ outside }, 'redqueen', {}, near)
assert(outside.NewUpgrade, 'outside the radius is not covered')

-- Stall risk really is army-wide: there is no spare mass anywhere.
local stalled = Unit(true, false, { 10, 0, 10 })
Run({ stalled }, 'redqueen', { StallRisk = true }, far)
assert(not stalled.NewUpgrade, 'stall risk withholds regardless of where the alert is')

-- An alert with no anchor has no known extent and keeps the old answer.
local unknown = Unit(true, false, { 10, 0, 10 })
Run({ unknown }, 'redqueen', {}, { Active = true })
assert(not unknown.NewUpgrade, 'an alert with no anchor still covers the army')

-- BlockReason over a set: blocked only when the alert is on top of all of it.
local function At(x) return { GetPosition = function() return { x, 0, 0 } end } end
assert(upgrades.BlockReason({}, near, { At(10), At(1000) }) == nil,
    'one extractor outside the alert is enough to keep upgrading')
assert(upgrades.BlockReason({}, near, { At(10), At(20) }) == 'under-attack',
    'an alert over the whole set blocks it')
assert(upgrades.BlockReason({ StallRisk = true }, nil, { At(1000) }) == 'stall-risk',
    'stall risk outranks the scope')
assert(upgrades.BlockReason({}, near, nil) == 'under-attack',
    'no set means no known extent, which is the old army-wide answer')
assert(upgrades.BlockReason({}, near, {}) == 'under-attack',
    'an empty set has nothing to exempt')
assert(upgrades.BlockReason({}, { Active = false }, { At(10) }) == nil,
    'an inactive alert blocks nothing')

print('Red Queen native extractor start, recovery and in-progress preservation contracts passed')
print('Red Queen extractor upgrade alert-scope contracts passed')
