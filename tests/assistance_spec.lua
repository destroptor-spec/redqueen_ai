local tick, clears, polls, nativeAssignments = 1000, 0, 0, 0
local cache = {}
function ClassSimple(definition)
    return setmetatable(definition, { __call = function(class, ...)
        local object = setmetatable({}, { __index = class })
        object:__init(...)
        return object
    end })
end
function GetGameTick() return tick end
local mt = {}
local function Category(predicate) return setmetatable({ Matches = predicate }, mt) end
mt.__mul = function(a, b) return Category(function(h) return a.Matches(h) and b.Matches(h) end) end
mt.__add = function(a, b) return Category(function(h) return a.Matches(h) or b.Matches(h) end) end
mt.__sub = function(a, b) return Category(function(h) return a.Matches(h) and not b.Matches(h) end) end
categories = setmetatable({}, { __index = function(self, name)
    local category = Category(function(h) return h[name] end)
    rawset(self, name, category)
    return category
end })
function EntityCategoryContains(category, unit) return category.Matches(unit.Hash) end
function IssueClearCommands(units)
    for _, unit in ipairs(units) do unit.Guard = nil; unit.Idle = true end
    clears = clears + 1
end
function IssueGuard(units, target)
    for _, unit in ipairs(units) do unit.Guard = target; unit.Idle = false end
end
function IssueMove(units, position) units[1].Position = position end
function KillThread() end
function import(path)
    local names = { Constants = true, Assistance = true, ExtractorUpgrades = true,
        ProductionManager = true, EngineerSurvival = true, AlertScope = true }
    local name = string.match(path, "/([^/]+)%.lua$")
    if names[name] then
        if not cache[name] then
            local env = setmetatable({}, { __index = _G })
            cache[name] = env
            setfenv(assert(loadfile("lua/AI/RedQueen/" .. name .. ".lua")), env)()
        end
        return cache[name]
    end
    return { Info = function() end, Announce = function() end }
end
local assistance = import('/mods/TheRedQueen/lua/AI/RedQueen/Assistance.lua')
local production = import('/mods/TheRedQueen/lua/AI/RedQueen/ProductionManager.lua')
local constants = import('/mods/TheRedQueen/lua/AI/RedQueen/Constants.lua')
local nativeManager = {
    Brain = { RedQueenLobbyPersonality = 'redqueen' },
    DelayAssign = function() polls = polls + 1 end,
    AssignEngineerTask = function(_, unit)
        nativeAssignments = nativeAssignments + 1
        unit.NativeAssigned = true
    end,
}
local hook = setmetatable({ EngineerManager = nativeManager }, { __index = _G })
setfenv(assert(loadfile('hook/lua/sim/EngineerManager.lua')), hook)()
local function Unit(id, hash, x)
    return {
        EntityId = id, Hash = hash, Army = 2, Position = { x or 0, 0, 0 }, Idle = true,
        EngineerBuildQueue = {}, BuilderManagerData = { EngineerManager = nativeManager },
        GetBlueprint = function(self)
            return { CategoriesHash = self.Hash, Physics = { MotionType = 'RULEUMT_Amphibious' } }
        end,
        GetArmy = function(self) return self.Army end,
        GetPosition = function(self) return self.Position end,
        GetFractionComplete = function(self) return self.Complete or 1 end,
        GetGuardedUnit = function(self) return self.Guard end,
        IsIdleState = function(self) return self.Idle end,
        IsUnitState = function(self, state) return self.State == state end,
    }
end
local function Setup()
    local acu = Unit(1, { COMMAND = true, ENGINEER = true }, 10)
    local engineer = Unit(2, { MOBILE = true, ENGINEER = true }, 5)
    local factory = Unit(3, { STRUCTURE = true, FACTORY = true }, 20)
    factory.State = 'Building'
    local units = { acu, engineer, factory }
    local brain = {
        GetArmyIndex = function() return 2 end,
        GetListOfUnits = function(_, category)
            local matches = {}
            for _, unit in ipairs(units) do
                if category.Matches(unit.Hash) then table.insert(matches, unit) end
            end
            return matches
        end,
        BuilderManagers = {},
    }
    local economy = { State = { Mode = 'Balanced', EnergyStoredRatio = 1 } }
    local strategy = { ProductionDemand = {} }
    local world = { StartPosition = { 0, 0, 0 },
        CanPath = function() return true end,
        GetObservedRouteThreat = function() return 0 end }
    return production.Create(brain, { FactionIndex = 1 }, world, economy, {}, strategy),
        acu, engineer, factory, units
