local Logger = import("/mods/TheRedQueen/lua/AI/RedQueen/Logger.lua")

-- Observation only: no commands, enemy enumeration, random numbers or policy
-- inputs. Keep cumulative records by blueprint/controller, never by dead unit.
local Controllers = { "pool", "directed", "nativeLand", "nativeAir", "nativeNaval", "unassigned" }

local function Blueprint(unit)
    return unit and unit.GetBlueprint and unit:GetBlueprint() or {}
end

local function IsCombat(bp)
    local c = bp.CategoriesHash or {}
    return c.MOBILE and not (c.ENGINEER or c.COMMAND or c.SCOUT or c.TRANSPORTFOCUS)
end

local function Mass(bp)
    return (bp.Economy or {}).BuildCostMass or 0
end

function Controller(unit, pool)
    local platoon = unit.PlatoonHandle
    if not platoon then return "unassigned" end
    if platoon == pool then return "pool" end
    if platoon.RedQueenDirected then return "directed" end
    local c = Blueprint(unit).CategoriesHash or {}
    if c.AIR then return "nativeAir" end
    if c.NAVAL then return "nativeNaval" end
    return "nativeLand"
end

-- What a platoon was told to do, as the name its former set on it.
--
-- `PlatoonFormManager` writes `PlanName` (the template's plan, or the builder's
-- `GetPlatoonAIPlan()`) and `BuilderName` onto the handle, so this is the
-- native task without inferring anything. Controller alone said two thirds of
-- the dying mass was outside our directed plan; it could not say what the rest
-- was sent at.
local function PlanName(unit, pool)
    local platoon = unit.PlatoonHandle
    if not platoon then return "unassigned" end
    if platoon == pool then return "ArmyPool" end
    if platoon.RedQueenDirected then return "RedQueenDirected" end
    local name = platoon.PlanName or platoon.BuilderName
    if type(name) ~= "string" or name == "" then return "unknown" end
    return name
end

local function State(brain)
    if not brain.RedQueenCombatTelemetry then
        brain.RedQueenCombatTelemetry = {
            Blueprints = {}, Lost = {}, LostByPlan = {}, RepeatedDeaths = 0,
        }
    end
    return brain.RedQueenCombatTelemetry
end

function Record(brain, unit, event)
    local bp = Blueprint(unit)
    if not IsCombat(bp) then return end
    local state = State(brain)
    if event == "lost" then
        -- A falling aircraft can notify its brain more than once. Count the
        -- unit once, and expose repeats instead of inventing additional losses.
        if unit.RedQueenTelemetryDeath then
            state.RepeatedDeaths = state.RepeatedDeaths + 1
            return
        end
        unit.RedQueenTelemetryDeath = true
    elseif event == "built" then
        if unit.RedQueenTelemetryCompleted then return end
        unit.RedQueenTelemetryCompleted = true
    end
    local id = bp.BlueprintId or unit.UnitId or "unknown"
    local record = state.Blueprints[id] or { Built = 0, Lost = 0, Mass = Mass(bp) }
    state.Blueprints[id] = record
    if event == "built" then
        record.Built = record.Built + 1
    elseif event == "lost" then
        record.Lost = record.Lost + 1
        local pool = brain:GetPlatoonUniquelyNamed("ArmyPool")
        local controller = Controller(unit, pool)
        state.Lost[controller] = (state.Lost[controller] or 0) + Mass(bp)
        -- PlatoonHandle still holds here: native Unit:OnKilled notifies the
        -- brain before anything clears it, and PlatoonDisband clears it later.
        local plan = PlanName(unit, pool)
        local record = state.LostByPlan[plan] or { Mass = 0, Count = 0 }
        state.LostByPlan[plan] = record
        record.Mass = record.Mass + Mass(bp)
        record.Count = record.Count + 1
    end
end

-- How close counts as arrived.
--
-- A measurement threshold, not a policy knob: nothing reads it to decide
-- anything. Matched to the radius the directed-platoon detail already uses for
-- "at its target", so the two figures mean the same thing.
local ArrivalRadius = 35

-- Half the side of the box concentration is measured in.
--
-- Units within this of each other are in one fight: past a Tech 3 direct-fire
-- range, short of a separate engagement. A measurement constant, not a policy
-- knob -- nothing reads it to decide anything.
local ConcentrationRadius = 50

