--- Experimental classification, and what each one needs before it is worth building.
--
-- An experimental is not one thing. A Galactic Colossus has to walk to the
-- enemy to be worth 27500 mass; a Mavor never moves and only needs the enemy to
-- be inside 1000-odd range; an Atlantis cannot shoot a ground target at all and
-- is only worth building next to a fleet it can escort. Building "an
-- experimental" without saying which kind spends an endgame economy on a unit
-- that cannot reach or cannot engage.
--
-- So every buildable experimental carries a Role -- what it is for -- and a
-- Layer -- the navigation graph it actually moves on. The Layer is the half that
-- has historically gone wrong: the assault experimentals are all
-- RULEUMT_Amphibious, so gating them on the Land graph asks a question about a
-- graph they do not use, which is the same defect that once left an entire hover
-- army without orders.
--
-- ## Why the catalog is written out rather than derived
--
-- FAF's `BuildingTemplates` maps a template key to a blueprint per faction, and
-- three of those mappings do not hold what their key says. Verified against
-- `lua/BuildingTemplates.lua` and the 606 blueprints in `units.nx2`:
--
--   * Cybran   `T4SeaExperimental1` -> `urb0101`, a Tech 1 *land factory*.
--   * Seraphim `T4SeaExperimental1` -> `xsb0101`, a Tech 1 *land factory*.
--   * Aeon and Cybran `T4Artillery` -> `uab2302`/`urb2302`, Tech 3 heavy
--     artillery, not an experimental at all.
--   * UEF `T4AirExperimental1` -> `uel0401`, the Fatboy: an experimental, but an
--     amphibious land unit sitting under an air key.
--
-- Neither Cybran nor Seraphim has a naval experimental in Forged Alliance, so
-- those two are placeholders rather than bugs in intent -- but a builder that
-- trusts the key spends a Tech 3 engineer erecting a 240-mass Tech 1 factory and
-- counts it as an endgame project. Every entry below therefore records the
-- blueprint it expects, and `Rejected` keeps the three bad keys documented in
-- code so the knowledge cannot be lost again.
--
-- Roles are assigned from blueprint categories, not from unit names:
--   Assault -- can attack a ground target (DIRECTFIRE, GROUNDATTACK or BOMBER)
--              and moves. Needs a route to the enemy on its own Layer.
--   Siege   -- INDIRECTFIRE artillery or a NUKE silo. Static, or mobile but too
--              slow to assault. Needs range, not a route.
--   Support -- moves and fights, but cannot engage ground. Only worth building
--              alongside a force of its own layer to escort.
--   Economy -- no weapons (the Paragon).
--   Intel   -- orbital observation (the Novax satellite).

Roles = {
    Assault = "Assault",
    Siege = "Siege",
    Support = "Support",
    Economy = "Economy",
    Intel = "Intel",
}

-- Faction indices follow FAF: 1 UEF, 2 Aeon, 3 Cybran, 4 Seraphim.
-- Order within a faction is the selection order, so it is deliberate and stable:
-- a contract can rely on it and no runtime sort is needed to stay deterministic.
Catalog = {
    [1] = {
        {
            Template = "T4SeaExperimental1",
            Blueprint = "ues0401",
            Name = "Atlantis",
            Role = Roles.Support,
            Layer = "Water",
            Mass = 12000,
            Escorts = "Water",
        },
        {
            Template = "T4LandExperimental1",
            Blueprint = "uel0401",
            Name = "Fatboy",
            Role = Roles.Siege,
            Layer = "Amphibious",
            Mass = 28000,
        },
        {
            Template = "T4Artillery",
            Blueprint = "ueb2401",
            Name = "Mavor",
            Role = Roles.Siege,
            Mass = 224775,
        },
        {
            Template = "T4SatelliteExperimental",
            Blueprint = "xeb2402",
            Name = "Novax Center",
            Role = Roles.Intel,
            Mass = 32000,
        },
    },
    [2] = {
        {
            Template = "T4LandExperimental1",
            Blueprint = "ual0401",
            Name = "Galactic Colossus",
            Role = Roles.Assault,
            Layer = "Amphibious",
            Mass = 27500,
        },
        {
            Template = "T4AirExperimental1",
            Blueprint = "uaa0310",
            Name = "CZAR",
            Role = Roles.Assault,
            Layer = "Air",
            Mass = 42750,
        },
        {
            Template = "T4SeaExperimental1",
            Blueprint = "uas0401",
            Name = "Tempest",
            Role = Roles.Assault,
            Layer = "Water",
            Mass = 25000,
        },
        {
            Template = "T3RapidArtillery",
            Blueprint = "xab2307",
            Name = "Salvation",
            Role = Roles.Siege,
            Mass = 202500,
        },
        {
            Template = "T4EconExperimental",
            Blueprint = "xab1401",
            Name = "Paragon",
            Role = Roles.Economy,
            Mass = 250200,
        },
    },
    [3] = {
        {
            Template = "T4LandExperimental1",
            Blueprint = "url0402",
            Name = "Monkeylord",
            Role = Roles.Assault,
            Layer = "Amphibious",
            Mass = 20000,
        },
        {
            Template = "T4LandExperimental3",
            Blueprint = "xrl0403",
            Name = "Megalith",
            Role = Roles.Assault,
            Layer = "Amphibious",
            Mass = 37500,
        },
        {
            Template = "T4AirExperimental1",
            Blueprint = "ura0401",
            Name = "Soul Ripper",
            Role = Roles.Assault,
            Layer = "Air",
            Mass = 29000,
        },
        {
            Template = "T4LandExperimental2",
            Blueprint = "url0401",
            Name = "Scathis",
            Role = Roles.Siege,
            Layer = "Amphibious",
            Mass = 220000,
        },
    },
    [4] = {
        {
            Template = "T4LandExperimental1",
            Blueprint = "xsl0401",
            Name = "Ythotha",
            Role = Roles.Assault,
            Layer = "Amphibious",
            Mass = 26500,
        },
        {
            Template = "T4AirExperimental1",
            Blueprint = "xsa0402",
            Name = "Ahwassa",
            Role = Roles.Assault,
            Layer = "Air",
            Mass = 48000,
        },
        {
            Template = "T4Artillery",
            Blueprint = "xsb2401",
            Name = "Yolona Oss",
            Role = Roles.Siege,
            Mass = 187650,
        },
    },
}