end

-- Moving/combat commanders are not building targets. Choose the nearest
-- productive factory, deterministically, rather than the first factory.
local manager, acu, engineer, factory, units = Setup()
acu.Idle = false; acu.State = 'Moving'
local near = Unit(4, { STRUCTURE = true, FACTORY = true }, 12)
near.State = 'Building'; table.insert(units, near)
assert(manager:AssignIdleEngineers({ engineer }) == 1 and engineer.Guard == near)
local first = engineer.RedQueenAssist
manager:AssignIdleEngineers({ engineer })
assert(engineer.RedQueenAssist == first, 'valid assists must not be reissued every pass')
nativeManager:AssignEngineerTask(engineer)
assert(not engineer.NativeAssigned, 'native retries must respect the actual guard lease')

tick = first.Until + 1
nativeManager:AssignEngineerTask(engineer)
assert(engineer.NativeAssigned and not engineer.Guard and not engineer.RedQueenAssist,
    'native must release the guard and resume work when the lease expires')

manager, acu, engineer, factory = Setup()
acu.Idle = false; acu.State = 'Building'
assert(manager:AssignIdleEngineers({ engineer }) == 1 and engineer.Guard == acu)
acu.State = 'Moving'
manager:AssignIdleEngineers({ engineer })
assert(not engineer.Guard, 'helpers must release a commander as soon as it stops building')

for _, event in ipairs({ 'alert', 'stall', 'objective', 'death', 'capture', 'route', 'expiry' }) do
    manager, acu, engineer, factory = Setup()
    manager:AssignIdleEngineers({ engineer })
    local before = polls
    if event == 'alert' then manager.Strategy.ProductionDemand.DefenseAlert = { Active = true }
    elseif event == 'stall' then manager.Economy.State.StallRisk = true
    elseif event == 'objective' then manager.Strategy.CurrentObjective = { Type = 'Defend' }
    elseif event == 'death' then factory.Dead = true
    elseif event == 'capture' then factory.Army = 3
    elseif event == 'route' then manager.World.GetObservedRouteThreat = function() return 100 end
    else tick = engineer.RedQueenAssist.Until + 1 end
    manager:AssignIdleEngineers({ engineer })
    assert(not engineer.Guard and polls == before + 1, event .. ' must release and hand back')
end

-- A stale lease must not stop, reassign, or clear metadata from replacement work.
for _, replacement in ipairs({ 'platoon', 'queue', 'guard', 'capture' }) do
    manager, acu, engineer, factory = Setup()
    manager:AssignIdleEngineers({ engineer })
    if replacement == 'platoon' then engineer.PlatoonHandle = {}
    elseif replacement == 'queue' then engineer.EngineerBuildQueue = { { 'ueb1101' } }
    elseif replacement == 'guard' then engineer.Guard = acu
    else engineer.Army = 3 end
    local before, beforePolls = clears, polls
    manager.Strategy.CurrentObjective = { Type = 'Defend' }
    manager:MaintainIdleAssistants()
    assert(clears == before and polls == beforePolls and engineer.Guard,
        'do not clear replacement ' .. replacement)
end

for _, unsafe in ipairs({ 'distance', 'home', 'path', 'threat', 'unfinished', 'idle-target', 'stall', 'defense' }) do
    manager, acu, engineer, factory = Setup()
    if unsafe == 'distance' then factory.Position = { 1000, 0, 0 }
    elseif unsafe == 'home' then
        factory.State = nil; acu.State = 'Building'; acu.Position = { 100, 0, 0 }; engineer.Position = { 90, 0, 0 }
    elseif unsafe == 'path' then manager.World.CanPath = function() return false end
    elseif unsafe == 'threat' then manager.World.GetObservedRouteThreat = function() return 100 end
    elseif unsafe == 'unfinished' then factory.Complete = 0.5
    elseif unsafe == 'idle-target' then factory.State = nil
    elseif unsafe == 'stall' then manager.Economy.State.StallRisk = true
    else manager.Strategy.ProductionDemand.DefenseAlert = { Active = true } end
    assert(manager:AssignIdleEngineers({ engineer }) == 0, 'reject ' .. unsafe)