local function Distance(a, b)
    if not a or not b then return -1 end
    local x, z = a[1] - b[1], a[3] - b[3]
    return math.sqrt(x * x + z * z)
end

local function SortedKeys(values)
    local keys = {}
    for key in pairs(values) do table.insert(keys, key) end
    table.sort(keys)
    return keys
end

function Collect(brain)
    local state = State(brain)
    local pool = brain:GetPlatoonUniquelyNamed("ArmyPool")
    local result = { Controllers = {}, Platoons = {}, Factories = {}, Inventory = {},
        Plans = {}, Sent = {}, Cells = {}, CombatMass = 0, Unkeyed = 0 }
    for _, name in ipairs(Controllers) do
        result.Controllers[name] = { Count = 0, Mass = 0, Idle = 0, Lost = state.Lost[name] or 0 }
    end
    local units = brain:GetListOfUnits(categories.ALLUNITS, false) or {}
    for _, unit in pairs(units) do
        if unit and not unit.Dead then
            local bp = Blueprint(unit)
            local c = bp.CategoriesHash or {}
            if IsCombat(bp) then
                local name = Controller(unit, pool)
                local bucket = result.Controllers[name]
                bucket.Count = bucket.Count + 1
                bucket.Mass = bucket.Mass + Mass(bp)
                local idle = unit.IsIdleState and unit:IsIdleState()
                if idle then bucket.Idle = bucket.Idle + 1 end
                local id = bp.BlueprintId or unit.UnitId or "unknown"
                result.Inventory[id] = (result.Inventory[id] or 0) + 1
                -- Grid-bucket for concentration. Cheap and deterministic:
                -- O(n) here, then a bounded pass over occupied cells below.
                -- Iterating every unit against every other would be O(n^2) on
                -- an army of hundreds, once a game minute.
                if unit.GetPosition then
                    local at = unit:GetPosition()
                    if at then
                        local bx = math.floor(at[1] / ConcentrationRadius)
                        local bz = math.floor(at[3] / ConcentrationRadius)
                        local key = tostring(bx) .. ":" .. tostring(bz)
                        local cell = result.Cells[key]
                        if not cell then
                            cell = { X = bx, Z = bz, Mass = 0 }
                            result.Cells[key] = cell
                        end
                        cell.Mass = cell.Mass + Mass(bp)
                        result.CombatMass = result.CombatMass + Mass(bp)
                    end
                end
                local plan = PlanName(unit, pool)
                local living = result.Plans[plan] or { Mass = 0, Count = 0 }
                result.Plans[plan] = living
                living.Mass = living.Mass + Mass(bp)
                living.Count = living.Count + 1
                -- Ordered somewhere, and whether it is there yet. A claim is
                -- not protection: the secondary slot could report the force it
                -- took but never whether any of it reached the thing it was
                -- taken to defend.
                if unit.RedQueenSentTo and unit.GetPosition then
                    local kind = unit.RedQueenSentKind or "unknown"
                    local sent = result.Sent[kind]
                    if not sent then
                        sent = { Count = 0, Mass = 0, Arrived = 0, ArrivedMass = 0 }
                        result.Sent[kind] = sent
                    end
                    sent.Count = sent.Count + 1
                    sent.Mass = sent.Mass + Mass(bp)
                    local travelled = Distance(unit:GetPosition(), unit.RedQueenSentTo)
                    if travelled >= 0 and travelled <= ArrivalRadius then
                        sent.Arrived = sent.Arrived + 1
                        sent.ArrivedMass = sent.ArrivedMass + Mass(bp)
                    end
                end
                if name == "directed" then
                    local platoon = unit.PlatoonHandle
                    local key = platoon.RedQueenDirectedId
                    -- A directed platoon with no id cannot be a table key, and
                    -- `result.Platoons[nil] = group` raises "table index is
                    -- nil" -- which would kill the whole diagnostics pass every
                    -- game minute, the way a constructor probing MapSize once
                    -- killed the brain outright. ObjectiveAttack sets the id
                    -- and the flag together, so this is unreachable today; it
                    -- is one refactor away from not being, and an observer must
                    -- never be able to take the brain down. Counted and
                    -- disclosed rather than dropped silently.
                    if key == nil then
                        result.Unkeyed = result.Unkeyed + 1
                    else
                        local group = result.Platoons[key]
                        if not group then
                            group = { Platoon = platoon, Count = 0, Mass = 0, Idle = 0 }
                            result.Platoons[key] = group
                        end
                        group.Count = group.Count + 1
                        group.Mass = group.Mass + Mass(bp)
                        if idle then group.Idle = group.Idle + 1 end
                    end
                end
            elseif c.FACTORY and (c.LAND or c.AIR or c.NAVAL) then
                local domain = c.AIR and "A" or c.NAVAL and "N" or "L"
                local tier = c.TECH3 and 3 or c.TECH2 and 2 or 1
                local key = domain .. tostring(tier)
                local factory = result.Factories[key] or { Ready = 0, Building = 0, Upgrading = 0, Idle = 0 }
                result.Factories[key] = factory
                if not unit.GetFractionComplete or unit:GetFractionComplete() >= 1 then
                    factory.Ready = factory.Ready + 1
                    if unit:IsUnitState("Upgrading") then
                        factory.Upgrading = factory.Upgrading + 1
                    elseif unit:IsUnitState("Building") then
                        factory.Building = factory.Building + 1
                    elseif unit.IsIdleState and unit:IsIdleState() then
                        factory.Idle = factory.Idle + 1
                    end
                end
            end
        end
    end
    -- The heaviest own combat mass inside any axis-aligned box of side
    -- 2 * ConcentrationRadius, taken as the best 2x2 block of cells. An
    -- approximation of "one fight", stated as one: it does not find the true
    -- optimal circle, and it never overstates, because every unit it counts is
    -- genuinely inside that box.
    local best, occupied = 0, 0
    for _, cell in pairs(result.Cells) do
        occupied = occupied + 1
        local block = 0
        for dx = 0, 1 do
            for dz = 0, 1 do
                local neighbour = result.Cells[tostring(cell.X + dx) .. ":" .. tostring(cell.Z + dz)]
                if neighbour then block = block + neighbour.Mass end
            end
        end
        if block > best then best = block end
    end
    result.Concentration = best
    result.OccupiedCells = occupied
    return result
