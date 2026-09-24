local ManagerNames = { "EngineerManager", "FactoryManager", "PlatoonFormManager" }

function Enabled(brain)
    return brain and brain.RedQueenLobbyPersonality ~= nil
end

function Live(brain, location, expected)
    if brain.RedQueenCleaned then return false end
    local base = brain.BuilderManagers and brain.BuilderManagers[location]
    if not base or base.RedQueenRetired or (expected and base ~= expected) then return false end
    for _, name in ipairs(ManagerNames) do
        local manager = base[name]
        if not manager or manager.RedQueenRetired or manager.Destroyed then return false end
    end
    return true
end

local function Emit(brain, state, location, generation)
    local trace = brain.RedQueenModules and brain.RedQueenModules.ProductionTrace
    if trace then
        trace:Safe(trace.Observe, "lifecycle", location .. ":" .. tostring(generation), state,
            string.format("location=%q generation=%s", location, tostring(generation)))
    end
end

function Retire(brain, location, base)
    if not base or base.RedQueenRetired then return end
    base.RedQueenRetired = true
    for _, name in ipairs(ManagerNames) do
        local manager = base[name]
        if manager then
            manager.RedQueenRetired = true
            for _, data in pairs(manager.BuilderData or {}) do
                for _, builder in pairs(data.Builders or {}) do
                    builder.RedQueenRetired = true
                    builder.Priority = 0
                end
            end
        end
    end
    local production = brain.RedQueenModules and brain.RedQueenModules.Production
    if production and production.CounterBuildersRegistered[location] == base then
        production.CounterBuildersRegistered[location] = nil
    end
    Emit(brain, "base-retirement", location, base.RedQueenGeneration)
end

function Register(brain, location, base)
    if not base or base.RedQueenGeneration then return end
    brain.RedQueenBaseGeneration = (brain.RedQueenBaseGeneration or 0) + 1
    base.RedQueenGeneration = brain.RedQueenBaseGeneration
    brain.RedQueenBaseLocations = brain.RedQueenBaseLocations or {}
    brain.RedQueenBaseLocations[location] = true
    for _, name in ipairs(ManagerNames) do
        local manager = base[name]
        if manager and manager.Destroy then
            local original = manager.Destroy
            manager.Destroy = function(current)
                Retire(brain, location, base)
                return original(current)
            end
        end
    end
    Emit(brain, "base-registration", location, base.RedQueenGeneration)
end

function Cleanup(brain)
    for location, base in pairs(brain.BuilderManagers or {}) do Retire(brain, location, base) end
end

-- Shared keyed conditions remain in the native cache. Their liveness follows
-- the current base, while builders themselves retain their original generation.
function ConditionLive(condition)
    local brain = condition.Brain
    if not Enabled(brain) then return true end
    if brain.RedQueenCleaned then condition.Status = false; return false end
    local signature = ""
    for _, value in ipairs(condition.FunctionData or condition.FunctionParameters or {}) do
        if type(value) == "string" and ((brain.RedQueenBaseLocations or {})[value]
            or string.sub(value, 1, 5) == "RQFB_") then
            if not Live(brain, value) then condition.Status = false; condition.CheckTime = false; return false end
            local base = brain.BuilderManagers[value]
            signature = signature .. ":" .. tostring(base.RedQueenGeneration)
        end
    end
    if signature ~= condition.RedQueenGenerationSignature then
        condition.CheckTime = false
        condition.Status = false
        condition.RedQueenGenerationSignature = signature
    end
    return true
end
