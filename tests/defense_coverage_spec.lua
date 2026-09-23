-- Whether a defence can reach the fighting, not whether it exists.
--
-- Observed while spectating: the point defences and anti-air that were built
-- sat beside the factories and shields, out of range of the attack until the
-- enemy had already arrived there. `FortificationBuilders` cannot see that --
-- it satisfies a tier's need with any allied structure of that tier anywhere
-- inside the base radius. These contracts pin the measurement that can.
local constants = {
    Policy = { FortificationMinimumRadius = 40 },
}

function import(path)
    if path == "/mods/TheRedQueen/lua/AI/RedQueen/Constants.lua" then
        return constants
    end
    error("unexpected import: " .. tostring(path))
end

categories = setmetatable({}, {
    __index = function(value, key)
        local category = { Name = key }
        rawset(value, key, category)
        return category
    end,
})
-- Category algebra only has to be distinguishable, not faithful.
getmetatable(categories).__index = function(value, key)
    local category = setmetatable({ Name = key }, {
        __mul = function(a, b) return { Name = a.Name .. "*" .. b.Name } end,
    })
    rawset(value, key, category)
    return category
end

local environment = setmetatable({}, { __index = _G })
setfenv(assert(loadfile("lua/AI/RedQueen/DefenseCoverage.lua")), environment)()

local function Gun(x, z, range)
    return {
        GetPosition = function() return { x, 0, z } end,
        GetBlueprint = function()
            return {
                BlueprintId = "pd" .. tostring(range),
                Weapon = { { MaxRadius = range } },
            }
        end,
    }
end

-- A shield is a structure near the base with no weapon at all. It satisfies a
-- base-wide structure count while covering nothing, which is exactly the
-- confusion this measurement exists to remove.
local shield = {
    GetPosition = function() return { 0, 0, 0 } end,
    GetBlueprint = function() return { BlueprintId = "shield", Weapon = {} } end,
}

assert(environment.WeaponRange(shield) == 0, "a weaponless structure has no reach")
assert(environment.WeaponRange(Gun(0, 0, 26)) == 26, "reach is the longest weapon")
assert(environment.Covers(Gun(0, 0, 26), { 20, 0, 0 }), "a gun in range covers")
assert(not environment.Covers(Gun(0, 0, 26), { 40, 0, 0 }),
    "a gun out of range does not cover, however close to the base it stands")
assert(not environment.Covers(shield, { 1, 0, 0 }),
    "a weaponless structure never covers, at any distance")

-- Four guns at the base, an attack 150 away: the spectated case.
local defences = { Gun(0, 0, 26), Gun(10, 0, 10), Gun(-10, 0, 5), shield }
local brain = {
    GetListOfUnits = function(_, category)
        if category.Name == "STRUCTURE*DEFENSE" then return defences end
        return {}
    end,
}
local summary = environment.Summarise(brain, {
    Active = true, AnchorPosition = { 150, 0, 0 },
})
assert(summary.Total == 4, "every defence structure is held, got " .. summary.Total)
assert(summary.Covering == 0,
    "none of them can reach an attack 150 away, got " .. summary.Covering)
assert(math.floor(summary.Nearest) == 140,
    "and the nearest is 140 from the fighting, got " .. tostring(summary.Nearest))

-- The same guns against an attack close to the base. Two of the three reach it:
-- the long-ranged gun at the centre and the short one it happens to stand near.
-- The third has range 5 and is 23 away, which is the whole point -- reach is
-- per weapon, and a base-wide count cannot see it.
local near = environment.Summarise(brain, { Active = true, AnchorPosition = { 12, 0, 8 } })
assert(near.Covering == 2, "two guns reach a close attack, got " .. near.Covering)

-- An inactive alert has nothing to cover and must not be scored as failure.
local idle = environment.Summarise(brain, { Active = false, AnchorPosition = { 1, 0, 1 } })
assert(idle.Total == 4 and idle.Covering == 0 and idle.Nearest == 0,
    "an inactive alert reports holdings without a coverage verdict")

-- Extractor losses, with whether anything could have shot the attacker.
environment.RecordExtractorLoss(brain, { 200, 0, 200 })
environment.RecordExtractorLoss(brain, { 5, 0, 5 })
local losses = environment.LossSummary(brain)
assert(losses.Lost == 2, "both losses counted, got " .. losses.Lost)
assert(losses.Defended == 1,
    "only the one inside a gun's reach was defended, got " .. losses.Defended)

-- Fortifiable span: ground outside every base manager cannot be offered a
-- fortification builder at all, so it is not "under-defended" but unreachable.
local extractors = {
    { GetPosition = function() return { 0, 0, 0 } end },
    { GetPosition = function() return { 30, 0, 0 } end },
    { GetPosition = function() return { 400, 0, 400 } end },
}
local spanBrain = {
    BuilderManagers = {
        MAIN = { EngineerManager = {
            Radius = 100,
            GetLocationCoords = function() return { 0, 0, 0 } end,
        } },
    },
    GetListOfUnits = function(_, category)
        if category.Name == "STRUCTURE*MASSEXTRACTION" then return extractors end
        return {}
    end,
}
local span = environment.BaseSpan(spanBrain)
assert(span.Bases == 1, "one registered base, got " .. span.Bases)
assert(span.Inside == 2 and span.Outside == 1,
    "two extractors inside the base radius and one beyond every base, got "
        .. span.Inside .. "/" .. span.Outside)

print("Red Queen defence coverage contracts passed")
