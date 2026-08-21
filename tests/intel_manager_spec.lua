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
    },
}

function import(path)
    if path == "/mods/TheRedQueen/lua/AI/RedQueen/Constants.lua" then
        return constants
    end
    error("unexpected import: " .. tostring(path))
end

dofile("lua/AI/RedQueen/IntelManager.lua")

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
    LastSeenTick = 600,
    Confidence = 1,
    Threat = { Land = 200, Air = 0, Naval = 0 },
    Role = { MobileCombat = true },
}
local pressure = manager:GetObservedArmyPressure({ { 0, 0, 0 } }, 512)
assert(pressure.Count == 2, "fresh nearby mobile contacts must form one army cluster")
assert(pressure.Threat == 50, "army pressure must sum observed surface and air threat")
assert(pressure.Approaching, "contacts closing on a protected anchor must be acknowledged")
assert(pressure.FirstEntityId == 6, "cluster selection must use deterministic entity order")

print("Red Queen intel manager contracts passed")