end

-- Native roster engineers are eligible without being in ArmyPool, but queued
-- construction, retreats and previously claimed custom jobs remain untouched.
manager, acu, engineer, factory = Setup()
manager.Brain.BuilderManagers.MAIN = { EngineerManager = { GetUnits = function() return { engineer } end } }
assert(manager:AssignIdleEngineers({}) == 1, 'find idle native-manager engineers')
for _, held in ipairs({ 'queue', 'production', 'defense', 'core', 'factory', 'retreat' }) do
    manager, acu, engineer = Setup()
    if held == 'queue' then engineer.EngineerBuildQueue = { { 'ueb1101' } }
    elseif held == 'production' then engineer.RedQueenProductionBuildUntil = tick + 100
    elseif held == 'defense' then engineer.RedQueenEmergencyDefenseUntil = tick + 100
    elseif held == 'core' then engineer.RedQueenCoreUpgradeUntil = tick + 100
    elseif held == 'factory' then engineer.RedQueenFactoryAssistUntil = tick + 100
    else engineer.RedQueenRetreatPosition = { 900, 0, 900 } end
    assert(manager:AssignIdleEngineers({ engineer }) == 0, 'preserve ' .. held)
end

-- Stateful commander handback: one native opportunity, then a fallback that
-- lasts through subsequent production/native passes and hands back at expiry.
manager, acu, engineer, factory = Setup()
manager.Economy.State.Mode = 'Opening'
local before = polls
assert(manager:DecideCommanderTasking() == 'opening-build' and polls == before + 1)
tick = tick + constants.Policy.CommanderHandbackSeconds * 10
assert(manager:DecideCommanderTasking() == 'assist' and acu.Guard == factory)
tick = tick + 30
assert(manager:DecideCommanderTasking() == 'assisting' and acu.Guard == factory)
nativeManager:AssignEngineerTask(acu)
assert(not acu.NativeAssigned, 'native cannot replace fallback during its lease')
tick = acu.RedQueenAssist.Until + 1
assert(manager:DecideCommanderTasking() == 'opening-build' and not acu.Guard)
local handback = acu.RedQueenHandbackTick
tick = tick + 30
assert(manager:DecideCommanderTasking() == 'opening-build' and acu.RedQueenHandbackTick == handback)

manager, acu, engineer, factory = Setup()
assert(manager:DecideCommanderTasking() == 'assist')
manager.Economy.State.StallRisk = true
before = polls
assert(manager:DecideCommanderTasking() == 'economy-build' and polls == before + 1 and not acu.Guard,
    'new stall must hand a regular assist back to native')
acu.Idle = false; acu.State = 'Building'; acu.EngineerBuildQueue = { { 'ueb1101' } }
tick = tick + 300
assert(manager:DecideCommanderTasking() == 'economy-build' and #acu.EngineerBuildQueue == 1,
    'preserve native construction and reset the idle window')
assert(not acu.RedQueenHandbackTick)

manager, acu, engineer, factory = Setup()
manager:DecideCommanderTasking()
acu.EngineerBuildQueue = { { 'ueb1101' } }; acu.PlatoonHandle = {}
before = clears
manager.Economy.State.StallRisk = true
manager:DecideCommanderTasking()
assert(clears == before and #acu.EngineerBuildQueue == 1, 'stale commander lease cannot cancel native work')

nativeManager.Brain.RedQueenLobbyPersonality = nil
manager, acu, engineer, factory = Setup()
manager:AssignIdleEngineers({ engineer })
before = nativeAssignments
nativeManager:AssignEngineerTask(engineer)
assert(nativeAssignments == before + 1, 'stock AI retains native assignment behavior')
print('Red Queen assist ownership, safety, expiry and commander handback contracts passed')
