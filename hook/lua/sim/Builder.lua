local Lifecycle = import("/mods/TheRedQueen/lua/AI/RedQueen/BaseLifecycle.lua")
local NativeCreate = Builder.Create
Builder.Create = function(self, brain, data, location)
    if Lifecycle.Enabled(brain) then
        self.RedQueenLocation = location
        self.RedQueenBase = brain.BuilderManagers and brain.BuilderManagers[location]
    end
    return NativeCreate(self, brain, data, location)
end

local function Retired(self)
    return Lifecycle.Enabled(self.Brain) and (self.RedQueenRetired
        or not Lifecycle.Live(self.Brain, self.RedQueenLocation, self.RedQueenBase))
end
local NativeStatus = Builder.GetBuilderStatus
Builder.GetBuilderStatus = function(self)
    if Retired(self) then self.BuilderStatus = false; return false end
    return NativeStatus(self)
end
local NativePriority = Builder.CalculatePriority
Builder.CalculatePriority = function(self, manager)
    if Retired(self) then
        local changed = self.Priority ~= 0
        self.RedQueenRetired = true
        self.Priority = 0
        return changed
    end
    return NativePriority(self, manager)
end
