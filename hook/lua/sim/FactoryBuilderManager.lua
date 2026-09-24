-- A factory must not build an engineer below its own tier.
--
-- Native `BuilderParamCheck` asks only whether the factory *can* build the
-- template, and a Tech 2 factory can build a Tech 1 engineer perfectly well --
-- so it does, which was observed directly in a match. Red Queen's own engineer
-- builders cannot prevent it either: a `BuilderConditions` function receives
-- only the brain, never the factory, and general tier obsolescence exempts the
-- `Utility` role, which is where engineers and scouts live.
--
-- The decision belongs here because this is the only place that knows both the
-- factory and the blueprint it would produce. `GetFactoryTemplate` resolves the
-- template against the factory, so a captured factory of another faction
-- resolves to that faction's engineer.
--
-- Deliberately a floor, not a switch: a *surviving* Tech 1 factory keeps
-- building Tech 1 engineers. A global "highest tier only" rule would silence
-- that fallback exactly when an army has lost its better factories and most
-- needs the cheap ones.
--
-- Scoped to Red Queen brains. This method serves every AI in the simulation and
-- an unguarded change would alter the opponents Red Queen is measured against.
local function UnitTech(unit)
    if not unit or not EntityCategoryContains then
        return nil
    end
    if EntityCategoryContains(categories.TECH3, unit) then
        return 3
    end
    if EntityCategoryContains(categories.TECH2, unit) then
        return 2
    end
    if EntityCategoryContains(categories.TECH1, unit) then
        return 1
    end
    return nil
end

-- The tier of the unit a template would produce, and whether it is an engineer
-- at all. Read from the blueprint rather than the template's name: the name is
-- a Red Queen convention, while the blueprint is what the factory builds.
local function TemplateEngineerTech(template)
    if type(template) ~= "table" then
        return nil
    end
    local lowest = nil
    -- FAF reserves entries 1 and 2 for the template name and plan placeholder.
    for index = 3, table.getn(template) do
        local squad = template[index]
        local blueprintId = type(squad) == "table" and squad[1] or nil
        local blueprint = type(blueprintId) == "string" and __blueprints and __blueprints[blueprintId]
        local hash = blueprint and blueprint.CategoriesHash
        if hash and hash.ENGINEER then
            local tech = hash.TECH3 and 3 or hash.TECH2 and 2 or hash.TECH1 and 1 or nil
            if tech then lowest = math.min(lowest or tech, tech) end
        end
    end
    return lowest
end

local NativeBuilderParamCheck = FactoryBuilderManager.BuilderParamCheck
FactoryBuilderManager.BuilderParamCheck = function(self, builder, params)
    if not NativeBuilderParamCheck(self, builder, params) then
        return false
    end
    local brain = self.Brain
    if not brain or not brain.RedQueenLobbyPersonality then
        return true
    end
    local factory = params and params[1]
    if not factory or not builder or not builder.GetPlatoonTemplate then
        return true
    end
    local factoryTech = UnitTech(factory)
    if not factoryTech then
        return true
    end
    local template = self:GetFactoryTemplate(builder:GetPlatoonTemplate(), factory)
    local engineerTech = TemplateEngineerTech(template)
    if engineerTech and engineerTech < factoryTech then
        return false
    end
    return true
end
