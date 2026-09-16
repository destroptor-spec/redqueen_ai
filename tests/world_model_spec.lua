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

local spawnMarkers = {}
local markerUtilities = {
    GetMarkersByType = function(markerType)
        if markerType == "Spawn" then
            return spawnMarkers, table.getn(spawnMarkers)
        elseif markerType == "Mass" then
            return {
                { Name = "Mass1", Position = { 100, 0, 0 } },
                { Name = "Mass2", Position = { 110, 0, 0 } },
            }, 2
        elseif markerType == "Defensive Point" then
            return { { Name = "SafeDefense", Position = { 300, 0, 0 } } }, 1
        elseif markerType == "Expansion Area" then
            return { { Name = "ThreatenedExpansion", Position = { 400, 0, 0 } } }, 1
        elseif markerType == "Naval Area" then
            -- Deliberately out of coordinate order, and named with the
            -- generator's unpadded "%00d" so a name sort would mis-order them.
            return {
                { Name = "Naval Area 10", Position = { 900, 0, 0 } },
                { Name = "Naval Area 9", Position = { 700, 0, 0 } },
                { Name = "Naval Area 2", Position = { 520, 0, 0 } },
            }, 3
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
        UnknownRoutePresumedThreat = 30,  -- spec keeps the shipping value
        RouteCoverageConfidenceForFull = 1.0,
        EnemyBaseDiscoveryRadius = 60,
        FriendlySpawnMatchRadius = 12,
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

local module = setmetatable({}, { __index = _G })
setfenv(assert(loadfile("lua/AI/RedQueen/WorldModel.lua")), module)()
local Create = module.Create

local brain = { GetArmyStartPos = function() return 0, 0 end }
local world = Create(brain, { EnemyArmies = {} })
assert(world:GetMaximumForwardBases() == 2, "20 km maps must cap forward bases at two")

-- The map's mass points, kept from the marker scan rather than recounted.
-- Claiming an unclaimed point is 36 mass for +2/s -- an 18-second payback,
-- against 225 seconds for a Tech 2 upgrade -- so what an army holds against
-- what exists is the figure that says whether expansion has anything to gain.
assert(world.MassPointCount == 2,
    "the map's mass point total must be recorded, got " .. tostring(world.MassPointCount))

-- Coverage is reported separately from threat, because the two questions have
-- different answers and conflating them is the defect under test: everything
-- below x=600 has been observed, so threat 0 there means "watched and clear",
-- while beyond it means "never looked".
local observedTo = 600
local intel = {
    GetThreatNear = function(_, position)
        return position[1] >= 350 and 100 or 0
    end,
    GetCoverageNear = function(_, position)
        return position[1] <= observedTo and 1 or 0
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

local nearbyClaims = {
    MassCluster1 = true,
    ThreatenedExpansion = true,
}
local engineerAtDestroyedSite = { 300, 0, 0 }
site = world:SelectForwardBaseSite(
    engineerAtDestroyedSite,
    { 500, 0, 0 },
    intel,
    nearbyClaims,
    100
)
assert(not site, "ordinary markers inside the engineer minimum distance must remain ineligible")

site = world:SelectForwardBaseSite(
    engineerAtDestroyedSite,
    { 500, 0, 0 },
    intel,
    nearbyClaims,
    100,
    { SafeDefense = true }
)
assert(site and site.Name == "SafeDefense", "released destroyed markers must allow rebuilding at the engineer position")
assert(site.RouteThreat == 0, "nearby rebuilding must retain engineer-origin route threat checks")

-- Route coverage is measured and reported, and deliberately does not gate.
--
-- Threat is summed from observations, so an unscouted route reports 0 -- the
-- same number as a route watched and found clear. Coverage is what lets a
-- caller tell those apart, and it is recorded on the chosen site so a match can
-- be diagnosed. It is not charged as risk: doing so was measured on Seton's
-- Clutch and cost expansion without saving an engineer, because the losses
-- happen on fully covered routes part-way through a long walk.
observedTo = 600
local seeing = world:SelectForwardBaseSite(
    world.StartPosition, { 500, 0, 0 }, intel, {}, 100
)
assert(seeing and seeing.Name == "SafeDefense",
    "an observed approach must allow progress toward the objective")
assert(seeing.RouteCoverage == 1, "an observed route must report full coverage")

observedTo = 200
local blind = world:SelectForwardBaseSite(
    world.StartPosition, { 500, 0, 0 }, intel, { MassCluster1 = true, Mass2 = true }, 100
)
assert(blind, "reduced coverage must not by itself withhold a site")
assert(blind.RouteCoverage < 1,
    "a route outside observed ground must report reduced coverage")
assert(blind.RouteThreat == 0,
    "and must still report its observed threat unmodified, so the two stay separable")
observedTo = 600

-- Coverage must be averaged, so one watched corner cannot vouch for a long
-- blind route.
local partial = { 0, 0, 0 }
observedTo = 1
local sampled = select(2, world:GetObservedRouteThreat(
    partial, { 400, 0, 0 }, intel, 60, "Land"
))
assert(sampled > 0 and sampled < 1,
    "a route half in view must report partial coverage, got " .. tostring(sampled))
observedTo = 600

-- An intel source that cannot report coverage must not be treated as blind.
local coverageless = { GetThreatNear = function() return 0 end }
local unknowable = select(2, world:GetObservedRouteThreat(
    partial, { 400, 0, 0 }, coverageless, 60, "Land"
))
assert(unknowable == 1, "absent coverage reporting must not fabricate ignorance")

-- The traveller's own graph decides reachability. Every engineer in the game
-- crosses water, so asking about Land describes none of them.
local askedLayers = {}
local savedCanPathTo = navUtils.CanPathTo
navUtils.CanPathTo = function(layer) askedLayers[layer] = true; return true end
world:SelectForwardBaseSite(world.StartPosition, { 500, 0, 0 }, intel, {}, 100, nil, "Hover")
navUtils.CanPathTo = savedCanPathTo
assert(askedLayers.Hover, "site selection must path on the layer it is given")
assert(not askedLayers.Land, "a hover engineer must not be judged on the land graph")

-- A safe endpoint does not excuse an unsafe route or departure. Engine paths
-- may omit their origin; always sample it explicitly. A remote threat alone
-- must not block a locally safe route, even with an objective at home.
local savedPathTo = navUtils.PathTo
local routeOrigin = { 0, 0, 0 }
local routeMiddle = { 150, 0, 0 }
navUtils.PathTo = function(_, _, destination) return { routeMiddle, destination } end
for _, threatenedX in ipairs({ 0, 150, 300, 900 }) do
    local routeIntel = {
        GetThreatNear = function(_, position)
            return position[1] == threatenedX and 100 or 0
        end,
    }
    local selected = world:SelectForwardBaseSite(routeOrigin, routeOrigin,
        routeIntel, nearbyClaims, 100)
    assert((selected ~= nil) == (threatenedX == 900),
        "only threats near the engineer, route or destination should veto this site")
end
navUtils.PathTo = savedPathTo

-- A fleet's destination must be water it can actually reach, never the enemy
-- start, which is dry land where a commander spawns.
assert(table.getn(world.NavalApproaches) == 3, "naval area markers must be collected")
assert(world.NavalApproaches[1].Position[1] == 520
    and world.NavalApproaches[2].Position[1] == 700
    and world.NavalApproaches[3].Position[1] == 900,
    "naval approaches must sort by coordinate, not by the generator's unpadded name")

local enemyStart = { 1000, 0, 0 }
local askedLayers = {}
-- Model the engine faithfully: NavUtils.CanPathTo reports OriginUnpathable when
-- the ORIGIN cell has no label on the layer. Our army start is dry land, so a
-- water route out of it fails just as a water route into an enemy start does.
-- A stub that only inspects the destination hides that entirely -- which is how
-- the first version of GetNavalApproach shipped still falling through to Air.
local navalMarkerX = { [520] = true, [700] = true, [900] = true }
navUtils.CanPathTo = function(layer, origin, destination)
    table.insert(askedLayers, layer)
    if layer ~= "Water" then return false end
    if not navalMarkerX[origin[1]] then return nil, "OriginUnpathable" end
    -- The nearest approach to the enemy sits behind a land bridge.
    return destination[1] ~= 900
end

local approach = world:GetNavalApproach(world.StartPosition, enemyStart)
assert(approach, "a naval approach must be found from a land army start, not only from water")
assert(approach[1] == 700, "the nearest water-reachable approach must win, skipping unreachable ones")
for _, layer in ipairs(askedLayers) do
    assert(layer == "Water", "naval approach selection must only ask about water routes")
end

-- Exercise the catalog against the real world model, including native-style
-- rejection of land origins. Both naval experimentals must share this route.
local experimentals = setmetatable({}, { __index = _G })
setfenv(assert(loadfile("lua/AI/RedQueen/Experimentals.lua")), experimentals)()
world.EnemyStarts = { { Position = enemyStart } }
for _, faction in ipairs({ 1, 2 }) do
    assert(experimentals.CanAct(world,
        experimentals.ForTemplate(faction, "T4SeaExperimental1"), world.StartPosition),
        "naval experimentals must be eligible through connected water approaches")
end

assert(world:NearestNavalApproach(world.StartPosition)[1] == 520,
    "the home end must resolve onto the nearest water without a route test")

navUtils.CanPathTo = function(_, origin, destination)
    return origin == destination
end
assert(not world:GetNavalApproach(world.StartPosition, enemyStart),
    "a disconnected home marker is reachable from itself but is not an enemy approach")
for _, faction in ipairs({ 1, 2 }) do
    assert(not experimentals.CanAct(world,
        experimentals.ForTemplate(faction, "T4SeaExperimental1"), world.StartPosition),
        "a home-only water route must not enable naval experimentals")
end

local navalApproaches = world.NavalApproaches
world.NavalApproaches = {
    { Position = { 50, 0, 0 } },
    { Position = { 150, 0, 0 } },
    { Position = { 900, 0, 0 } },
}
navUtils.CanPathTo = function(_, origin, destination)
    return destination[1] < 200
end
assert(not world:GetNavalApproach(world.StartPosition, enemyStart),
    "other reachable markers in the home basin must not count as enemy-side water")
world.NavalApproaches = navalApproaches

navUtils.CanPathTo = function() return false end
assert(not world:GetNavalApproach(world.StartPosition, enemyStart),
    "with no water route the caller must be told, not handed an unreachable order")
assert(not world:GetNavalApproach(nil, enemyStart), "a missing origin must not select an approach")

navUtils.CanPathTo = function() return true end


-- Where the enemy lives, in two tiers.
--
-- A player in the lobby sees every start position unless the host randomised
-- them, and even then a full map gives it away: if every slot has someone on
-- it, every slot that is not yours or an ally's holds an enemy. Once a scout
-- has found a base that player does not forget it when the scout dies. All
-- three are contracts: what may be read for free, what may be deduced, and
-- what must survive the intel that produced it.
ArmyBrains[7] = { GetArmyStartPos = function() return 800, 800 end }
ArmyBrains[8] = { GetArmyStartPos = function() return 200, 100 end }
local function EnemyWorld()
    return Create(brain, { EnemyArmies = { 7, 8 }, AlliedArmies = { 1 } })
end
-- Four slots: ours at the origin and three others.
local function Slots(occupied)
    spawnMarkers = {
        { Name = "ARMY_1", Position = { 0, 0, 0 }, IsOccupied = true },
        { Name = "ARMY_2", Position = { 200, 0, 100 }, IsOccupied = occupied },
        { Name = "ARMY_3", Position = { 800, 0, 800 }, IsOccupied = occupied },
        { Name = "ARMY_4", Position = { 900, 0, 100 }, IsOccupied = occupied },
    }
end
Slots(true)

ScenarioInfo.Options = nil
local revealed = EnemyWorld()
assert(revealed.SpawnsRevealed, "an absent TeamSpawn is fixed spawns, not hidden ones")
assert(table.getn(revealed.EnemyStarts) == 2, "revealed spawns must yield every enemy start")
for _, enemy in ipairs(revealed.EnemyStarts) do
    assert(enemy.Known, "a revealed start is known from the first tick")
    assert(enemy.Army, "a revealed start carries its army, as the lobby showed it")
end
assert(revealed:GetClosestEnemyStart(revealed.StartPosition)[1] == 200,
    "a known start must be offered as a destination")

for _, option in ipairs({ "fixed", "random_reveal", "balanced_reveal",
    "balanced_reveal_mirrored", "balanced_flex_reveal" }) do
    ScenarioInfo.Options = { TeamSpawn = option }
    assert(EnemyWorld().SpawnsRevealed, option .. " shows every start in the lobby")
end

for _, option in ipairs({ "random", "balanced", "balanced_flex" }) do
    ScenarioInfo.Options = { TeamSpawn = option }
    assert(not EnemyWorld().SpawnsRevealed, option .. " hides who spawned where")
end

-- Randomised spawns on a full map hide nothing: three slots, ours excluded,
-- two enemies -- so both remaining slots hold one, without scouting for it.
ScenarioInfo.Options = { TeamSpawn = "random" }
Slots(true)
local full = EnemyWorld()
assert(full.AllSpawnsOccupied, "every slot taken is a full map")
assert(table.getn(full.EnemyStarts) == 3, "our own slot is excluded, the rest are candidates")
for _, enemy in ipairs(full.EnemyStarts) do
    assert(enemy.Known, "on a full map every slot that is not ours holds an enemy")
    assert(not enemy.Army, "which enemy holds which slot is still not ours to read")
end

-- Empty slots restore the hiding places, and a closed slot is indistinguishable
-- from an empty one: the sim is told about neither, so both read as unoccupied
-- and Red Queen stays conservative rather than claiming a deduction it cannot
-- make. This is the safe direction -- it scouts a slot nobody could be in.
Slots(false)
local partial = EnemyWorld()
assert(not partial.AllSpawnsOccupied, "an unoccupied slot is a place an enemy could be")
assert(table.getn(partial.EnemyStarts) == 3,
    "every slot but ours stays a candidate, occupied or not")
for _, enemy in ipairs(partial.EnemyStarts) do
    assert(not enemy.Known, "nothing is known before anything has been seen")
end
assert(partial.EnemyStarts[1].Position[1] == 200,
    "candidates are ordered by distance from home, not by slot order")
assert(not partial:GetClosestEnemyStart(partial.StartPosition),
    "an unresolved start is a place to scout, not a place to attack")

-- A mobile unit proves nothing: it travelled to where it was seen.
local intel = { Observations = {
    mover = { Position = { 800, 0, 800 }, Role = { Structure = false } },
} }
assert(partial:ResolveEnemyBases(intel) == 0, "a mobile unit must not resolve a base")

-- Nor does a structure standing somewhere that is not a start.
intel.Observations.outpost = { Position = { 500, 0, 500 }, Role = { Structure = true } }
assert(partial:ResolveEnemyBases(intel) == 0,
    "a structure away from every start resolves no start")

-- A structure on a start does.
intel.Observations.factory = { Position = { 820, 0, 790 }, Role = { Structure = true } }
assert(partial:ResolveEnemyBases(intel) == 1, "an observed structure resolves that start")
assert(partial:GetClosestEnemyStart(partial.StartPosition)[1] == 800,
    "a resolved start must be offered as a destination")
assert(partial:ResolveEnemyBases(intel) == 0, "an already-resolved start resolves once")
assert(table.getn(partial.EnemyStarts) == 3, "resolving one start must not drop the others")

-- The observation decays at IntelLifetimeSeconds. The base does not.
intel.Observations = {}
partial:ResolveEnemyBases(intel)
local afterDecay = partial:GetClosestEnemyStart(partial.StartPosition)
assert(afterDecay and afterDecay[1] == 800,
    "a resolved start must outlive the intel that produced it")
partial:Rebuild()
local afterRebuild = partial:GetClosestEnemyStart(partial.StartPosition)
assert(afterRebuild and afterRebuild[1] == 800,
    "a resolved start must survive a world rebuild")

-- An ally's slot is ours to see, so it is never an enemy candidate.
ArmyBrains[9] = { GetArmyStartPos = function() return 900, 100 end }
Slots(false)
local allied = Create(brain, { EnemyArmies = { 7, 8 }, AlliedArmies = { 1, 9 } })
assert(table.getn(allied.EnemyStarts) == 2, "an allied slot must not be scouted as an enemy")
for _, enemy in ipairs(allied.EnemyStarts) do
    assert(enemy.Position[1] ~= 900, "the ally's own start must be excluded")
end
ArmyBrains[9] = nil

-- Without the engine's spawn cache there is nothing to enumerate, so fall back
-- to the occupied enemy starts rather than going blind.
spawnMarkers = {}
local unmapped = EnemyWorld()
assert(table.getn(unmapped.EnemyStarts) == 2,
    "a missing spawn cache must fall back to the occupied enemy starts")
assert(not unmapped.EnemyStarts[1].Known, "the fallback claims no knowledge it has not earned")

-- With the lobby showing the spawns there is nothing to learn.
ScenarioInfo.Options = { TeamSpawn = "fixed" }
Slots(true)
local open = EnemyWorld()
assert(open:ResolveEnemyBases({ Observations = {
    x = { Position = { 800, 0, 800 }, Role = { Structure = true } },
} }) == 0, "revealed spawns have nothing left to resolve")
ScenarioInfo.Options = nil
ArmyBrains[7] = nil
ArmyBrains[8] = nil

print("Red Queen world model contracts passed")
