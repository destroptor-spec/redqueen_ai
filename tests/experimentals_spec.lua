-- Contracts for the experimental classification.
--
-- These drive the real catalog. The point of the module is that a template key
-- cannot be trusted to hold what its name says, so a contract asserting against
-- a stubbed catalog would prove nothing.

-- Load the module the way the engine does. FAF's import() runs the file in a
-- fresh environment and returns *that environment*, ignoring any value the file
-- returns. dofile() does the opposite, so a module exporting via `return {...}`
-- passes a dofile-based contract and then fails in game with a strict-global
-- error -- which is exactly what happened here.
local function importModule(path)
    local environment = setmetatable({}, { __index = _G })
    setfenv(assert(loadfile(path)), environment)()
    return environment
end

local experimentals = importModule("lua/AI/RedQueen/Experimentals.lua")
local Roles = experimentals.Roles

-- Every entry must be classified and name the blueprint it expects, so a future
-- FAF template change can be caught by comparing against the engine rather than
-- discovered in a match.
local seen = {}
for faction, entries in pairs(experimentals.Catalog) do
    assert(type(faction) == "number" and faction >= 1 and faction <= 4,
        "catalog must be keyed by FAF faction index")
    for _, entry in ipairs(entries) do
        assert(entry.Template and entry.Template ~= "", "every entry needs a template key")
        assert(entry.Blueprint and string.len(entry.Blueprint) == 7,
            "every entry must record the blueprint the key resolves to")
        assert(Roles[entry.Role], "every entry needs a known role: " .. tostring(entry.Blueprint))
        assert((entry.Mass or 0) > 0, "every entry needs its mass cost")

        -- One key per faction. Aeon and Seraphim both alias
        -- T4LandExperimental2 to the same unit as T4LandExperimental1, and
        -- listing both would let one unit be started twice under two names.
        local key = faction .. ":" .. entry.Template
        assert(not seen[key], "a template key must appear once per faction: " .. key)
        seen[key] = true
    end
end

-- An assault or mobile-siege experimental has to arrive somewhere to be worth
-- its mass, so it must carry the layer its path is tested on. Every assault
-- experimental in the game is amphibious, air or naval -- never plain Land --
-- which is precisely why the layer is recorded rather than assumed.
for faction, entries in pairs(experimentals.Catalog) do
    for _, entry in ipairs(entries) do
        if entry.Role == Roles.Assault then
            assert(entry.Layer, "an assault experimental must declare its layer: " .. entry.Blueprint)
            assert(entry.Layer ~= "Land",
                "no experimental moves on the Land graph; " .. entry.Blueprint .. " must not claim it")
        end
        if not entry.Layer then
            assert(entry.Role ~= Roles.Assault and entry.Role ~= Roles.Support,
                "a unit with no layer cannot assault or escort: " .. entry.Blueprint)
        end
    end
end

-- The rejected keys must be genuinely absent, not merely commented about.
for _, bad in ipairs(experimentals.Rejected) do
    assert(experimentals.ForTemplate(bad.Faction, bad.Template) == nil,
        "a rejected key must not be buildable: faction " .. bad.Faction .. " " .. bad.Template)
    assert(bad.Reason and bad.Reason ~= "", "a rejection must say why")
end
assert(experimentals.ForTemplate(3, "T4SeaExperimental1") == nil,
    "Cybran has no naval experimental; the key resolves to a Tech 1 land factory")
assert(experimentals.ForTemplate(4, "T4SeaExperimental1") == nil,
    "Seraphim has no naval experimental; the key resolves to a Tech 1 land factory")
assert(experimentals.ForTemplate(2, "T4Artillery") == nil,
    "Aeon T4Artillery is Tech 3 heavy artillery, not an experimental")
assert(experimentals.ForTemplate(1, "T4AirExperimental1") == nil,
    "UEF T4AirExperimental1 resolves to the amphibious Fatboy")

-- Aeon's experimental artillery lives under a Tech 3 key, so it is only
-- reachable if the catalog says so explicitly.
local salvation = experimentals.ForTemplate(2, "T3RapidArtillery")
assert(salvation and salvation.Blueprint == "xab2307" and salvation.Role == Roles.Siege,
    "Aeon Salvation must be reachable through its actual T3RapidArtillery key")

