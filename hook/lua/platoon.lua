local NativeForkThread = Platoon.ForkThread
Platoon.ForkThread = function(self, fn, ...)
    local thread = NativeForkThread(self, fn, unpack(arg))
    local brain = self:GetBrain()
    if brain and brain.RedQueenLobbyPersonality and fn == self.BaseManagersDistressAI then
        -- Native stores this evaluator in the pool's trash, which outlives
        -- brain teardown. It must stop before any base managers are destroyed.
        if brain.RedQueenCleaned then
            if thread then KillThread(thread) end
        else
            brain.RedQueenDistressThread = thread
        end
    end
    return thread
end

local RedQueenExtractorUpgrades = import("/mods/TheRedQueen/lua/AI/RedQueen/ExtractorUpgrades.lua")
local NativeUnitUpgradeAI = Platoon.UnitUpgradeAI
Platoon.UnitUpgradeAI = function(self)
    if RedQueenExtractorUpgrades.FilterNative(self, self:GetBrain()) then return end
    return NativeUnitUpgradeAI(self)
end
