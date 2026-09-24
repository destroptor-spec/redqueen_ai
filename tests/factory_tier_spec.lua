-- A factory must not build an engineer below its own tier.
--
-- Native BuilderParamCheck asks only whether the factory *can* build the
-- template, and a Tech 2 factory can build a Tech 1 engineer perfectly well --
-- so it did, observed directly in a match. These contracts exercise the shipped
-- hook, including the cases that must keep working: a surviving Tech 1 factory
-- still builds Tech 1 engineers, and other AIs are left alone.
categories = setmetatable({}, {
    __index = function(value, key)
        local category = { Name = key }
        rawset(value, key, category)
        return category
    end,
})

function EntityCategoryContains(category, unit)
    return (unit.Categories or {})[category.Name] == true
end

__blueprints = {
    uel0105 = { CategoriesHash = { ENGINEER = true, TECH1 = true, MOBILE = true } },
    uel0208 = { CategoriesHash = { ENGINEER = true, TECH2 = true, MOBILE = true } },
    uel0309 = { CategoriesHash = { ENGINEER = true, TECH3 = true, MOBILE = true } },
    uel0301 = { CategoriesHash = { ENGINEER = true, SUBCOMMANDER = true, TECH3 = true } },
    uel0201 = { CategoriesHash = { MOBILE = true, LAND = true, TECH1 = true } },
    ual0105 = { CategoriesHash = { ENGINEER = true, TECH1 = true, MOBILE = true } },
}

local TEMPLATES = {
    T1BuildEngineer = { "T1BuildEngineer", "", { "uel0105", 1, 1, "support", "None" } },
    T2BuildEngineer = { "T2BuildEngineer", "", { "uel0208", 1, 1, "support", "None" } },
    T3BuildEngineer = { "T3BuildEngineer", "", { "uel0309", 1, 1, "support", "None" } },
    RedQueenSupportCommander = { "RedQueenSupportCommander", "", { "uel0301", 1, 1 } },
    T1LandDFTank = { "T1LandDFTank", "", { "uel0201", 1, 1 } },
    -- A captured factory of another faction resolves to that faction's
    -- engineer, which is why the template is looked up against the factory.
    CapturedT1BuildEngineer = { "T1BuildEngineer", "", { "ual0105", 1, 1 } },
    -- Native returns a two-entry template when the faction has no squad.
    Missing = { "Missing", "" },
    Mixed = { "Mixed", "", { "uel0201", 1, 1 }, { "uel0105", 1, 1 } },
}

-- Stand-in for the native manager. `GetFactoryTemplate` resolves against the
-- factory, and the native check is recorded so the hook can be shown to call
-- through rather than replace it.
nativeCalls = 0
FactoryBuilderManager = {
    BuilderParamCheck = function(self, builder, params)
        nativeCalls = nativeCalls + 1
        return self.NativeVerdict ~= false
    end,
    GetFactoryTemplate = function(self, name, factory)
        if factory and factory.Faction == "Aeon" and name == "T1BuildEngineer" then
            return TEMPLATES.CapturedT1BuildEngineer
        end
        return TEMPLATES[name]
    end,
}

setfenv(assert(loadfile("hook/lua/sim/FactoryBuilderManager.lua")), getfenv())()

local function factory(tech, faction)
    return { Categories = { [tech] = true, STRUCTURE = true, FACTORY = true }, Faction = faction }
end
local function builderFor(template)
    return { GetPlatoonTemplate = function() return template end }
end
local function check(brainIsRedQueen, tech, template, nativeVerdict, faction)
    local manager = {
        Brain = { RedQueenLobbyPersonality = brainIsRedQueen and "redqueen" or nil },
        NativeVerdict = nativeVerdict,
        GetFactoryTemplate = FactoryBuilderManager.GetFactoryTemplate,
    }
    return FactoryBuilderManager.BuilderParamCheck(
        manager, builderFor(template), { factory(tech, faction) })
end

-- The defect: a Tech 2 factory selecting the Tech 1 engineer.
assert(not check(true, "TECH2", "T1BuildEngineer"),
    "a Tech 2 factory must not build a Tech 1 engineer")
assert(not check(true, "TECH3", "T1BuildEngineer"),
    "a Tech 3 factory must not build a Tech 1 engineer")
assert(not check(true, "TECH3", "T2BuildEngineer"),
    "a Tech 3 factory must not build a Tech 2 engineer")

assert(not check(true, "TECH2", "Mixed"), "all native squads must obey the engineer floor")

-- A factory building its own tier, or better, is untouched.
assert(check(true, "TECH1", "T1BuildEngineer"),
    "a surviving Tech 1 factory must still build Tech 1 engineers")
assert(check(true, "TECH2", "T2BuildEngineer"), "a Tech 2 factory may build its own engineer")
assert(check(true, "TECH3", "T3BuildEngineer"), "a Tech 3 factory may build its own engineer")
assert(check(true, "TECH2", "T3BuildEngineer"),
    "a higher-tier engineer must never be refused for being too good")

-- The rule is about the tiered engineer line only.
assert(check(true, "TECH3", "RedQueenSupportCommander"),
    "a support commander is not a tiered engineer and must not be refused")
assert(check(true, "TECH3", "T1LandDFTank"),
    "combat production must be untouched by an engineer tier rule")
assert(check(true, "TECH2", "Missing"),
    "an absent faction squad is native's own refusal, not ours to duplicate")

-- Captured factories resolve through the factory, so the rule uses the
-- blueprint that would actually be produced.
assert(not check(true, "TECH2", "T1BuildEngineer", nil, "Aeon"),
    "a captured Tech 2 factory must not build the other faction's Tech 1 engineer")

-- Other AIs are left exactly as they were: this method serves every brain in
-- the simulation, and Red Queen is measured against those opponents.
assert(check(false, "TECH2", "T1BuildEngineer"),
    "a non-Red Queen brain must keep native behaviour")

-- And the hook narrows, never widens: a native refusal stands.
local before = nativeCalls
assert(not check(true, "TECH1", "T1BuildEngineer", false),
    "a native refusal must not be overturned")
assert(nativeCalls == before + 1, "the native check must be called through, not replaced")

print("Red Queen factory engineer tier contracts passed")