end

function Report(brain, modules)
    local facts = Collect(brain)
    local state = State(brain)
    local tick = GetGameTick()
    local summary = {}
    for _, name in ipairs(Controllers) do
        local c = facts.Controllers[name]
        table.insert(summary, string.format("%s:%d/%.0f/%d/%.0f", name, c.Count, c.Mass, c.Idle, c.Lost))
    end
    local factories = {}
    for _, key in ipairs(SortedKeys(facts.Factories)) do
        local f = facts.Factories[key]
        table.insert(factories, string.format("%s:%d/%d/%d/%d", key, f.Ready, f.Building, f.Upgrading, f.Idle))
    end
    -- Full blueprint totals stay small (one entry per unit type); do not retain
    -- individual completions. Output/loss callbacks are not net transfers or
    -- reclaim, so they must not be presented as an exact inventory equation.
    local blueprints = {}
    local ids = {}
    for id in pairs(state.Blueprints) do ids[id] = true end
    for id in pairs(facts.Inventory) do ids[id] = true end
    for _, id in ipairs(SortedKeys(ids)) do
        local b = state.Blueprints[id] or { Built = 0, Lost = 0 }
        table.insert(blueprints, string.format("%s:%d/%d/%d", id, b.Built, b.Lost, facts.Inventory[id] or 0))
    end
    Logger.Info(brain, string.format("combat-production t=%.0f factories=%s units=%s",
        tick / 10, table.concat(factories, ","), table.concat(blueprints, ",")))

    -- What each task is holding and what it has lost, worst loss first.
    --
    -- Bounded to the twelve heaviest losers and the total disclosed, because
    -- the number of distinct native plans is not ours to bound.
    local planNames = {}
    for name in pairs(state.LostByPlan) do planNames[name] = true end
    for name in pairs(facts.Plans) do planNames[name] = true end
    local ordered = SortedKeys(planNames)
    table.sort(ordered, function(a, b)
        local am = (state.LostByPlan[a] or {}).Mass or 0
        local bm = (state.LostByPlan[b] or {}).Mass or 0
        if am ~= bm then return am > bm end
        return a < b
    end)
    local plans = {}
    for index = 1, math.min(12, table.getn(ordered)) do
        local name = ordered[index]
        local lost = state.LostByPlan[name] or { Mass = 0, Count = 0 }
        local living = facts.Plans[name] or { Mass = 0, Count = 0 }
        table.insert(plans, string.format("%s:%d/%.0f/%d/%.0f",
            name, living.Count, living.Mass, lost.Count, lost.Mass))
    end
    Logger.Info(brain, string.format("combat-plans t=%.0f shown=%d/%d plans=%s",
        tick / 10, math.min(12, table.getn(ordered)), table.getn(ordered),
        table.concat(plans, ",")))

    -- The defensive chain end to end: what was required, what there was to
    -- draw on, what was taken, and what is actually standing there.
    --
    -- The secondary slot already reported required against claimed. Claimed is
    -- an order, not protection -- so the shortfall could never be told apart
    -- from force that was taken and never got there, nor from a reserve that
    -- was never large enough to claim from in the first place.
    local combat = modules.Combat or {}
    local required = combat.SecondaryRequiredThreat or 0
    local claimed = combat.SecondaryClaimedThreat or 0
    local available = combat.SecondaryAvailableThreat or 0
    local enRoute, arrived, arrivedMass = 0, 0, 0
    local kinds = {}
    for _, kind in ipairs({ "Defend", "Support", "Reinforce", "Investigate" }) do
        local sent = facts.Sent[kind]
        if sent then
            enRoute = enRoute + sent.Count
            arrived = arrived + sent.Arrived
            arrivedMass = arrivedMass + sent.ArrivedMass
            table.insert(kinds, string.format("%s:%d/%d/%.0f/%.0f",
                kind, sent.Count, sent.Arrived, sent.Mass, sent.ArrivedMass))
        end
    end
    Logger.Info(brain, string.format(
        "combat-defence t=%.0f required=%.0f available=%.0f claimed=%.0f deficit=%.0f sent=%d arrived=%d arrivedmass=%.0f kinds=%s",
        tick / 10, required, available, claimed, math.max(0, required - claimed),
        enRoute, arrived, arrivedMass, table.concat(kinds, ",")))

    local keys = SortedKeys(facts.Platoons)
    -- Twelve detail lines per minute maximum; always disclose omitted groups.
    for index = 1, math.min(12, table.getn(keys)) do
        local id = keys[index]
        local group = facts.Platoons[id]
        local platoon = group.Platoon
        local position = platoon:GetPlatoonPosition()
        local target = platoon.RedQueenDirectionPosition
        local strategy, intel = modules.Strategy, modules.Intel
        local enemy = position and intel and intel.GetThreatNear and intel:GetThreatNear(position, 35) or 0
        local support = position and strategy and strategy.GetOwnThreatNear
            and strategy:GetOwnThreatNear(position, 35) or 0
        Logger.Info(brain, string.format(
            "combat-platoon t=%.0f id=%d age=%.0f units=%d mass=%.0f idle=%d pos=%.0f,%.0f target=%.0f,%.0f distance=%.0f observed=%.1f support=%.1f",
            tick / 10, id,
            -- -1 for an unknown birth tick, the same sentinel a missing
            -- position uses, rather than arithmetic on nil.
            platoon.RedQueenDirectionBorn and (tick - platoon.RedQueenDirectionBorn) / 10 or -1,
            group.Count, group.Mass, group.Idle,
            position and position[1] or -1, position and position[3] or -1,
            target and target[1] or -1, target and target[3] or -1,
            Distance(position, target), enemy, support))
    end
    return " combatctl=" .. table.concat(summary, ",")
        .. " combatdetail=" .. tostring(math.min(12, table.getn(keys))) .. "/" .. tostring(table.getn(keys))
        .. " combatconc=" .. string.format("%.0f/%.0f/%d",
            facts.Concentration or 0, facts.CombatMass or 0, facts.OccupiedCells or 0)
        .. " combatdefence=" .. string.format("%.0f/%.0f/%.0f/%d/%d",
            required, available, claimed, enRoute, arrived)
        .. " combatunkeyed=" .. tostring(facts.Unkeyed)
        .. " combatdeathrepeats=" .. tostring(state.RepeatedDeaths)
end
