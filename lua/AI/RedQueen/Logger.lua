local Constants = import("/mods/TheRedQueen/lua/AI/RedQueen/Constants.lua")

local function Format(brain, level, message)
    local army = "?"
    if brain and brain.Army then
        army = tostring(brain.Army)
    end
    return string.format("%s[%s][army=%s] %s", Constants.LogPrefix, level, army, tostring(message))
end
function Info(brain, message)
    LOG(Format(brain, "INFO", message))
end

function Warning(brain, message)
    WARN(Format(brain, "WARN", message))
end

function Error(brain, message)
    WARN(Format(brain, "ERROR", message))
end

function Debug(brain, message)
    if brain and brain.RedQueenDebug then
        LOG(Format(brain, "DEBUG", message))
    end
end
