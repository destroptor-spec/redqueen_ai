-- Match-scoped controls for isolating scouting mechanisms. The launch overlay
-- carries the choice in synchronized scenario options; ordinary games keep
-- both mechanisms. Never mutate the shared Constants or terrain profiles.
local Modes = {
    combined = { AdaptiveProduction = true, DirectedDispatch = true },
    ["production-only"] = { AdaptiveProduction = true, DirectedDispatch = false },
    ["dispatch-only"] = { AdaptiveProduction = false, DirectedDispatch = true },
}

function Create(options)
    local mode = "combined"
    if options and options.RedQueenScoutingMode ~= nil then
        mode = options.RedQueenScoutingMode
    end
    local selected = Modes[mode]
    assert(selected, "Unknown RedQueenScoutingMode: " .. tostring(mode))
    return {
        Mode = mode,
        AdaptiveProduction = selected.AdaptiveProduction,
        DirectedDispatch = selected.DirectedDispatch,
    }
end
