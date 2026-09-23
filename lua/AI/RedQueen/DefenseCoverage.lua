-- Does a defence cover the ground that is being attacked?
--
-- `FortificationBuilders.NeedsDefense` satisfies a tier's need with any allied
-- structure of that tier anywhere inside the base manager's radius, and
-- construction places it with `BuildClose` at the base. Neither step knows which
-- approach the enemy is using. Observed directly while spectating: the point
-- defences and anti-air that did get built sat where they could not reach the
-- fighting, and only came into range once the enemy had reached the factories
-- and shields they happened to be standing next to.
--
-- Gun count therefore cannot say whether the army is defended. What can is
-- whether a gun can *shoot* the place under attack, and whether anything could
-- shoot the extractor that just died. Both are measured here, and neither
-- changes a decision: this module is read by Diagnostics only.
local Constants = import("/mods/TheRedQueen/lua/AI/RedQueen/Constants.lua")

local function Alive(unit)
    return unit and not unit.Dead
        and (not unit.BeenDestroyed or not unit:BeenDestroyed())
end

local function DistanceSquared(a, b)
    if not a or not b then
        return nil
    end
    local dx = a[1] - b[1]
    local dz = a[3] - b[3]
    return dx * dx + dz * dz
end

-- Reach of the longest weapon on a structure, cached per blueprint.
--
-- A structure with no weapon -- a shield, a radar, a wall -- has a reach of
-- zero and can never cover anything, which is the point: it still satisfies a
-- base-wide count of "structures near the base" while covering nothing.
local RangeCache = {}
function WeaponRange(unit)
    if not unit or not unit.GetBlueprint then
        return 0
    end
    local blueprint = unit:GetBlueprint()
    if not blueprint then
        return 0
    end
    local identifier = blueprint.BlueprintId
    if identifier and RangeCache[identifier] then
        return RangeCache[identifier]
    end
    local best = 0
    for _, weapon in pairs(blueprint.Weapon or {}) do
        local radius = weapon.MaxRadius or 0
        if radius > best then
            best = radius
        end
    end
    if identifier then
        RangeCache[identifier] = best
    end
    return best
end

function Covers(unit, position)
    local range = WeaponRange(unit)
    if range <= 0 or not unit.GetPosition or not position then
        return false
    end
    local distance = DistanceSquared(unit:GetPosition(), position)
    return distance ~= nil and distance <= range * range
end

local function DefenceStructures(brain)
    if not brain or not brain.GetListOfUnits or not categories then
        return {}
    end
    return brain:GetListOfUnits(
        categories.STRUCTURE * categories.DEFENSE, false) or {}
end

-- Defences held, defences that can reach the alert, and how far the nearest one
-- is from it. The third figure is what separates "too few guns" from "guns in
-- the wrong place": a base with ten defences whose nearest is 200 away from the
-- fighting is not short of defences.
function Summarise(brain, alert)
    local summary = { Total = 0, Covering = 0, Nearest = 0 }
    local anchor = alert and alert.Active and alert.AnchorPosition
    local nearest = nil
    local units = DefenceStructures(brain)
    for _, unit in pairs(units) do
        if Alive(unit) then
            summary.Total = summary.Total + 1
            if anchor then
                if Covers(unit, anchor) then
                    summary.Covering = summary.Covering + 1
                end
                local distance = unit.GetPosition
                    and DistanceSquared(unit:GetPosition(), anchor)
                if distance and (not nearest or distance < nearest) then
                    nearest = distance
                end
            end
        end
    end
    if nearest then
        summary.Nearest = math.sqrt(nearest)
    end
    return summary
end

-- An extractor died. Could anything have shot whatever killed it?
--
-- Counted at the loss rather than sampled, because an extractor that is gone
-- cannot be asked later what was covering it.
function RecordExtractorLoss(brain, position)
    if not brain then
        return
    end
    brain.RedQueenExtractorLosses = brain.RedQueenExtractorLosses
        or { Lost = 0, Defended = 0 }
    local record = brain.RedQueenExtractorLosses
    record.Lost = record.Lost + 1
    if not position then
        return
    end
    local units = DefenceStructures(brain)
    for _, unit in pairs(units) do
        if Alive(unit) and Covers(unit, position) then
            record.Defended = record.Defended + 1
            return
        end
    end
end

function LossSummary(brain)
    return (brain and brain.RedQueenExtractorLosses)
        or { Lost = 0, Defended = 0 }
end

-- How much of what the army holds is even eligible for a defence.
--
-- `FortificationBuilders.GetLocation` resolves only for a registered base
-- manager, and refuses the job outright when the alert is anchored outside its
-- radius. Ground beyond every base is therefore not under-defended -- no
-- fortification builder can be offered it at all.
function BaseSpan(brain)
    local span = { Bases = 0, Inside = 0, Outside = 0 }
    if not brain or not brain.GetListOfUnits or not categories then
        return span
    end
    local spots = {}
    for _, manager in pairs(brain.BuilderManagers or {}) do
        local engineerManager = manager and manager.EngineerManager
        if engineerManager and engineerManager.GetLocationCoords then
            local resolved, coords = pcall(
                engineerManager.GetLocationCoords, engineerManager)
            if resolved and coords then
                span.Bases = span.Bases + 1
                table.insert(spots, {
                    Position = coords,
                    Radius = math.max(
                        Constants.Policy.FortificationMinimumRadius,
                        engineerManager.Radius or 100
                    ),
                })
            end
        end
    end
    local extractors = brain:GetListOfUnits(
        categories.STRUCTURE * categories.MASSEXTRACTION, false) or {}
    for _, extractor in pairs(extractors) do
        if Alive(extractor) and extractor.GetPosition then
            local position = extractor:GetPosition()
            local covered = false
            for _, spot in pairs(spots) do
                local distance = DistanceSquared(position, spot.Position)
                if distance and distance <= spot.Radius * spot.Radius then
                    covered = true
                end
            end
            if covered then
                span.Inside = span.Inside + 1
            else
                span.Outside = span.Outside + 1
            end
        end
    end
    return span
end
