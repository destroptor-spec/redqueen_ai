local Constants = import("/mods/TheRedQueen/lua/AI/RedQueen/Constants.lua")
local Logger = import("/mods/TheRedQueen/lua/AI/RedQueen/Logger.lua")

local function DistanceSquared(a, b)
    local dx = a[1] - b[1]
    local dz = a[3] - b[3]
    return dx * dx + dz * dz
end

---@class RedQueenPingManager
PingManager = ClassSimple {
    __init = function(self, brain)
        self.Brain = brain
        self.Requests = {}
        self.NextId = 1
    end,

    Handle = function(self, pingData)
        if not pingData or not pingData.Type or not pingData.Location then
            return
        end

        local ownerArmy = (pingData.Owner or -1) + 1
        if ownerArmy < 1 or not IsAlly(self.Brain.Army, ownerArmy) then
            return
        end

        local pingType = string.lower(tostring(pingData.Type))
        local requestType = nil
        local priority = 0
        if pingType == "attack" then
            requestType = "Attack"
            priority = 90
        elseif pingType == "move" then
            requestType = "Reinforce"
            priority = 80
        elseif pingType == "alert" then
            requestType = "Investigate"
            priority = 85
        else
            return
        end

        local tick = GetGameTick()
        for _, request in pairs(self.Requests) do
            if request.OwnerArmy == ownerArmy
                and request.Type == requestType
                and DistanceSquared(request.Position, pingData.Location) < 1600
                and request.ExpiresTick >= tick
            then
                request.Priority = math.min(120, request.Priority + 10)
                request.ExpiresTick = tick + Constants.Policy.PingLifetimeSeconds * 10
                Logger.Info(self.Brain, string.format("reinforced allied ping type=%s owner=%d", requestType, ownerArmy))
                return
            end
        end

        table.insert(self.Requests, {
            Id = self.NextId,
            Type = requestType,
            OwnerArmy = ownerArmy,
            Position = { pingData.Location[1], pingData.Location[2], pingData.Location[3] },
            Priority = priority,
            CreatedTick = tick,
            ExpiresTick = tick + Constants.Policy.PingLifetimeSeconds * 10,
        })
        self.NextId = self.NextId + 1
        Logger.Info(self.Brain, string.format("accepted allied ping type=%s owner=%d", requestType, ownerArmy))
    end,

    Update = function(self)
        local tick = GetGameTick()
        local retained = {}
        for _, request in pairs(self.Requests) do
            if request.ExpiresTick >= tick then
                table.insert(retained, request)
            end
        end
        self.Requests = retained
    end,

    GetBestRequest = function(self)
        local best = nil
        for _, request in pairs(self.Requests) do
            if not best or request.Priority > best.Priority
                or (request.Priority == best.Priority and request.CreatedTick < best.CreatedTick)
            then
                best = request
            end
        end
        return best
    end,
}

function Create(brain)
    return PingManager(brain)
end
