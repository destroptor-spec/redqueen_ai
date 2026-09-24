-- Opt-in construction fixture. Loaded only by verify-storage-placement.py.
-- Uses the command-line launch's civilian human army, which has no AI builder
-- loop. Real units, placement, build orders, adjacency and income stay native.
local function Check(value, message)
    if not value then
        LOG('[RQStorageFixture] FAIL ' .. message)
        error(message)
    end
end

local function Report(message)
    LOG('[RQStorageFixture] ' .. message)
end

local function Close(a, b, tolerance)
    return math.abs(a - b) <= tolerance
end

-- Finds a site whose adjacency ring is clear, plus somewhere to park the
-- fixture's own equipment.
--
-- The ring is the thing under test and must be genuinely buildable. The
-- buffers and power are spawned with CreateUnitHPR rather than built, so they
-- only need valid ground away from the ring -- tying them to a fixed +20/+24
-- offset refused 43 of 49 candidate sites on Sentry Point and the fixture
-- never reached its first case.
local RING = { { 0, 0 }, { 0, -2 }, { 0, 2 }, { 2, 0 }, { -2, 0 } }
local AUX = { { 20, 0 }, { -20, 0 }, { 0, 20 }, { 0, -20 }, { 20, 20 }, { -20, -20 } }

local function RingClear(brain, prefix, x, z)
    for _, offset in ipairs(RING) do
        if not brain:CanBuildStructureAt(prefix .. '1106', { x + offset[1], 0, z + offset[2] }) then
            return false
        end
    end
    return true
end

local function FindSite(brain, startX, startZ, prefix)
    local sx = startX < ScenarioInfo.size[1] / 2 and 1 or -1
    local sz = startZ < ScenarioInfo.size[2] / 2 and 1 or -1
    local tried, ringFailed, auxFailed = 0, 0, 0
    for dx = 16, 64, 8 do
        for dz = 16, 64, 8 do
            local x = math.floor(startX) + 0.5 + sx * dx
            local z = math.floor(startZ) + 0.5 + sz * dz
            tried = tried + 1
            if not RingClear(brain, prefix, x, z) then
                ringFailed = ringFailed + 1
            else
                for _, aux in ipairs(AUX) do
                    local ax, az = x + aux[1], z + aux[2]
                    if brain:CanBuildStructureAt(prefix .. '1106', { ax, 0, az })
                        and brain:CanBuildStructureAt(prefix .. '1105', { ax + 4, 0, az })
                        and brain:CanBuildStructureAt(prefix .. '1301', { ax, 0, az + 8 })
                    then
                        return x, z, ax, az
                    end
                end
                auxFailed = auxFailed + 1
            end
        end
    end
    return nil, string.format('tried=%d ring-blocked=%d aux-blocked=%d',
        tried, ringFailed, auxFailed)
end

local Survival = import('/mods/TheRedQueen/lua/AI/RedQueen/EngineerSurvival.lua')

