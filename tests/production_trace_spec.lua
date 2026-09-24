function ClassSimple(definition)
    return setmetatable(definition, {
        __call = function(class, ...)
            local instance = setmetatable({}, { __index = class })
            instance:__init(...)
            return instance
        end,
    })
end

local tick = 0
function GetGameTick() return tick end
local messages = {}
local warnings = {}
function import(path)
    if path == "/mods/TheRedQueen/lua/AI/RedQueen/TeamLayout.lua" then
        local env = setmetatable({}, { __index = _G })
        setfenv(assert(loadfile("lua/AI/RedQueen/TeamLayout.lua")), env)()
        return env
    end
    assert(path == "/mods/TheRedQueen/lua/AI/RedQueen/Logger.lua")
    return {
        Info = function(_, message) table.insert(messages, message) end,
        Warning = function(_, message) table.insert(warnings, message) end,
    }
end
categories = { ENGINEER = 4, COMMAND = 1, FACTORY = 8, STRUCTURE = 2, EXPERIMENTAL = 16 }
ScenarioInfo = { name = "trace-test", Options = {} }
-- FAF Lua 5.0 supplies the implicit arg table (including n). LuaJIT does not;
-- supply that language feature for contracts without changing production code.
local file = assert(io.open("lua/AI/RedQueen/ProductionTrace.lua"))
local source = file:read("*a")
file:close()
source = string.gsub(source, "function([%w_%s]*)(%b())", function(name, parameters)
    if string.find(parameters, "...", 1, true) then
        return "function" .. name .. parameters .. " local arg = { n = select('#', ...), ... }; "
    end
    return "function" .. name .. parameters
end)
local nativeUnpack = unpack
unpack = function(values) return nativeUnpack(values, 1, values.n or table.getn(values)) end
assert(loadstring(source))()

local calls = { Condition = 0, Param = 0, Selection = 0, Random = 0, Orders = 0 }
local engineerBuilder = {
    BuilderName = "Engineer", Priority = 800,
    GetPlatoonTemplate = function() return "T1Engineer" end,
    GetBuilderStatus = function() calls.Condition = calls.Condition + 1; return true end,
}
local combatBuilder = {
    BuilderName = "Combat", Priority = 930,
    GetPlatoonTemplate = function() return "T2Tank" end,
    GetBuilderStatus = engineerBuilder.GetBuilderStatus,
}
local native = {
    BuilderParamCheck = function(_, _, params)
        calls.Param = calls.Param + 1
        assert(params[1].EntityId == 10)
        return true
    end,
    GetHighestBuilder = function(self, kind, params)
        calls.Selection = calls.Selection + 1
        local chosen
        for _, builder in ipairs(self.BuilderData[kind].Builders) do
            if chosen and builder.Priority < chosen.Priority then break end
            if self:BuilderParamCheck(builder, params) and builder:GetBuilderStatus() then chosen = builder end
        end
        -- Model a native tie-break call: tracing must never call the selector
        -- again (which would consume another random value / builder delay).
        calls.Random = calls.Random + 1
        calls.Orders = calls.Orders + 1
        return chosen, nil, "native-tail"
    end,
    Destroy = function(self) self.Destroyed = true; return "destroyed", nil, 42 end,
}
local manager = setmetatable({ LocationType = "MAIN", BuilderData = {
    Land = { Builders = { combatBuilder, engineerBuilder } },
} }, { __index = native })
local engineer = {
    EntityId = 20, EngineerBuildQueue = {},
    GetBlueprint = function() return { BlueprintId = "uel0105", CategoriesHash = { ENGINEER = true } } end,
    GetPosition = function() return { 10, 0, 20 } end,
    IsIdleState = function() return false end,
    IsUnitState = function() return false end,
}
local unitList = { engineer }
local brain = {
    GetArmyIndex = function() return 2 end,
    BuilderManagers = { MAIN = { FactoryManager = manager } },
    GetListOfUnits = function(_, category) return category == 3 and unitList or {} end,
}
local modules = {
    Production = { Counts = { Total = 1, Land = 1 },
        GetFactoryTargets = function() return { Total = 3, Land = 2, Air = 1 } end },
    Economy = { State = { MassIncome = 2, EnergyIncome = 30 } },
}
assert(Create(brain, modules) == nil, "tracing must be disabled by default")
local params = { { EntityId = 10 } }
local expected, middle, tail = manager:GetHighestBuilder("Land", params)
assert(expected == combatBuilder and middle == nil and tail == "native-tail")
local baseline = {}
for name, count in pairs(calls) do baseline[name] = count; calls[name] = 0 end

ScenarioInfo.Options.RedQueenProductionTrace = true
local trace = Create(brain, modules)
trace:Update()
local installed = manager.GetHighestBuilder
trace:Update()
assert(manager.GetHighestBuilder == installed, "repeated updates must not stack observers")
local chosen, nilValue, final = manager:GetHighestBuilder("Land", params)
assert(chosen == expected and nilValue == nil and final == tail, "all native return values must survive tracing")
for name, count in pairs(calls) do
    assert(count == baseline[name], "tracing changed native call count: " .. name)
