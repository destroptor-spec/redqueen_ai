function ClassSimple(definition)
    return setmetatable(definition, {
        __call = function(class, ...)
            local instance = setmetatable({}, { __index = class })
            instance:__init(...)
            return instance
        end,
    })
end

function GetSurfaceHeight() return 0 end
function GetTerrainHeight() return 0 end
function GetGameTick() return 100 end

ScenarioInfo = { size = { 1024, 1024 } }
ArmyBrains = {}

local markerUtilities = {
    GetMarkersByType = function(markerType)
        if markerType == "Mass" then
            return {
                { Name = "Mass1", Position = { 100, 0, 0 } },
                { Name = "Mass2", Position = { 110, 0, 0 } },
            }, 2
        elseif markerType == "Defensive Point" then
            return { { Name = "SafeDefense", Position = { 300, 0, 0 } } }, 1
        elseif markerType == "Expansion Area" then
            return { { Name = "ThreatenedExpansion", Position = { 400, 0, 0 } } }, 1
        end
        return {}, 0
    end,
}
local navUtils = {
    CanPathTo = function() return true end,
    PathTo = function(_, origin, destination) return { origin, destination } end,
}
local constants = {
    Policy = {
        MaximumForwardBases = 3,
        ForwardBaseMapKilometersPerBase = 10,
        ForwardBaseMinimumDistance = 80,
        ForwardBaseSafetyRatio = 0.60,
        ForwardBaseSiteRadius = 60,
    },
}
local logger = { Info = function() end }

function import(path)
    if path == "/lua/sim/MarkerUtilities.lua" then
        return markerUtilities
    elseif path == "/lua/sim/NavUtils.lua" then
        return navUtils
    elseif path == "/mods/TheRedQueen/lua/AI/RedQueen/Constants.lua" then
        return constants
    elseif path == "/mods/TheRedQueen/lua/AI/RedQueen/Logger.lua" then
        return logger
    end
    error("unexpected import: " .. tostring(path))
end

dofile("lua/AI/RedQueen/WorldModel.lua")

local brain = { GetArmyStartPos = function() return 0, 0 end }
local world = Create(brain, { EnemyArmies = {} })
assert(world:GetMaximumForwardBases() == 2, "20 km maps must cap forward bases at two")

local intel = {
    GetThreatNear = function(_, position)
        return position[1] >= 350 and 100 or 0
    end,
}
local claimed = {}
local site = world:SelectForwardBaseSite(
    world.StartPosition,
    { 500, 0, 0 },
    intel,
    claimed,
    100
)
assert(site.Name == "SafeDefense", "forward bases must prefer safe progress toward the objective")
assert(site.RouteThreat == 0, "selected forward routes must use observed threat only")

claimed.SafeDefense = true
claimed.MassCluster1 = true
site = world:SelectForwardBaseSite(
    world.StartPosition,
    { 500, 0, 0 },
    intel,
    claimed,
    100
)
assert(not site, "route threat above escort capacity must reject a forward site")

print("Red Queen world model contracts passed")
