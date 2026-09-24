-- Opt-in fixture injected by scripts/verify-observation-fixes.py.
local function Check(value, message)
    if not value then
        LOG('[RQObservationFixes] FAIL ' .. message)
        error(message)
    end
end
local function Report(message) LOG('[RQObservationFixes] ' .. message) end

function Run()
    WaitTicks(150)
    local brain = ArmyBrains[2]
    Check(brain and brain.RedQueenModules, 'Red Queen must initialize')
    local modules = brain.RedQueenModules
    -- This fixture drives its own production instance. Keep the ordinary
    -- production cadence from taking a released test engineer between cases.
    modules.Production.Update = function() end
    local start = modules.World.StartPosition
    local xdir = start[1] < modules.World.Width / 2 and 1 or -1
    local zdir = start[3] < modules.World.Height / 2 and 1 or -1
    local function Spawn(id, dx, dz)
        local x, z = start[1] + dx * xdir, start[3] + dz * zdir
        return CreateUnitHPR(id, brain:GetArmyIndex(), x, GetSurfaceHeight(x, z), z, 0, 0, 0)
    end
    local acu = Spawn('uel0001', 15, 10)
    local engineer = Spawn('uel0105', 12, 10)
    local factory = Spawn('ueb0101', 25, 20)
    brain:GiveResource('MASS', 50000)
    brain:GiveResource('ENERGY', 500000)
    brain:BuildUnit(factory, 'uel0201', 20)
    local roster = { acu, engineer, factory }
    local testBrain = {
        Army = brain.Army,
        GetArmyIndex = function() return brain:GetArmyIndex() end,
        GetListOfUnits = function(self, category)
            local selected = {}
            for _, unit in ipairs(roster) do
                if not unit.Dead and EntityCategoryContains(category, unit) then table.insert(selected, unit) end
            end
            return selected
        end,
    }
    local economy = { State = { Mode = 'Balanced', StallRisk = false, EnergyStoredRatio = 0.8 } }
    local strategy = { ProductionDemand = {} }
    local production = import('/mods/TheRedQueen/lua/AI/RedQueen/ProductionManager.lua').Create(
        testBrain, brain.RedQueenContext, modules.World, economy, modules.Intel, strategy)
    -- Real native task scheduling and the real hook, with builder selection
    -- returning no work so the idle timeout can be reached deterministically.
    local native = import('/lua/sim/EngineerManager.lua').EngineerManager
    local manager = setmetatable({ Brain = brain,
        GetHighestBuilder = function(self, kind, params)
            params[1].FixtureNativePolls = (params[1].FixtureNativePolls or 0) + 1
            return nil
        end,
    }, { __index = native })
    engineer.BuilderManagerData = { EngineerManager = manager }
    acu.BuilderManagerData = { EngineerManager = manager }
    IssueClearCommands({ acu, engineer })
    IssueMove({ acu }, { start[1] + 65 * xdir, start[2], start[3] + 10 * zdir })
    WaitTicks(10)
    Check(acu:IsUnitState('Moving') and factory:IsUnitState('Building'), 'moving ACU and productive factory setup')
    Check(production:AssignIdleEngineers({ engineer }) == 1, 'idle helper receives useful work')
    WaitTicks(5)
    Check(engineer:GetGuardedUnit() == factory, 'moving ACU must not attract helpers')
    local record = engineer.RedQueenAssist
    WaitTicks(60)
    Check(engineer:GetGuardedUnit() == factory and not engineer.FixtureNativePolls,
        'native retry must preserve a valid helper lease')
    while GetGameTick() <= record.Until + 55 do WaitTicks(10) end
    Check(not engineer:GetGuardedUnit() and (engineer.FixtureNativePolls or 0) > 0,
        'expired helper must actually resume native assignment')
    production:MaintainIdleAssistants()
    Check(production.AssistSummary.Released == 1, 'native expiry is counted in diagnostics')
    Report('helper moving-acu-rejected=true native-hold=true expired-and-resumed=true')

    WaitTicks(55)
    Report(string.format('reuse idle=%s building=%s safe=%s queue=%d process=%s retreat=%s held=%s retry=%s tick=%d',
        tostring(engineer:IsIdleState()), tostring(factory:IsUnitState('Building')),
        tostring(production:IsSafeAssistTarget(engineer, factory)), table.getn(engineer.EngineerBuildQueue or {}),
        tostring(engineer.ProcessBuild), tostring(engineer.RedQueenRetreatPosition),
        tostring(engineer.RedQueenAssist), tostring(engineer.RedQueenAssistRetryTick), GetGameTick()))
    Check(production:AssignIdleEngineers({ engineer }) == 1, 'helper can be reused after native opportunity')
    WaitTicks(5)
    strategy.ProductionDemand.DefenseAlert = { Active = true }
    economy.State.StallRisk = true
    production:AssignIdleEngineers({ engineer })
    WaitTicks(5)
    Check(not engineer:GetGuardedUnit(), 'alert/stall releases helpers')
    Report('helper emergency-release=true')

    IssueClearCommands({ acu })
    WaitTicks(5)
    strategy.ProductionDemand.DefenseAlert = { Active = false }
    economy.State.StallRisk = false
    economy.State.Mode = 'Opening'
    Check(production:DecideCommanderTasking() == 'opening-build', 'native gets commander first')
    WaitTicks(205)
    Check((acu.FixtureNativePolls or 0) > 0, 'commander handback really polls native')
    Check(production:DecideCommanderTasking() == 'assist', 'idle timeout selects fallback')
    WaitTicks(30)
    Check(production:DecideCommanderTasking() == 'assisting' and acu:GetGuardedUnit() == factory,
        'fallback survives next production pass')
    record = acu.RedQueenAssist
    local polls = acu.FixtureNativePolls
    WaitTicks(60)
    Check(acu.FixtureNativePolls == polls and acu:GetGuardedUnit() == factory,
        'native retry respects commander fallback')
    while GetGameTick() <= record.Until + 55 do WaitTicks(10) end
    Check(not acu:GetGuardedUnit() and acu.FixtureNativePolls > polls, 'commander expiry restores native work')
    Report('commander native-handback=true fallback-retained=true expired-and-resumed=true')

    local function UpgradePlatoon(mex)
        local platoon = brain:MakePlatoon('', '')
        brain:AssignUnitsToPlatoon(platoon, { mex }, 'Support', 'None')
        platoon.PlatoonData = {}
        ForkThread(function() platoon:UnitUpgradeAI() end)
    end
    local mex = Spawn('ueb1202', 35, 30)
    modules.Strategy.ProductionDemand.DefenseAlert = { Active = true }
    local before = brain.RedQueenExtractorBlocks or 0
    UpgradePlatoon(mex)
    WaitTicks(5)
    Check(not mex:IsUnitState('Upgrading') and (brain.RedQueenExtractorBlocks or 0) > before,
        'native must veto a new T3 extractor upgrade under attack')
    modules.Strategy.ProductionDemand.DefenseAlert = { Active = false }
    modules.Economy.State.StallRisk = false
    UpgradePlatoon(mex)
    WaitTicks(5)
    Check(mex:IsUnitState('Upgrading'), 'native upgrade resumes after alert clears')
    modules.Strategy.ProductionDemand.DefenseAlert = { Active = true }
    UpgradePlatoon(mex)
    WaitTicks(5)
    Check(mex:IsUnitState('Upgrading') and table.getn(mex:GetCommandQueue()) > 0,
        'existing native upgrade must survive the veto')
    Report('extractor native-veto=true recovery=true in-progress-preserved=true')
    Report('PASS all controlled native-order contracts satisfied')
end
