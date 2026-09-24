-- Opt-in integration fixture. Uses real FAF managers and keyed conditions;
-- intentionally defeats the selected brain and is never balance evidence.
local Lifecycle = import("/mods/TheRedQueen/lua/AI/RedQueen/BaseLifecycle.lua")
local Logger = import("/mods/TheRedQueen/lua/AI/RedQueen/Logger.lua")

function Run(brain)
    WaitTicks(200)
    local location = "RQFB_LIFECYCLE_TEST"
    local pos = brain:GetStartVector3f()
    local marker = { type = "Expansion Area", position = { pos[1] + 30, pos[2], pos[3] + 30 } }
    Scenario.MasterChain._MASTERCHAIN_.Markers[location] = marker
    brain:AddBuilderManagers(marker.position, 40, location, false)
    local old = brain.BuilderManagers[location]
    old.BaseSettings = {}
    local monitor = brain.ConditionsMonitor
    local key = monitor:GetConditionKey("/lua/editor/UnitCountBuildConditions.lua", "EngineerLessAtLocation",
        { location, 1, categories.ALLUNITS })
    local instant = monitor.ResultTable[key]
    local function CheckBase(current, name)
        assert(current.BuilderManagers[name].EngineerManager)
        return true
    end
    local cachedKey = monitor:GetConditionKeyFunction(CheckBase, { location })
    local cached = monitor.ResultTable[cachedKey]
    assert(instant:GetStatus() and cached:CheckCondition())
    old.EngineerManager:Destroy()
    assert(not instant:GetStatus() and not cached:CheckCondition())
    brain.BuilderManagers[location] = nil
    assert(not instant:GetStatus() and not cached:LocationExists())
    brain:AddBuilderManagers(marker.position, 40, location, false)
    local replacement = brain.BuilderManagers[location]
    replacement.BaseSettings = {}
    brain.RedQueenModules.Production.CounterBuildersRegistered[location] = replacement
    old.FactoryManager:Destroy()
    old.PlatoonFormManager:Destroy()
    assert(brain.RedQueenModules.Production.CounterBuildersRegistered[location] == replacement)
    assert(instant:GetStatus() and cached:CheckCondition())
    local manager = replacement.EngineerManager
    replacement.EngineerManager = nil
    assert(not instant:GetStatus() and not cached:CheckCondition())
    replacement.EngineerManager = manager
    Logger.Info(brain, "fixture lifecycle base-destroy-rebuild-partial passed")
    brain:OnDefeat()
    assert(not instant:GetStatus() and not cached:CheckCondition())
    Lifecycle.Cleanup(brain)
    Logger.Info(brain, "fixture lifecycle brain-defeat passed")
end