-- Template keys that must never be built, with the blueprint they actually
-- resolve to. Kept as data so a structural contract can assert no builder uses
-- one, and so the next reader does not have to rediscover it from the engine.
Rejected = {
    { Faction = 3, Template = "T4SeaExperimental1", Blueprint = "urb0101",
      Reason = "Tech 1 land factory; Cybran has no naval experimental" },
    { Faction = 4, Template = "T4SeaExperimental1", Blueprint = "xsb0101",
      Reason = "Tech 1 land factory; Seraphim has no naval experimental" },
    { Faction = 2, Template = "T4Artillery", Blueprint = "uab2302",
      Reason = "Tech 3 heavy artillery; Aeon's experimental artillery is T3RapidArtillery" },
    { Faction = 3, Template = "T4Artillery", Blueprint = "urb2302",
      Reason = "Tech 3 heavy artillery; Cybran has no experimental artillery" },
    { Faction = 1, Template = "T4AirExperimental1", Blueprint = "uel0401",
      Reason = "resolves to the Fatboy, an amphibious land unit; UEF has no air experimental" },
}

--- The role of a blueprint this module knows, or nil. Used to classify work
--- already in flight, which the engine reports by blueprint rather than by the
--- template key it was requested under.
function RoleForBlueprint(blueprint)
    if not blueprint then
        return nil
    end
    local wanted = string.lower(blueprint)
    for _, entries in pairs(Catalog) do
        for _, entry in ipairs(entries) do
            if entry.Blueprint == wanted then
                return entry.Role
            end
        end
    end
    return nil
end

--- Every catalog entry for a faction, optionally filtered to one role.
function Options(factionIndex, role)
    local entries = Catalog[factionIndex]
    if not entries then
        return {}
    end
    if not role then
        return entries
    end
    local matching = {}
    for _, entry in ipairs(entries) do
        if entry.Role == role then
            table.insert(matching, entry)
        end
    end
    return matching
end

--- True when `entry` can act against the enemy from `origin`.
--
-- A structure has no Layer and no route to satisfy -- a Mavor shells what it can
-- reach from where it stands -- so it is always considered able to act, and the
-- economy gate alone decides whether it is affordable. Naval units use water
-- approaches at both ends because army starts are on land. Other mobile entries
-- must have an enemy start reachable on their own layer.
function CanAct(world, entry, origin)
    if not entry then
        return false
    end
    if not entry.Layer then
        return true
    end
    if not world or not origin then
        return false
    end
    if entry.Layer == "Water" then
        if not world.GetNavalApproach then return false end
        for _, enemy in ipairs(world.EnemyStarts or {}) do
            if world:GetNavalApproach(origin, enemy.Position) then return true end
        end
        return false
    end
    if not world.GetClosestEnemyStart then return false end
    return world:GetClosestEnemyStart(origin, entry.Layer) ~= nil
end

--- The first entry of `role` that can act, or nil when none can.
function SelectForRole(world, factionIndex, role, origin)
    for _, entry in ipairs(Options(factionIndex, role)) do
        if CanAct(world, entry, origin) then
            return entry
        end
    end
    return nil
end

--- True when this faction has any entry of `role` that can act from `origin`.
function HasReachableRole(world, factionIndex, role, origin)
    return SelectForRole(world, factionIndex, role, origin) ~= nil
end

--- The entry a template key builds for a faction, or nil when the key is not
--- one this module will build. Used by builder conditions so a builder and its
--- gate can never disagree about which unit is at stake.
function ForTemplate(factionIndex, template)
    for _, entry in ipairs(Options(factionIndex)) do
        if entry.Template == template then
            return entry
        end
    end
    return nil
end
