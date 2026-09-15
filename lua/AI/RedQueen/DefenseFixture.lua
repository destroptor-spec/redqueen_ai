local Logger = import("/mods/TheRedQueen/lua/AI/RedQueen/Logger.lua")

local function Water(x, z)
    return GetSurfaceHeight(x, z) - GetTerrainHeight(x, z) > 2
end

function Run(brain)
    WaitTicks(200)
    local modules = brain.RedQueenModules
    local width = modules.World.Width
    local coast, sea, land
    -- Public terrain only; search all four shore orientations.
    for x = 16, width - 16, 4 do
        for z = 16, width - 16, 4 do
            for _, direction in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
                local sx, sz = x + direction[1] * 48, z + direction[2] * 48
                local lx, lz = x - direction[1] * 12, z - direction[2] * 12
                if not coast and sx > 0 and sz > 0 and sx < width and sz < width
                    and Water(x, z) and Water(sx, sz) and not Water(lx, lz) then
                    coast = { x, GetSurfaceHeight(x, z), z }
                    sea = { sx, GetSurfaceHeight(sx, sz), sz }
                    land = { lx, GetTerrainHeight(lx, lz), lz }
                end
            end
        end
    end
    assert(coast, "fixture needs a coastal test site")
    local tanks = {}
    for index = 1, 24 do
        tanks[index] = CreateUnitHPR("uel0303", brain:GetArmyIndex(), land[1], land[2], land[3], 0, 0, 0)
    end
    local ships = {}
    local enemy = brain.RedQueenContext.EnemyArmies[1]
    for index = 1, 8 do
        ships[index] = CreateUnitHPR("urs0201", enemy, sea[1], sea[2], sea[3], 0, 0, 0)
    end
    local responders = {}
    for index = 1, 2 do
        responders[index] = CreateUnitHPR("uas0103", brain:GetArmyIndex(), coast[1], coast[2], coast[3], 0, 0, 0)
        responders[index]:SetIntelRadius("Vision", 100)
    end
    WaitTicks(5)
    for _, ship in ipairs(ships) do
        local blip = ship:GetBlip(brain:GetArmyIndex())
        assert(blip and blip:IsSeenNow(brain:GetArmyIndex()), "fixture must use observed contacts")
        modules.Intel:ObserveUnit(blip, GetGameTick())
    end
    local strategy = modules.Strategy
    local original = strategy.GetProtectedAnchors
    strategy.GetProtectedAnchors = function()
        return { strategy:MakeAnchor(coast, "NavalBase", "fixture") }
    end
    strategy.DefenseAlert = { Active = false }
    local alert = strategy:UpdateDefenseAlert()
    Logger.Info(brain, string.format("fixture naval active=%s friendly=%.1f threat=%.1f observed=%d",
        tostring(alert.Active), alert.FriendlyThreat or strategy:GetOwnThreatNear(coast, math.max(60, width / 12)),
        alert.Threat or 0, table.getn(ships)))
    local response = modules.Combat:IssueObjective(responders, { Type = "Defend", Position = sea }, "Water")
    Logger.Info(brain, "fixture naval reachable-response=" .. tostring(response))
    strategy.GetProtectedAnchors = original
    brain:OnDefeat()
end
