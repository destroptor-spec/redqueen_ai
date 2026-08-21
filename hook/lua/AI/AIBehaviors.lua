local RedQueenOriginalCDROverCharge = CDROverCharge

local function HasCompletedEnhancement(commander)
    if not SimUnitEnhancements then
        return false
    end

    local enhancements = SimUnitEnhancements[commander.EntityId]
    if not enhancements then
        return false
    end

    for _, enhancement in pairs(enhancements) do
        if enhancement then
            return true
        end
    end
    return false
end

function CDROverCharge(aiBrain, commander)
    if aiBrain and aiBrain.RedQueenContext and not HasCompletedEnhancement(commander) then
        return
    end
    return RedQueenOriginalCDROverCharge(aiBrain, commander)
end
