function ClassSimple(definition)
    return setmetatable(definition, {
        __call = function(class, ...)
            local instance = setmetatable({}, { __index = class })
            instance:__init(...)
            return instance
        end,
    })
end

local currentTick = 1000
function GetGameTick()
    return currentTick
end

categories = {
    MOBILE = 1,
    LAND = 1,
    AIR = 1,
    NAVAL = 1,
    ALLUNITS = 1,
}

local constants = {
    Policy = {
        AirDropTargetRadius = 45,
        AirDropMaximumAirThreat = 6,
        StrategicHighValueThreshold = 80,
        StrategicFortificationThreshold = 40,
        FreshCombatIntelSeconds = 30,
        ArmyClusterMinimumRadius = 45,
        ArmyClusterMaximumRadius = 90,
        ArmyClusterMapDivisor = 12,
        ArmyApproachDistance = 10,
        ArmyClosingThreatFraction = 0.25,
        ObserversPerUpdate = 2,
        ObservationRadius = 70,
        IntelLifetimeSeconds = 120,
    },
}

function import(path)
    if path == "/mods/TheRedQueen/lua/AI/RedQueen/Constants.lua" then
        return constants
    end
    error("unexpected import: " .. tostring(path))
end

dofile("lua/AI/RedQueen/IntelManager.lua")

local function IntelBlip(entityId, position, intel)
    return {
        GetEntityId = function() return entityId end,
        GetPosition = function() return position end,
        GetBlueprint = function()
            return {
                BlueprintId = "enemy-" .. tostring(entityId),
                CategoriesHash = { MOBILE = true, LAND = true, TECH2 = true },
                Defense = { SurfaceThreatLevel = 10 },
                Economy = { BuildCostMass = 100 },
            }
        end,
        IsSeenNow = function() return intel.SeenNow or false end,
        IsSeenEver = function() return intel.SeenEver or false end,
        IsOnRadar = function() return intel.Radar or false end,
        IsOnSonar = function() return intel.Sonar or false end,
        IsOnOmni = function() return intel.Omni or false end,
    }
end

local function ProximityUnit(blip)
    return {
        GetBlip = function() return blip end,
        GetPosition = function() error("proximity unit positions must not be observed directly") end,
        GetBlueprint = function() error("proximity unit blueprints must not be observed directly") end,
    }
end

local visible = ProximityUnit(IntelBlip(101, { 10, 0, 10 }, { SeenNow = true }))
local identifiedRadar = ProximityUnit(IntelBlip(
    102,
    { 20, 0, 20 },
    { Radar = true, SeenEver = true }
))
local hidden = ProximityUnit(IntelBlip(103, { 30, 0, 30 }, {}))
local unidentifiedRadar = ProximityUnit(IntelBlip(104, { 40, 0, 40 }, { Radar = true }))
local observer = { GetPosition = function() return { 0, 0, 0 } end }
local observingBrain = {
    GetArmyIndex = function() return 1 end,
    GetListOfUnits = function() return { observer } end,
    GetUnitsAroundPoint = function()
        return { visible, identifiedRadar, hidden, unidentifiedRadar }
    end,
}
local observingManager = Create(observingBrain)
observingManager:Update()
assert(observingManager.Observations[101], "current visual intel must create an observation")
assert(observingManager.Observations[102], "identified active radar intel must create an observation")
assert(not observingManager.Observations[103], "hidden proximity units must not create observations")
assert(not observingManager.Observations[104], "unidentified radar must not expose exact blueprint intel")
assert(observingManager.Observations[101].BlueprintId == "enemy-101", "blueprints must come from verified blips")
assert(observingManager.Observations[102].Position[1] == 20, "positions must come from verified blips")

local manager = Create({})
manager.Observations = {
    [1] = {
        EntityId = 1,
        Position = { 40, 0, 0 },
        Layer = "Land",
        Threat = { Land = 0, Air = 0, Naval = 0, Economy = 5 },
        Role = { Economy = true, MassValue = 100 },
        Confidence = 1,
    },
    [2] = {
        EntityId = 2,
        Position = { 100, 0, 0 },
        Layer = "Land",
        Threat = { Land = 0, Air = 0, Naval = 0, Economy = 10 },
        Role = { Economy = true, Structure = true, Shield = true, MassValue = 500 },
        Confidence = 1,
    },
    [3] = {
        EntityId = 3,
        Position = { 103, 0, 0 },
        Layer = "Land",
        Threat = { Land = 3, Air = 10, Naval = 0, Economy = 0 },
        Role = { Economy = false, StaticDefense = true, Shield = true, Artillery = true, MassValue = 80 },
        Confidence = 1,
    },
    [4] = {
        EntityId = 4,
        Position = { 20, 0, 0 },
        Layer = "Land",
        Threat = { Land = 100, Air = 0, Naval = 0, Economy = 0 },
        Role = { Economy = false, MassValue = 200 },
        Confidence = 1,
    },
    [5] = {
        EntityId = 5,
        Position = { 105, 0, 0 },
        Layer = "Land",
        Threat = { Land = 0, Air = 0, Naval = 0, Economy = 0 },
        Role = { Economy = false, Structure = true, StrategicDefense = true, MassValue = 1000 },
        Confidence = 1,
    },
}
manager.HighestObservedTech = 3

