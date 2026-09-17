function BlockReason(state, alert)
    if state and state.StallRisk then return "stall-risk" end
    if alert and alert.Active then return "under-attack" end
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
    local reason = BlockReason(state, alert)
    local units = platoon:GetPlatoonUnits()
    local withheld, remaining, blocked = {}, 0, 0
    for _, unit in pairs(units) do
        local hash = not unit.Dead and unit:GetBlueprint().CategoriesHash or {}
        local extractor = hash.STRUCTURE and hash.MASSEXTRACTION
        local running = extractor and unit:IsUnitState("Upgrading")
        if extractor and (reason or running) then
            table.insert(withheld, unit)
            if reason and not running then blocked = blocked + 1 end
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
