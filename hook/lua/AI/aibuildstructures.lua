-- Does the engine's resource threat filter actually refuse ground here?
--
-- `AIExecuteBuildStructure` places mass extractors through
--     aiBrain:FindPlaceToBuild(..., 'Enemy', x, z, 5)
-- and every other structure in the game through the same call with the filter
-- left at its default of 0, "accept all". Per FAForever/fa engine/Sim/CAiBrain.lua
-- the trailing argument is `optIgnoreThreatOver`: a candidate deposit is
-- considered only while its ring-0 anti-surface threat influence is below it.
-- Extractors are therefore the one structure refused on contested ground, by the
-- engine, and for resource builder types the engine ignores the base template
-- and queries the deposits directly -- so this is the only spatial gate deciding
-- which deposit is offered at all.
--
-- Whether it *binds* in these matches is a separate question, and the ring-0
-- threat influence is not on the same scale as the `GetThreatNear` values Red
-- Queen's own policy is tuned against, so it cannot be settled by eye. This
-- probe settles it by asking the engine both ways and returning the gated
-- answer: the filtered result is what native receives, so **no decision
-- changes**, while the counterfactual says how many deposits the filter was
-- refusing. Red Queen's route guard is left armed for the same reason.
--
-- Hooked here rather than anywhere that merely calls it: `lua/AI/aibuildstructures.lua`
-- is the file that defines `AIExecuteBuildStructure` and `IsResource`, and
-- `system/config.lua`'s strict metatable aborts the import of any file that
-- captures a global it does not define.
--
-- Scoped to Red Queen brains. This function is global to every AI in the
-- simulation, so an unguarded change here would alter the opponents Red Queen
-- is measured against.
local NativeAIExecuteBuildStructure = AIExecuteBuildStructure

local function InstallPlacementProbe(aiBrain)
    if rawget(aiBrain, "RedQueenPlacementProbe") then
        return
    end
    local NativeFindPlaceToBuild = aiBrain.FindPlaceToBuild
    if not NativeFindPlaceToBuild then
        return
    end
    aiBrain.RedQueenPlacementProbe = true
    aiBrain.RedQueenPlacement = { Attempts = 0, Gated = 0, Open = 0 }
    aiBrain.FindPlaceToBuild = function(self, buildType, structureName, templates,
        relative, builder, alliance, positionX, positionZ, threatLimit)
        local located = NativeFindPlaceToBuild(self, buildType, structureName,
            templates, relative, builder, alliance, positionX, positionZ, threatLimit)
        -- Only the resource call carries a threat limit; every other structure
        -- leaves it nil, so this cannot mistake a factory for a deposit.
        if threatLimit and threatLimit > 0 then
            local counts = self.RedQueenPlacement
            if counts then
                counts.Attempts = counts.Attempts + 1
                if located then
                    counts.Gated = counts.Gated + 1
                end
                local open = NativeFindPlaceToBuild(self, buildType, structureName,
                    templates, relative, builder, alliance, positionX, positionZ, 0)
                if open then
                    counts.Open = counts.Open + 1
                end
            end
        end
        return located
    end
end

AIExecuteBuildStructure = function(aiBrain, builder, buildingType, closeToBuilder,
    relative, buildingTemplate, baseTemplate, reference, NearMarkerType)
    if aiBrain and aiBrain.RedQueenLobbyPersonality and IsResource(buildingType) then
        InstallPlacementProbe(aiBrain)
    end
    return NativeAIExecuteBuildStructure(aiBrain, builder, buildingType,
        closeToBuilder, relative, buildingTemplate, baseTemplate, reference,
        NearMarkerType)
end
