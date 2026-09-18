local Logger = import("/mods/TheRedQueen/lua/AI/RedQueen/Logger.lua")

---@class RedQueenObserver
-- What a spectator sees, written down once a minute.
--
-- Two rounds in front of the screen produced eight defects that no log could
-- have shown: a commander assisting a factory while the base browned out, a
-- first Tech 2 structure that was a missile launcher, a Tech 3 extractor
-- upgrade started while extractors still stood at Tech 1, a commander that
-- wandered out alone and died. Every one is a fact about inventory or about
-- what the commander is doing, and the state line carries neither.
--
-- Telemetry only. Enemy counts here are read straight off the opposing brains,
-- which is not knowledge Red Queen is entitled to act on -- nothing in this
-- module may ever be read by a decision, and no caller may keep what it
-- returns. It exists so a watcher can say "outgunned three to one" the way a
-- spectator can, and that is all.

local CombatUnits = categories.MOBILE
    - categories.ENGINEER
    - categories.COMMAND
    - categories.SCOUT
    - categories.TRANSPORTFOCUS

-- Ordered most specific first: a commander upgrading is also building, and one
-- assisting a factory reads as guarding while it moves between build sites.
-- The first match wins, so "assisting" cannot be lost to "moving".
local CommanderStates = {
    { "Upgrading", "upgrading" },
    { "Building", "building" },
    { "Repairing", "repairing" },
    { "Guarding", "assisting" },
    { "Attacking", "attacking" },
    { "Moving", "moving" },
}

local function Count(brain, category)
    if not brain or not brain.GetCurrentUnits then
        return 0
    end
    return brain:GetCurrentUnits(category) or 0
end

local function Tiers(brain, category)
    return Count(brain, category * categories.TECH1),
        Count(brain, category * categories.TECH2),
        Count(brain, category * categories.TECH3)
end

local function Distance(from, to)
    if not from or not to then
        return 0
    end
    local dx = (from[1] or 0) - (to[1] or 0)
    local dz = (from[3] or 0) - (to[3] or 0)
    return math.sqrt(dx * dx + dz * dz)
end

-- The commander, and how far from home it has gone.
--
-- Distance is the field that matters: the leash exists to stop the commander
-- walking into an army, and a match where it died doing exactly that reported
-- one recall the whole game. A number every minute says whether the leash is
-- failing to fire or firing and being ignored.
function CommanderFacts(brain, home)
    local facts = { State = "none", Distance = 0, Health = 0 }
    if not brain or not brain.GetListOfUnits or not categories or not categories.COMMAND then
        return facts
    end
    for _, commander in pairs(brain:GetListOfUnits(categories.COMMAND, false) or {}) do
        if commander and not commander.Dead then
            facts.State = "idle"
            for _, entry in ipairs(CommanderStates) do
                if commander.IsUnitState and commander:IsUnitState(entry[1]) then
                    facts.State = entry[2]
                    break
                end
            end
            if commander.GetPosition then
                facts.Distance = Distance(commander:GetPosition(), home)
            end
            if commander.GetHealth and commander.GetMaxHealth then
                local maximum = commander:GetMaxHealth() or 0
                if maximum > 0 then
                    facts.Health = 100 * (commander:GetHealth() or maximum) / maximum
                end
            end
            return facts
        end
    end
    -- No living commander at all is the single most important thing that can
    -- be said about a Red Queen army, and "none" would read as a missing field.
    facts.State = "dead"
    return facts
end

-- Engineers with nothing to do, which is the cheapest waste in the game and
-- was visible on screen minutes before any other symptom appeared.
function IdleEngineers(brain)
    if not brain or not brain.GetListOfUnits then
        return 0, 0
    end
    local engineers = brain:GetListOfUnits(
        categories.ENGINEER * categories.MOBILE - categories.COMMAND, false) or {}
    local idle = 0
    for _, engineer in pairs(engineers) do
        if engineer and not engineer.Dead
            and engineer.IsIdleState and engineer:IsIdleState()
        then
            idle = idle + 1
        end
    end
    return idle, table.getn(engineers)
end

function Collect(brain, modules)
    local world = modules.World or {}
    local economy = (modules.Economy or {}).State or {}
    local home = world.StartPosition
    local commander = CommanderFacts(brain, home)
    local idleEngineers, engineers = IdleEngineers(brain)

    local structure = categories.STRUCTURE
    local pd1, pd2, pd3 = Tiers(brain, structure * categories.DEFENSE * categories.DIRECTFIRE)
    local aa1, aa2, aa3 = Tiers(brain, structure * categories.DEFENSE * categories.ANTIAIR)
    local mex1, mex2, mex3 = Tiers(brain, structure * categories.MASSEXTRACTION)
    local own1, own2, own3 = Tiers(brain, CombatUnits)

    local enemy1, enemy2, enemy3, enemyExperimental = 0, 0, 0, 0
    local context = brain.RedQueenContext or {}
    for _, armyIndex in pairs(context.EnemyArmies or {}) do
        local enemyBrain = ArmyBrains and ArmyBrains[armyIndex]
        if enemyBrain then
            local one, two, three = Tiers(enemyBrain, CombatUnits)
            enemy1 = enemy1 + one
            enemy2 = enemy2 + two
            enemy3 = enemy3 + three
            enemyExperimental = enemyExperimental
                + Count(enemyBrain, CombatUnits * categories.EXPERIMENTAL)
        end
    end

    return {
        Time = economy.GameTimeSeconds or 0,
        Commander = commander,
        PointDefense = { pd1, pd2, pd3 },
        AntiAir = { aa1, aa2, aa3 },
        AntiMissile = Count(brain, structure * categories.DEFENSE * categories.ANTIMISSILE),
        Shields = Count(brain, structure * categories.SHIELD),
        MissileLaunchers = Count(brain, structure * categories.TACTICALMISSILEPLATFORM),
        Artillery = Count(brain, structure * categories.ARTILLERY),
        Extractors = { mex1, mex2, mex3 },
        IdleEngineers = idleEngineers,
        Engineers = engineers,
        Own = { own1, own2, own3, Count(brain, CombatUnits * categories.EXPERIMENTAL) },
        Enemy = { enemy1, enemy2, enemy3, enemyExperimental },
        MassStored = economy.MassStoredRatio or 0,
        EnergyStored = economy.EnergyStoredRatio or 0,
    }
end

function Format(facts)
    local commander = facts.Commander
    return string.format(
        "watch t=%d acu=%s/%.0f/%.0f def=pd%d/%d/%d,aa%d/%d/%d,tmd%d,sh%d,tml%d,arty%d"
            .. " mex=%d/%d/%d eng=%d/%d units=%d/%d/%d/%d enemy=%d/%d/%d/%d store=%.2f/%.2f",
        facts.Time,
        commander.State,
        commander.Distance,
        commander.Health,
        facts.PointDefense[1], facts.PointDefense[2], facts.PointDefense[3],
        facts.AntiAir[1], facts.AntiAir[2], facts.AntiAir[3],
        facts.AntiMissile,
        facts.Shields,
        facts.MissileLaunchers,
        facts.Artillery,
        facts.Extractors[1], facts.Extractors[2], facts.Extractors[3],
        facts.IdleEngineers,
        facts.Engineers,
        facts.Own[1], facts.Own[2], facts.Own[3], facts.Own[4],
        facts.Enemy[1], facts.Enemy[2], facts.Enemy[3], facts.Enemy[4],
        facts.MassStored,
        facts.EnergyStored
    )
end

function Report(brain, modules)
    Logger.Info(brain, Format(Collect(brain, modules)))
end