local target = manager:GetBestKnownTarget({ 0, 0, 0 }, "Land")
assert(target.Role.Economy, "raid scoring must prefer economic value over the strongest combat contact")

local drop = manager:GetBestExposedEconomyTarget({ 0, 0, 0 })
assert(drop.EntityId == 1, "airdrop scoring must reject valuable targets protected by observed AA")
assert(drop.AirDefense == 0, "selected airdrop target must expose its observed AA threat")

local world = {
    CanPath = function(_, _, _, position)
        return position[1] < 80
    end,
}
local picture = manager:GetStrategicPicture({ 0, 0, 0 }, world)
assert(picture.EnemyTech == 3, "strategic picture must retain observed enemy tech")
assert(picture.HasHighValueTarget, "observed economy must expose strategic target value")
assert(picture.HasUnreachableTarget, "pathing must distinguish unreachable strategic value")
assert(not picture.HasReachableTarget, "small reachable raids must not masquerade as major targets")
assert(picture.Fortified, "observed shields, artillery, and static defense must identify fortification")
assert(picture.StrategicDefense == 1, "observed missile defense must be available to the director")

manager.Observations[6] = {
    EntityId = 6,
    Position = { 60, 0, 0 },
    PreviousPosition = { 80, 0, 0 },
    LastSeenTick = 990,
    Confidence = 1,
    Threat = { Land = 25, Air = 0, Naval = 0 },
    Role = { MobileCombat = true },
}
manager.Observations[7] = {
    EntityId = 7,
    Position = { 65, 0, 0 },
    PreviousPosition = { 85, 0, 0 },
    LastSeenTick = 995,
    Confidence = 1,
    Threat = { Land = 20, Air = 5, Naval = 0 },
    Role = { MobileCombat = true },
}
manager.Observations[8] = {
    EntityId = 8,
    Position = { 400, 0, 400 },
    LastSeenTick = 998,
    Confidence = 1,
    Threat = { Land = 200, Air = 0, Naval = 0 },
    Role = { MobileCombat = true },
}
local clusters = manager:GetObservedArmyClusters({ { 0, 0, 0 } }, 512)
assert(table.getn(clusters) == 2, "every fresh mobile formation must remain available to strategy")
assert(clusters[1].FirstEntityId == 8, "clusters must be sorted by threat deterministically")
assert(clusters[1].Threat == 200, "the largest independent formation must retain its threat")
assert(clusters[2].Count == 2, "fresh nearby mobile contacts must form one army cluster")
assert(clusters[2].Threat == 50, "army pressure must sum observed surface and air threat")
assert(clusters[2].Approaching, "contacts closing on a protected anchor must be acknowledged")
assert(clusters[2].FirstEntityId == 6, "cluster formation must use deterministic entity order")

local expiryBrain = {
    GetArmyIndex = function() return 1 end,
    GetListOfUnits = function() return {} end,
}
local expiryManager = Create(expiryBrain)
expiryManager.HighestObservedTech = 4
expiryManager.Observations = {
    [201] = {
        EntityId = 201,
        Position = { 200, 0, 200 },
        LastSeenTick = 799,
        Confidence = 1,
        Threat = { Land = 50, Air = 0, Naval = 0, Economy = 0 },
        Role = { MobileCombat = true, Tech = 3 },
    },
    [202] = {
        EntityId = 202,
        Position = { 100, 0, 100 },
        LastSeenTick = 1000,
        Confidence = 1,
        Threat = { Land = 20, Air = 0, Naval = 0, Economy = 0 },
        Role = { MobileCombat = true, Tech = 2 },
    },
}
currentTick = 2000
expiryManager:Update()
assert(not expiryManager.Observations[201], "expired T3 observations must be removed")
assert(expiryManager.Observations[202], "fresh lower-tech observations must survive")
assert(expiryManager.HighestObservedTech == 2, "enemy tech must fall to the highest surviving observation")

currentTick = 2201
expiryManager:Update()
assert(not expiryManager.Observations[202], "the final lower-tech observation must eventually expire")
assert(expiryManager.HighestObservedTech == 1, "enemy tech must return to tier one when no observations survive")

print("Red Queen intel manager contracts passed")
