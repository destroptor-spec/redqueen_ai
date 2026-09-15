local scouting = setmetatable({}, { __index = _G })
setfenv(assert(loadfile("lua/AI/RedQueen/ScoutingConfig.lua")), scouting)()

local defaults = scouting.Create()
assert(defaults.Mode == "combined" and defaults.AdaptiveProduction and defaults.DirectedDispatch,
    "ordinary games must keep both scouting mechanisms")
local production = scouting.Create({ RedQueenScoutingMode = "production-only" })
assert(production.AdaptiveProduction and not production.DirectedDispatch,
    "production-only must disable directed dispatch")
local dispatch = scouting.Create({ RedQueenScoutingMode = "dispatch-only" })
assert(not dispatch.AdaptiveProduction and dispatch.DirectedDispatch,
    "dispatch-only must restore binary production")
production.DirectedDispatch = true
assert(not scouting.Create({ RedQueenScoutingMode = "production-only" }).DirectedDispatch,
    "each brain must receive its own configuration")
for _, invalid in ipairs({ "", "production", "off", true, false, 7 }) do
    assert(not pcall(scouting.Create, { RedQueenScoutingMode = invalid }),
        "unknown modes must fail rather than silently testing the default")
end
assert(scouting.Create({}).Mode == "combined", "absent options retain the default")

print("Red Queen scouting configuration contracts passed")