function Run()
    WaitTicks(150)
    Check(ArmyBrains[2] and ArmyBrains[2].RedQueenStarted, 'control Red Queen must initialize')
    local brain = ArmyBrains[1]
    local setup = brain and ScenarioInfo.ArmySetup[brain.Name]
    Check(brain and setup and setup.Human and setup.Civilian,
        'fixture must own the isolated launcher civilian slot')
    local native = import('/lua/AI/aibuildstructures.lua')
    -- Apply exactly the candidate hook to its defining native environment.
    -- It is deliberately not installed in the active mod's hook directory.
    doscript('/lua/rq-storage-hook.lua', native)
    local candidate = import('/mods/TheRedQueen/lua/AI/RedQueen/MassStorage.lua')
    Report('START native construction cases=8 control-mod=true fixture-army=' .. tostring(brain:GetArmyIndex()))
    local startX, startZ = brain:GetArmyStartPos()
    -- Diagnostic: the first run failed at site search with nothing to say why.
    -- A civilian slot may have no start marker, or may not be allowed to build
    -- at all, and those need different fixes.
    Report(string.format('SITE-CONTEXT start=%s,%s map=%sx%s canbuild-here=%s canbuild-mid=%s',
        tostring(startX), tostring(startZ),
        tostring(ScenarioInfo.size[1]), tostring(ScenarioInfo.size[2]),
        tostring(brain:CanBuildStructureAt('ueb1106', { (startX or 0) + 16.5, 0, (startZ or 0) + 16.5 })),
        tostring(brain:CanBuildStructureAt('ueb1106',
            { ScenarioInfo.size[1] / 2 + 0.5, 0, ScenarioInfo.size[2] / 2 + 0.5 }))))
    local originalModules, originalMarker = brain.RedQueenModules, brain.RedQueenLobbyPersonality
    local originalManagers = brain.BuilderManagers
    local originalLowEnergy = brain.LowEnergyMode
    brain.RedQueenLobbyPersonality = 'storage-fixture'
    brain.LowEnergyMode = false
    brain.RedQueenModules = { Economy = { State = { StallRisk = false } },
        Strategy = { ProductionDemand = {} } }
    brain.BuilderManagers = brain.BuilderManagers or {}
    Check(not brain.BuilderManagers.RQ_STORAGE_FIXTURE, 'fixture base must be unused')
    local cases = 0
    for _, prefix in ipairs({ 'ueb', 'uab', 'urb', 'xsb' }) do
        for _, tier in ipairs({ '1202', '1302' }) do
            local x, z, auxX, auxZ = FindSite(brain, startX, startZ, prefix)
            Check(x, 'no clear fixture site for ' .. prefix .. tier .. ' ' .. tostring(z))
            local created = {}
            local function Spawn(id, px, pz)
                local unit = CreateUnitHPR(id, brain:GetArmyIndex(), px, GetSurfaceHeight(px, pz), pz, 0, 0, 0)
                Check(unit and not unit.Dead, 'spawn ' .. id)
                table.insert(created, unit)
                return unit
            end
            -- Buffers fund the order, away from the extractor. They are spawned
            -- fixture equipment, not output attributed to the candidate.
            Spawn(prefix .. '1106', auxX, auxZ)
            Spawn(prefix .. '1105', auxX + 4, auxZ)
            Spawn(prefix .. '1301', auxX, auxZ + 8)
            local engineerId = string.sub(prefix, 1, 2) .. 'l0309'
            local engineer = Spawn(engineerId, x + 6, z + 6)
            local manager = { GetLocationCoords = function() return { x, 0, z } end }
            brain.BuilderManagers.RQ_STORAGE_FIXTURE = {
                EngineerManager = manager, FactoryManager = {}, PlatoonFormManager = {},
            }
            local platoon = brain:MakePlatoon('', '')
            brain:AssignUnitsToPlatoon(platoon, { engineer }, 'Support', 'None')
            platoon.PlatoonData = { Construction = { RedQueenStrictMassStorage = true } }
            engineer.BuilderManagerData = { EngineerManager = manager, LocationType = 'RQ_STORAGE_FIXTURE' }
            IssueClearCommands({ engineer })
            brain:GiveResource('MASS', 5000)
            brain:GiveResource('ENERGY', 50000)
            WaitTicks(80)
            local emptyIncome = brain:GetEconomyIncome('MASS')
            local mex = Spawn(prefix .. tier, x, z)
            WaitTicks(80)
            Check(mex:GetFractionComplete() == 1, 'extractor setup must be complete')
            local incomeBefore = brain:GetEconomyIncome('MASS')
            local baseIncome = incomeBefore - emptyIncome
            Check(baseIncome > 0, 'extractor must contribute measured income before storage')
            Check(Close(mex.MassProdAdjMod or 1, 1, 0.0001), 'extractor must start without a production buff')
            local existing = {}
            local storages = brain:GetListOfUnits(categories.MASSSTORAGE * categories.STRUCTURE, false)
            for _, unit in pairs(storages) do existing[unit:GetEntityId()] = true end
            Report('BUILD blueprint=' .. prefix .. tier)
            -- Which of the candidate's five engineer preconditions is false.
            -- "engineer-unavailable" is one reason covering all of them, and
            -- Seraphim Tech 2 refused here while passing on Sentry Point.
            Report(string.format(
                'ENG-STATE id=%s dead=%s army=%s/%s manager-match=%s platoon=%s retreating=%s queue=%d',
                tostring(engineerId), tostring(engineer.Dead),
                tostring(engineer:GetArmy()), tostring(brain:GetArmyIndex()),
                tostring(engineer.BuilderManagerData
                    and engineer.BuilderManagerData.EngineerManager == manager),
                tostring(brain:PlatoonExists(platoon)),
                tostring(Survival and Survival.IsRetreating and Survival.IsRetreating(engineer)),
                table.getn(engineer.EngineerBuildQueue or {})))
            local accepted = native.AIBuildAdjacency(brain, engineer, 'MassStorage', false, false,
                { { 'MassStorage', prefix .. '1106' } }, {}, { mex }, nil)
            -- Report the candidate's own counters before asserting, or a
            -- refusal aborts the case with no reason recorded. Seraphim Tech 2
            -- passed on Sentry Point and refused on Fields of Isis, so the
            -- reason is what distinguishes a site problem from a geometry one.
            Report(candidate.Report(brain))
            Check(accepted, 'candidate must queue storage at a free edge for ' .. prefix .. tier)
            local entry = engineer.EngineerBuildQueue and engineer.EngineerBuildQueue[1]
            Check(entry and entry[3] == false, 'native queue must hold absolute coordinates')
            local storage
            local deadline = GetGameTick() + 1200
            while GetGameTick() < deadline and not storage do
                Check(not engineer.Dead and not mex.Dead, 'fixture builder and target must survive')
                brain:GiveResource('MASS', 5000)
                brain:GiveResource('ENERGY', 50000)
                local units = brain:GetListOfUnits(categories.MASSSTORAGE * categories.STRUCTURE, false)
                for _, unit in pairs(units) do
                    if not unit.Dead and not existing[unit:GetEntityId()] and unit:GetFractionComplete() == 1 then
                        Check(not storage, 'one order must complete exactly one new storage')
                        storage = unit
                    end
                end
                WaitTicks(10)
            end
            Check(storage, 'construction deadline expired for ' .. prefix .. tier)
            table.insert(created, storage)
            WaitTicks(80)
            local p, target = storage:GetPosition(), mex:GetPosition()
            local sp, mp = storage:GetBlueprint().Physics, mex:GetBlueprint().Physics
            Check(sp.SkirtOffsetX == mp.SkirtOffsetX and sp.SkirtOffsetZ == mp.SkirtOffsetZ,
                'fixture geometry requires the verified equal offsets')
            local dx, dz = math.abs(p[1] - target[1]), math.abs(p[3] - target[3])
            local width, depth = (sp.SkirtSizeX + mp.SkirtSizeX) / 2, (sp.SkirtSizeZ + mp.SkirtSizeZ) / 2
            Check((Close(dx, width, 0.01) and dz < depth) or (Close(dz, depth, 0.01) and dx < width),
                'completed storage does not touch the extractor skirt')
            Check(Close(p[1], entry[2][1], 0.01) and Close(p[3], entry[2][2], 0.01),
                'completed position differs from queued position')
            Check(storage.AdjacentUnits and storage.AdjacentUnits[mex:GetEntityId()] == mex
                and mex.AdjacentUnits and mex.AdjacentUnits[storage:GetEntityId()] == storage,
                'engine must register adjacency in both directions')
            Check(Close(mex.MassProdAdjMod or 1, 1.125, 0.0001), 'native production multiplier must be 1.125')
            local delta = brain:GetEconomyIncome('MASS') - incomeBefore
            -- Ratios avoid assuming whether this engine reports per tick or
            -- per second. Other civilian income is unchanged during each case.
            Check(Close(delta / baseIncome, 0.125, 0.01), 'measured income gain must be 12.5 percent')
            Report(string.format('CASE blueprint=%s queued=%.1f,%.1f actual=%.1f,%.1f mex=%.1f,%.1f skirt=%.0fx%.0f adjacent=true multiplier=%.3f income-base=%.4f income-gain=%.4f',
                prefix .. tier, entry[2][1], entry[2][2], p[1], p[3], target[1], target[3],
                mp.SkirtSizeX, mp.SkirtSizeZ, mex.MassProdAdjMod, baseIncome, delta))
            Report(candidate.Report(brain))
            storage:Destroy()
            WaitTicks(80)
            Check(Close(mex.MassProdAdjMod or 1, 1, 0.0001), 'removing storage must remove its buff')
            Check(Close(brain:GetEconomyIncome('MASS'), incomeBefore, baseIncome * 0.01),
                'removing storage must restore measured income')
            for _, unit in ipairs(created) do if not unit.Dead then unit:Destroy() end end
            brain:DisbandPlatoon(platoon)
            brain.BuilderManagers.RQ_STORAGE_FIXTURE = nil
            WaitTicks(20)
            cases = cases + 1
        end
    end
    brain.RedQueenModules, brain.RedQueenLobbyPersonality = originalModules, originalMarker
    brain.BuilderManagers = originalManagers
    brain.LowEnergyMode = originalLowEnergy
    Report('PASS cases=' .. tostring(cases) .. ' completed-position adjacency income and removal verified')
end
