-- The spectator line. Every assertion here corresponds to something that was
-- seen on screen and could not be recovered from a log afterwards.

local logged = {}
local logger = {
    Info = function(_, message) table.insert(logged, message) end,
    Debug = function() end,
    Warning = function() end,
    Error = function() end,
}

function table.getn(value)
    local count = 0
    for _ in pairs(value or {}) do count = count + 1 end
    return count
end

-- Category expressions are opaque handles in the engine. Composed names let a
-- stub brain answer a count for an exact expression, which is the only way to
-- tell "Tech 2 point defence" from "Tech 2 anti-air" in a contract.
local categoryMetatable = {}
local function Compose(left, right, operator)
    return setmetatable(
        { Name = "(" .. tostring(left.Name) .. operator .. tostring(right.Name) .. ")" },
        categoryMetatable
    )
end
categoryMetatable.__mul = function(left, right) return Compose(left, right, "*") end
categoryMetatable.__sub = function(left, right) return Compose(left, right, "-") end
categories = setmetatable({}, {
    __index = function(value, key)
        local category = setmetatable({ Name = key }, categoryMetatable)
        rawset(value, key, category)
        return category
    end,
})

local function importModule(path)
    local environment = setmetatable({}, { __index = _G })
    setfenv(assert(loadfile(path)), environment)()
    return environment
end

function import(path)
    if path == "/mods/TheRedQueen/lua/AI/RedQueen/Logger.lua" then
        return logger
    end
    error("unexpected import: " .. tostring(path))
end

local observer = importModule("lua/AI/RedQueen/Observer.lua")

local function Brain(counts, units)
    return {
        GetCurrentUnits = function(_, category) return (counts or {})[category.Name] or 0 end,
        GetListOfUnits = function(_, category) return (units or {})[category.Name] or {} end,
    }
end

local function Commander(fields)
    local unit = {
        States = fields.States or {},
        Dead = fields.Dead,
        GetPosition = function() return fields.Position or { 0, 0, 0 } end,
        GetHealth = function() return fields.Health or 12000 end,
        GetMaxHealth = function() return 12000 end,
    }
    unit.IsUnitState = function(self, name) return self.States[name] or false end
    return unit
end

local function CommanderCategory()
    return categories.COMMAND.Name
end

local function Run(block) block() end

-- A commander assisting a factory walks between build sites, so the engine
-- reports it as both guarding and moving. The observation that mattered was
-- "still only assists primary land factory" -- reporting that as "moving"
-- would have hidden exactly the behaviour under investigation.
Run(function()
    local units = {}
    units[CommanderCategory()] = { Commander({ States = { Guarding = true, Moving = true } }) }
    local facts = observer.CommanderFacts(Brain({}, units), { 0, 0, 0 })
    assert(facts.State == "assisting", "assisting must win over moving, got " .. facts.State)
end)

-- Upgrading is also building. The first Tech 2 structure of a match being a
-- missile launcher was found this way, and an upgrade misreported as a plain
-- build loses it.
Run(function()
    local units = {}
    units[CommanderCategory()] = { Commander({ States = { Upgrading = true, Building = true } }) }
    local facts = observer.CommanderFacts(Brain({}, units), { 0, 0, 0 })
    assert(facts.State == "upgrading", "upgrading must win over building, got " .. facts.State)
end)

-- Distance from home is the leash's own measurement. A commander that wandered
-- out and died reported one recall in a whole match, and without a distance
-- every minute there is no way to tell a leash that never fired from one that
-- fired and was ignored.
Run(function()
    local units = {}
    units[CommanderCategory()] = { Commander({ Position = { 30, 0, 40 }, Health = 6000 }) }
    local facts = observer.CommanderFacts(Brain({}, units), { 0, 0, 0 })
    assert(math.abs(facts.Distance - 50) < 0.01, "distance must be planar, got " .. facts.Distance)
    assert(math.abs(facts.Health - 50) < 0.01, "health must be a percentage, got " .. facts.Health)
    assert(facts.State == "idle", "no reported unit state is idle, got " .. facts.State)
end)

-- No living commander is the single most important fact about a Red Queen
-- army; an absent field would read as a formatting gap.
Run(function()
    local units = {}
    units[CommanderCategory()] = { Commander({ Dead = true }) }
    assert(observer.CommanderFacts(Brain({}, units), { 0, 0, 0 }).State == "dead")
    assert(observer.CommanderFacts(Brain({}, {}), { 0, 0, 0 }).State == "dead")
end)

Run(function()
    local engineerCategory = (categories.ENGINEER * categories.MOBILE - categories.COMMAND).Name
    local units = {}
    units[engineerCategory] = {
        { IsIdleState = function() return true end },
        { IsIdleState = function() return false end },
        { IsIdleState = function() return true end },
        { Dead = true, IsIdleState = function() return true end },
    }
    local idle, total = observer.IdleEngineers(Brain({}, units))
    assert(idle == 2, "a dead engineer is not an idle one, got " .. idle)
    assert(total == 4, "the total is every engineer held, got " .. total)
end)

-- Enemy strength is summed across every enemy army. A free-for-all reports one
-- figure, and one opponent's army must not be mistaken for the whole field.
Run(function()
    local combat = categories.MOBILE
        - categories.ENGINEER
        - categories.COMMAND
        - categories.SCOUT
        - categories.TRANSPORTFOCUS
    local function Army(tech1)
        local counts = {}
        counts[(combat * categories.TECH1).Name] = tech1
        return Brain(counts, {})
    end
    ArmyBrains = { [3] = Army(10), [4] = Army(7) }
    local brain = Brain({}, {})
    brain.RedQueenContext = { EnemyArmies = { 3, 4 } }
    local facts = observer.Collect(brain, { World = {}, Economy = { State = {} } })
    assert(facts.Enemy[1] == 17, "every enemy army counts, got " .. facts.Enemy[1])
    ArmyBrains = nil
end)

-- The line is parsed by a watcher while the match is still running, so its
-- shape is a contract and not a convenience.
Run(function()
    local facts = {
        Time = 512,
        Commander = { State = "assisting", Distance = 14.4, Health = 100 },
        PointDefense = { 1, 0, 0 },
        AntiAir = { 0, 0, 0 },
        AntiMissile = 0,
        Shields = 0,
        MissileLaunchers = 1,
        Artillery = 0,
        Extractors = { 9, 2, 0 },
        IdleEngineers = 3,
        Engineers = 11,
        Own = { 12, 0, 0, 0 },
        Enemy = { 19, 2, 0, 0 },
        MassStored = 0.12,
        EnergyStored = 0.03,
    }
    local line = observer.Format(facts)
    assert(string.find(line, "^watch t=512 "), "the line must open with its kind and time: " .. line)
    assert(string.find(line, "acu=assisting/14/100", 1, true), line)
    assert(string.find(line, "def=pd1/0/0,aa0/0/0,tmd0,sh0,tml1,arty0", 1, true), line)
    assert(string.find(line, "mex=9/2/0", 1, true), line)
    assert(string.find(line, "eng=3/11", 1, true), line)
    assert(string.find(line, "units=12/0/0/0 enemy=19/2/0/0", 1, true), line)
    assert(string.find(line, "store=0.12/0.03", 1, true), line)
end)

print("observer_spec ok")
