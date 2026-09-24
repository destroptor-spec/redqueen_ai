local AlertScope = import("/mods/TheRedQueen/lua/AI/RedQueen/AlertScope.lua")

-- Why extractor upgrades are withheld right now.
--
-- Stall risk is army-wide and stays that way: there is no spare mass anywhere
-- to put into an upgrade. A defence alert is not army-wide, and treating it as
-- if it were is what kept this economy on Tech 1 extractors. Measured on the
-- twelve-cell control matrix, `mexgate=under-attack` is the dominant sample on
-- every LandLarge cell -- 26 of 35 on Syrtis Major 8675309 -- so for three
-- quarters of those matches no extractor anywhere could be upgraded, Red
-- Queen's own or native's. Mass income never reaches the Tech 3 gate it is
-- waiting on, and land Tech 3 is reached in none of the logged matches.
--
-- `units` is the set the caller owns. The alert blocks only when it is on top
-- of all of them; an alert at an expansion is no reason to leave the extractor
-- at home on Tech 1. Passing nothing keeps the old army-wide answer.
function BlockReason(state, alert, units)
    if state and state.StallRisk then return "stall-risk" end
    if AlertScope.CoversAll(alert, units) then return "under-attack" end
    return nil
end

-- Remove only withheld extractors before native UnitUpgradeAI calls Stop().
-- Assigning to ArmyPool preserves existing upgrade orders; disbanding a
-- platoon containing those units would cancel them.
function FilterNative(platoon, brain)
    if not brain or not brain.RedQueenLobbyPersonality then return end
    local modules = brain.RedQueenModules or {}
    local state = modules.Economy and modules.Economy.State
    local alert = modules.Strategy and modules.Strategy.ProductionDemand.DefenseAlert
    local stall = BlockReason(state, nil, nil) == "stall-risk"
    local units = platoon:GetPlatoonUnits()
    local withheld, remaining, blocked = {}, 0, 0
    local reason = nil
    for _, unit in pairs(units) do
        local hash = not unit.Dead and unit:GetBlueprint().CategoriesHash or {}
        local extractor = hash.STRUCTURE and hash.MASSEXTRACTION
        local running = extractor and unit:IsUnitState("Upgrading")
        -- Asked per extractor, not once for the army: this one is withheld
        -- only if the stall is real or the fight is actually on top of it.
        local here = extractor
            and (stall and "stall-risk"
                or (AlertScope.CoversUnit(alert, unit) and "under-attack" or nil))
            or nil
        if extractor and (here or running) then
            table.insert(withheld, unit)
            if here and not running then
                blocked = blocked + 1
                reason = reason or here
            end
        else
            remaining = remaining + 1
        end
    end
    if table.getn(withheld) == 0 then return end
    local pool = brain:GetPlatoonUniquelyNamed("ArmyPool")
    if not pool then return true end
    brain:AssignUnitsToPlatoon(pool, withheld, "Support", "None")
    brain.RedQueenExtractorBlocks = (brain.RedQueenExtractorBlocks or 0) + blocked
    if blocked > 0 then brain.RedQueenExtractorBlockReason = reason end
    if remaining == 0 then
        platoon:PlatoonDisband()
        return true
    end
end
