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
function SummariseDefences(defences, alert)
    local summary = { Total = 0, Covering = 0, Nearest = 0 }
    local anchor = alert and alert.Active and alert.AnchorPosition
    local nearest = nil
    for _, unit in pairs(defences or {}) do
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

function Summarise(brain, alert)
    return SummariseDefences(DefenceStructures(brain), alert)
end

-- An extractor died. Records the position and nothing else.
--
-- Deliberately pure: this runs on the unit-destruction path, and the first
-- version asked the brain for its defence structures here. That version
-- perturbed the simulation -- seventeen cells of eighteen reproduced the
-- baseline and one diverged at sample 33, reproducibly. A measurement that
-- changes the match it is measuring is worthless, so the question of what
-- covered this position is answered later, from the defence list the state
-- line already fetches.
function RecordExtractorLoss(brain, position)
    if not brain then
        return
    end
    brain.RedQueenExtractorLosses = brain.RedQueenExtractorLosses
        or { Lost = 0, Defended = 0, Pending = {} }
    local record = brain.RedQueenExtractorLosses
    record.Lost = record.Lost + 1
    if position then
        record.Pending = record.Pending or {}
        table.insert(record.Pending, { position[1], position[2], position[3] })
    end
end

-- Answer the pending losses against the defences that exist now.
--
-- The defence set moves slowly compared with the sampling interval, so asking
-- one state line later is the same question; asking it on the destruction path
-- was not the same match.
local function ResolvePending(brain, defences)
    local record = brain and brain.RedQueenExtractorLosses
    local pending = record and record.Pending
    if not pending then
        return
    end
    for index = table.getn(pending), 1, -1 do
        local position = pending[index]
        local covered = false
        for _, unit in pairs(defences) do
            if Alive(unit) and Covers(unit, position) then
                covered = true
            end
        end
        if covered then
            record.Defended = record.Defended + 1
        end
        table.remove(pending, index)
    end
end

function LossSummary(brain)
    return (brain and brain.RedQueenExtractorLosses)
        or { Lost = 0, Defended = 0 }
end

-- How much of the map could ever receive a defence.
--
-- `FortificationBuilders.GetLocation` resolves only for a registered base
-- manager and refuses the job outright when the alert is anchored outside its
-- radius. Deposits beyond every base are therefore not under-defended -- no
-- fortification builder can be offered them at all.
--
-- Measured against the map's own mass markers rather than the extractors
-- currently standing on them. Two reasons, one of them the hard-won one:
--
--  * it is the base placement that is being judged, and a count of surviving
--    extractors moves with the very losses this is meant to explain;
--  * the first version asked the brain for its extractors, and
--    `GetListOfUnits(STRUCTURE * MASSEXTRACTION)` perturbs the simulation.
--    Bisected against one cell over five matches: with every query removed the
--    match reproduced the baseline 74/74, with the defence query alone 74/74,
--    with the manager walk alone 74/74, and with the extractor query 68 samples
--    diverging at 32 -- reproducibly, and identically on a re-run. The same
--    call for `STRUCTURE * DEFENSE` is clean, so it is not the call but the
--    units it asks for. The mechanism is not understood; it is avoided.
--
-- The markers are read once when the world model is built, so this costs no
-- engine query at all.
function BaseSpan(brain, world)
    local span = { Bases = 0, Inside = 0, Outside = 0 }
    if not brain then
        return span
    end
    local spots = {}
    for _, manager in pairs(brain.BuilderManagers or {}) do
        local engineerManager = manager and manager.EngineerManager
        if engineerManager and engineerManager.GetLocationCoords then
            -- Called directly: BuilderManager:GetLocationCoords is
            -- `return self.Location` and cannot raise.
            local coords = engineerManager:GetLocationCoords()
            if coords then
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
    local clusters = world and world.MassClusters
    if not clusters then
        return span
    end
    for _, cluster in pairs(clusters) do
        for _, marker in pairs(cluster.Markers or {}) do
            local position = marker.Position or marker.position
            if position then
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
    end
    return span
end

-- Everything the state line needs, from one pass over each list.
--
-- Diagnostics calls this and nothing else, so the number of engine queries this
-- module makes is fixed at two per state line regardless of how many extractors
-- died in between.
function Report(brain, alert, world)
    local defences = DefenceStructures(brain)
    local summary = SummariseDefences(defences, alert)
    ResolvePending(brain, defences)
    return {
        Cover = summary,
        Loss = LossSummary(brain),
        Span = BaseSpan(brain, world),
    }
end