end
local function Has(fragment)
    for _, message in ipairs(messages) do
        if string.find(message, fragment, 1, true) then return true end
    end
    return false
end
assert(not Has("event=selection"), "unrestricted selection logging must remain removed")
assert(rawget(manager, "GetHighestBuilder") == nil, "tracing must not wrap selectors")
assert(Has("event=engineer"), "missing manager/platoon fields must not break sampling")

local entry = { "ueb0101", { 12, 24, 0 }, false }
engineer.EngineerBuildQueue = { entry }
trace:ExpansionAttempt(engineer, "T1LandFactory", true, entry)
tick = 300
trace:Update()
assert(Has("status=queued"), "accepted requests must track their actual queue entry")
engineer.EngineerBuildQueue = { { "ueb1101", { 12, 24, 0 }, false } }
tick = 600
trace:Update()
assert(Has("status=queue-absent"), "queue replacement must not be confused with completion")
assert(table.getn(trace.Requests) == 0, "terminal request records must be released")

engineer.EngineerBuildQueue = { entry }
trace:ExpansionAttempt(engineer, "T1LandFactory", true, entry)
engineer.Dead = true
tick = 900
trace:Update()
assert(Has("status=engineer-lost"), "destroyed engineers must terminate their requests safely")
assert(trace.Engineers[20] == nil, "destroyed engineers must not accumulate in the observer")

local a, b, c = manager:Destroy()
assert(a == "destroyed" and b == nil and c == 42, "destroy callbacks retain all return values")
assert(rawget(manager, "GetHighestBuilder") == nil, "retired managers must restore inherited methods")
assert(trace.Managers == nil, "retired manager records must be removed")

local replacement = setmetatable({ LocationType = "MAIN", BuilderData = { Land = { Builders = {} } } }, { __index = native })
brain.BuilderManagers.MAIN.FactoryManager = replacement
trace:Update()
assert(rawget(replacement, "GetHighestBuilder") == nil, "replacement selectors must remain native")
brain.BuilderManagers = {}
trace:Update()
assert(rawget(replacement, "GetHighestBuilder") == nil, "removed managers must be restored even without Destroy")
for index = 1, 1000 do trace:Observe("defense", index, "evaluated", "") end
assert(trace.Subsystems.defense.Count == 64)
assert(trace.Subsystems.defense.Overflow == 936)
trace:Flush()
assert(Has("coverage=incomplete"))
local project = { EntityId = 9, GetBlueprint = function() return { CategoriesHash = { EXPERIMENTAL = true } } end }
trace:UnitStarted(engineer, project)
local lifetime = trace.Entities.projects[project].Lifetime
trace:UnitLost(project)
local reused = { EntityId = 9, GetBlueprint = project.GetBlueprint }
trace:UnitStarted(engineer, reused)
assert(trace.Entities.projects[reused].Lifetime > lifetime)
trace:UnitCompleted(reused, engineer)
assert(next(trace.Entities.projects) == nil)
ScenarioInfo.Options.RedQueenTraceArmy = 3
assert(Create(brain, modules) == nil, "only selected army traces")
trace:Destroy()
assert(table.getn(warnings) == 0, "all trace observations must succeed")
assert(table.getn(trace.Requests) == 0 and next(trace.Subsystems) == nil, "cleanup releases retained records")

-- Diagnostic match selection must be opt-in and reproduce the prior army
-- configuration without silently changing normal lobby/smoke personalities.
for _, difficulty in ipairs({ 2, 42, 43 }) do
    ScenarioInfo = { Options = { Difficulty = difficulty }, ArmySetup = {
        ARMY_1 = { Human = true, AIPersonality = "" },
        ARMY_2 = { AIPersonality = "rush" },
        ARMY_3 = { AIPersonality = "rush" },
        ARMY_4 = { AIPersonality = "rush" },
        NEUTRAL_CIVILIAN = { Civilian = true, AIPersonality = "civilian" },
    } }
    keyToBrain = { rush = "stock-rush", adaptive = "stock-adaptive" }
    dofile("hook/lua/aibrains/index.lua")
    assert(ScenarioInfo.ArmySetup.ARMY_1.AIPersonality == "", "the diagnostic must preserve human starts")
    if difficulty == 43 then
        assert(ScenarioInfo.Options.RedQueenProductionTrace, "the mixed diagnostic must enable tracing")
        assert(ScenarioInfo.ArmySetup.ARMY_2.AIPersonality == "redqueen")
        assert(ScenarioInfo.ArmySetup.ARMY_3.AIPersonality == "adaptive")
        assert(ScenarioInfo.ArmySetup.ARMY_4.AIPersonality == "")
        assert(keyToBrain.rush == "stock-rush", "diagnostics must not globally replace the stock brain")
    else
        assert(not ScenarioInfo.Options.RedQueenProductionTrace, "ordinary matches must not enable tracing")
        assert(ScenarioInfo.ArmySetup.ARMY_2.AIPersonality == "rush")
    end
end

print("Red Queen production trace contracts passed")
