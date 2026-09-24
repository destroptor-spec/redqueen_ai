-- Run with pure stand-ins, or with installed native disband/task methods from
-- scripts/check-native-engineer-recall.py. The order scheduler is deterministic.
local survival
function ClassSimple(definition) return definition end
function import(path)
    if path == "/mods/TheRedQueen/lua/AI/RedQueen/Constants.lua" then
        return { Policy = { EngineerSurvivalHomeRadius = 80 } }
    end
    if path == "/mods/TheRedQueen/lua/AI/RedQueen/EngineerSurvival.lua" then return survival end
    if path == "/mods/TheRedQueen/lua/AI/RedQueen/Assistance.lua" then
        local assistance = setmetatable({}, { __index = _G })
        setfenv(assert(loadfile("lua/AI/RedQueen/Assistance.lua")), assistance)()
        return assistance
    end
    return {}
end
survival = setmetatable({}, { __index = _G })
setfenv(assert(loadfile("lua/AI/RedQueen/EngineerSurvival.lua")), survival)()
local file = assert(io.open("lua/AI/RedQueen/ProductionManager.lua"))
local source = file:read("*a")
file:close()
local env = setmetatable({}, { __index = _G })
setfenv(assert(loadstring(source .. "\nRecallForTest = ReleaseEngineer")), env)()

local tick = 100
local threads = {}
function KillThread(thread) thread.Killed = true end
function GetGameTimeSeconds() return tick / 10 end
function VDist3(a, b)
    return math.sqrt((a[1] - b[1]) ^ 2 + (a[3] - b[3]) ^ 2)
end
categories = { COMMAND = 1 }
function EntityCategoryContains() return false end
function IssueToUnitStop() end
function IssueToUnitClearCommands(unit) unit.Order = nil end
function IssueClearCommands(units)
    assert(not units[1].ForkedEngineerTask, "disband-created task must be cancelled before commands")
    units[1].Order = nil
end
function IssueMove(units) units[1].Order = "home" end
local function fork(unit, fn, ...)
    local args = { ... }
    local thread = { Coroutine = coroutine.create(function() fn(unit, unpack(args)) end) }
    local ok, delay = coroutine.resume(thread.Coroutine)
    assert(ok, delay)
    thread.At = tick + (delay or 0)
    table.insert(threads, thread)
    return thread
end
local function advance(ticks)
    for step = 1, ticks do
        tick = tick + 1
        local count = #threads
        for index = 1, count do
            local thread = threads[index]
            if not thread.Killed and coroutine.status(thread.Coroutine) ~= "dead" and thread.At <= tick then
                local ok, delay = coroutine.resume(thread.Coroutine)
                assert(ok, delay)
                thread.At = tick + (delay or 0)
            end
        end
    end
end
local native = NativeRecallEngineerManager or {
    Wait = function(unit, manager, ticks)
        coroutine.yield(ticks)
        if not unit.Dead then manager:AssignEngineerTask(unit) end
    end,
    DelayAssign = function(manager, unit, ticks)
        if unit.ForkedEngineerTask then KillThread(unit.ForkedEngineerTask) end
        unit.ForkedEngineerTask = unit:ForkThread(manager.Wait, manager, ticks or 10)
    end,
    ForkEngineerTask = function(manager, unit)
        manager:DelayAssign(unit, unit.ForkedEngineerTask and 3 or 20)
    end,
    TaskFinished = function(manager, unit) manager:ForkEngineerTask(unit) end,
}
local assignments = 0
native.AssignEngineerTask = function(_, unit)
    assignments = assignments + 1
    unit.Order = "native-build"
end
local hookEnv = setmetatable({ EngineerManager = native }, { __index = _G })
setfenv(assert(loadfile("hook/lua/sim/EngineerManager.lua")), hookEnv)()
local brain = { RedQueenLobbyPersonality = "redqueen", DisbandPlatoon = function() end }
local manager = setmetatable({ Brain = brain, Location = { 900, 0, 900 }, Radius = 100 }, { __index = native })
local position = { 900, 0, 900 }
local unit = {
    GetPosition = function() return position end, ForkThread = fork,
    IsPaused = function() return false end,
    BuilderManagerData = { EngineerManager = manager },
}
local disbandTask
local function disband(platoon)
    if NativeRecallPlatoon then NativeRecallPlatoon.PlatoonDisband(platoon)
    else manager:TaskFinished(unit) end
    disbandTask = unit.ForkedEngineerTask
end
unit.PlatoonHandle = {
    PlatoonDisband = disband,
    GetBrain = function() return brain end,
    GetPlatoonUnits = function() return { unit } end,
    CreationTime = 0,
}
manager:ForkEngineerTask(unit)
local previous = unit.ForkedEngineerTask
assert(env.RecallForTest(unit, { 0, 0, 0 }))
assert(previous.Killed and disbandTask.Killed, "cancel tasks from before and during disband")
advance(1000)
assert(assignments == 0 and unit.Order == "home", "native retries must preserve the entire retreat")
position = { 10, 0, 10 }
advance(50)
assert(assignments == 1 and unit.Order == "native-build" and not unit.RedQueenRetreatPosition,
    "arrival must restore native work, without permanently suppressing the engineer")
brain.RedQueenLobbyPersonality = nil
unit.RedQueenRetreatPosition = { 1000, 0, 1000 }
manager:AssignEngineerTask(unit)
assert(assignments == 2, "stock brains must retain native assignments")
print("Red Queen engineer recall ownership contracts passed")
