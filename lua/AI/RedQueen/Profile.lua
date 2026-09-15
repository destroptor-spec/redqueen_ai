-- Match profiles: which behaviours this brain runs, chosen from the options the
-- match actually presents.
--
-- Why this exists. Behaviour used to be one global policy with map conditionals
-- bolted on at the point of use. That reads as adaptive and is not: the
-- condition is a belief about what generalises, buried where nobody revisits
-- it. Scoping tier readiness by map size looked right on Sentry Point, Sludge
-- and Fields of Isis, and Syrtis Major -- the same size and terrain as Isis --
-- then moved the opposite way. The belief was wrong and the shape of the code
-- hid that it was a belief at all.
--
-- So selection is declarative and in one place. A profile names a set of
-- behaviours; the first whose condition matches wins; the choice is logged with
-- the inputs that produced it. Changing what a map class does is then a table
-- edit against a recorded baseline, not a hunt through call sites.
--
-- Constants.Policy is deliberately NOT mutated. It is one shared table for
-- every army in the simulation's Lua state -- the same hazard as the global
-- Builders table -- so an overlay there would leak between brains and, in a
-- mixed match, between Red Queen and its opponent. Values live on the brain and
-- fall back to Constants for everything a profile does not override.
local Constants = import("/mods/TheRedQueen/lua/AI/RedQueen/Constants.lua")
local Logger = import("/mods/TheRedQueen/lua/AI/RedQueen/Logger.lua")

-- Terrain selection, first match wins. Scale is applied independently below.
-- Keep the conditions cheap and pure: they run once
-- at brain start against a finished world model, and must not consult live
-- state, which would make the choice depend on when it was asked.
Profiles = {
    {
        Name = "Naval",
        Describe = "water-dominant map: contest the water, answer ships ashore",
        When = function(context, world)
            return world.MapType == "Naval"
        end,
        Flags = {
            NavalFirstTier = true,
            ShoreTorpedo = true,
            ShoreArtillery = true,
            TierReadinessObsolescence = false,
            TechEnergyLadder = true,
        },
    },
    {
        Name = "Mixed",
        Describe = "meaningful water beside a land route: keep both open",
        When = function(context, world)
            return world.MapType == "Mixed"
        end,
        Flags = {
            NavalFirstTier = true,
            ShoreTorpedo = true,
            ShoreArtillery = true,
            TierReadinessObsolescence = false,
            TechEnergyLadder = true,
        },
    },
    {
        Name = "LandSmall",
        Describe = "dry map decided before volume arrives: army quality first",
        When = function()
            return true
        end,
        Flags = {
            NavalFirstTier = false,
            ShoreTorpedo = false,
            ShoreArtillery = true,
            TierReadinessObsolescence = false,
            -- On with readiness off is the only configuration measured to win
            -- Sentry Point (K/L 0.96). Readiness on made it a defeat at 0.67,
            -- and turning the ladder off as well made it worse still at 0.42.
            TechEnergyLadder = true,
        },
    },
}

---@class RedQueenProfile
Profile = ClassSimple {
    __init = function(self, brain, context, world)
        self.Brain = brain
        self.Name = "LandSmall"
        self.Describe = ""
        self.Flags = {}
        self.Values = {}

        for _, candidate in ipairs(Profiles) do
            if candidate.When(context, world) then
                self.Name = candidate.Name
                self.Describe = candidate.Describe or ""
                for flag, value in pairs(candidate.Flags or {}) do
                    self.Flags[flag] = value
                end
                for name, value in pairs(candidate.Values or {}) do
                    self.Values[name] = value
                end
                break
            end
        end

        -- Scale applies to every terrain. Large water maps keep their naval
        -- counters and use completed higher-tier factories to retire obsolete
        -- production, just as large dry maps do. This is measured separately
        -- from the small-water doctrine; no shared policy table is mutated.
        self.Scale = "Small"
        if world.MapKilometers >= Constants.Policy.LargeMapKilometers then
            self.Scale = "Large"
            self.Name = self.Name == "LandSmall" and "LandLarge" or self.Name .. "Large"
            self.Describe = self.Describe .. "; large map: volume and completed-tier readiness"
            self.Flags.TierReadinessObsolescence = true
        end

        -- Log the inputs alongside the choice. A profile name on its own cannot
        -- be checked against a match; these four can.
        Logger.Info(brain, string.format(
            "profile selected=%s map=%s size=%dkm water=%.2f allies=%d enemies=%d flags=%s",
            self.Name,
            tostring(world.MapType),
            world.MapKilometers or 0,
            world.WaterRatio or 0,
            context.AlliedSideSize or 1,
            context.EnemyCount or 1,
            self:Summary()
        ))
    end,

    -- True only when the profile explicitly enables the behaviour. An unknown
    -- flag is off: a behaviour nobody assigned to a profile should not run.
    Flag = function(self, name)
        return self.Flags[name] == true
    end,

    -- Profile override if present, otherwise the shared policy value.
    Value = function(self, name)
        local override = self.Values[name]
        if override ~= nil then
            return override
        end
        return Constants.Policy[name]
    end,

    Summary = function(self)
        local names = {}
        for flag, value in pairs(self.Flags) do
            if value == true then
                table.insert(names, flag)
            end
        end
        table.sort(names)
        return table.getn(names) > 0 and table.concat(names, ",") or "none"
    end,
}

function Create(brain, context, world)
    return Profile(brain, context, world)
end
