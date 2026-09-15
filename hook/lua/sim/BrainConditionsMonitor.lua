local Lifecycle = import("/mods/TheRedQueen/lua/AI/RedQueen/BaseLifecycle.lua")

-- Cover both monitor checks and instant GetStatus, including shared functions.
-- Stock brains always call the exact native method with its original arguments.
local function Guard(class, name)
    local original = class[name]
    class[name] = function(self, reportFailure)
        if not Lifecycle.ConditionLive(self) then return false end
        return original(self, reportFailure)
    end
end
for _, class in ipairs({ ImportCondition, InstantImportCondition, FunctionCondition }) do
    Guard(class, "LocationExists")
    Guard(class, "CheckCondition")
    Guard(class, "GetStatus")
end
