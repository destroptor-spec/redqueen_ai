local upgrades = setmetatable({}, { __index = _G })
setfenv(assert(loadfile('lua/AI/RedQueen/ExtractorUpgrades.lua')), upgrades)()
function import() return upgrades end
local nativeCalls = 0
Platoon = { ForkThread = function() end, UnitUpgradeAI = function(self)
    nativeCalls = nativeCalls + 1
    for _, unit in ipairs(self.Units) do unit.Stopped = true; unit.NewUpgrade = true end
end }
setfenv(assert(loadfile('hook/lua/platoon.lua')), getfenv(1))()
local function Unit(extractor, running)
    return { Running = running,
        GetBlueprint = function() return { CategoriesHash = { STRUCTURE = true, MASSEXTRACTION = extractor } } end,
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
print('Red Queen native extractor start, recovery and in-progress preservation contracts passed')