-- Path gating. A structure has no route to satisfy; a mobile entry must have an
-- enemy start reachable on its own layer.
local reachable = {}
local world = {
    EnemyStarts = { { Position = { 90, 0, 90 } } },
    GetNavalApproach = function(self, origin, target)
        assert(target == self.EnemyStarts[1].Position)
        return reachable.Water and { 80, 0, 80 } or nil
    end,
    GetClosestEnemyStart = function(_, origin, layer)
        assert(layer ~= "Water", "naval experimentals must resolve water endpoints")
        return reachable[layer] and { 90, 0, 90 } or nil
    end,
}
local origin = { 10, 0, 10 }

local colossus = experimentals.ForTemplate(2, "T4LandExperimental1")
assert(colossus.Layer == "Amphibious", "the Galactic Colossus is RULEUMT_Amphibious")
assert(not experimentals.CanAct(world, colossus, origin),
    "with no amphibious route the Colossus cannot act")
reachable.Land = true
assert(not experimentals.CanAct(world, colossus, origin),
    "a Land route must not satisfy an amphibious unit")
reachable.Amphibious = true
assert(experimentals.CanAct(world, colossus, origin), "an amphibious route lets it act")

local mavor = experimentals.ForTemplate(1, "T4Artillery")
assert(mavor.Role == Roles.Siege and not mavor.Layer, "the Mavor is a static siege structure")
assert(experimentals.CanAct(world, mavor, origin),
    "a static siege experimental needs range, not a route")
assert(experimentals.CanAct(nil, mavor, nil),
    "a structure must not depend on a world model at all")

-- Selection walks the faction's entries in declaration order and returns the
-- first that can act, so it is deterministic without a runtime sort.
reachable = { Air = true }
local aeonAssault = experimentals.SelectForRole(world, 2, Roles.Assault, origin)
assert(aeonAssault and aeonAssault.Blueprint == "uaa0310",
    "with only air reachable, Aeon's assault choice must be the CZAR")
assert(not experimentals.HasReachableRole(world, 1, Roles.Support, origin),
    "the Atlantis is a Water unit and must not be offered with no water route")
reachable.Water = true
assert(experimentals.HasReachableRole(world, 1, Roles.Support, origin),
    "UEF's Atlantis is the support case once the water is reachable")
assert(experimentals.CanAct(world, experimentals.ForTemplate(2, "T4SeaExperimental1"), origin),
    "Aeon's Tempest must use the same water route as the Atlantis")
assert(not experimentals.HasReachableRole(world, 3, Roles.Support, origin),
    "Cybran has no support experimental")

-- UEF genuinely has no assault experimental: its land key is the Fatboy, a
-- mobile artillery piece, and its air key is that same unit. Recorded so the
-- absence reads as a fact about the game rather than a gap in the table.
reachable = { Amphibious = true, Air = true, Water = true }
assert(not experimentals.HasReachableRole(world, 1, Roles.Assault, origin),
    "UEF has no assault experimental in Forged Alliance")
for _, faction in ipairs({ 2, 3, 4 }) do
    assert(experimentals.HasReachableRole(world, faction, Roles.Assault, origin),
        "faction " .. faction .. " must have a reachable assault experimental")
end

-- In-flight work is reported by blueprint, so the classification has to be able
-- to name a role from one. Every catalog blueprint must resolve, and anything
-- else must return nil rather than guessing.
for faction, entries in pairs(experimentals.Catalog) do
    for _, entry in ipairs(entries) do
        assert(experimentals.RoleForBlueprint(entry.Blueprint) == entry.Role,
            "blueprint " .. entry.Blueprint .. " must classify as " .. entry.Role)
        assert(experimentals.RoleForBlueprint(string.upper(entry.Blueprint)) == entry.Role,
            "blueprint lookup must not depend on case: " .. entry.Blueprint)
    end
end
assert(experimentals.RoleForBlueprint("urb0101") == nil,
    "a Tech 1 land factory is not an experimental role")
assert(experimentals.RoleForBlueprint(nil) == nil, "a missing blueprint yields no role")

-- An unknown faction must degrade quietly rather than error.
assert(experimentals.ForTemplate(9, "T4LandExperimental1") == nil, "unknown faction yields nothing")
assert(#experimentals.Options(9) == 0, "unknown faction has no options")

print("Red Queen experimental classification contracts passed")
