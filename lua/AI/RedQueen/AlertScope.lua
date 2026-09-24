-- How far a defence alert reaches.
--
-- A defence alert is a *place*: a cluster of hostiles near one anchor. It was
-- being consumed as an army-wide boolean, and on a large map it latches --
-- measured across the twelve-cell control matrix, the four LandLarge cells
-- spend 71% to 83% of the match alerted and the last alert never clears, while
-- the two cells that win spend 17% and 62%. Everything keyed on `alert.Active`
-- therefore switched off for three quarters of a losing match: the Tech 2 and
-- Tech 3 upgrade conditions, every extractor upgrade, every factory assistant,
-- and the strategic focus. Land Tech 3 is reached in none of the logged
-- matches.
--
-- This is the extent test the rest of that work needs. `ProductionManager`
-- already had it inline for engineer leases; this is the same geometry, in one
-- place, so the remaining consumers can ask the same question.
local Constants = import("/mods/TheRedQueen/lua/AI/RedQueen/Constants.lua")

local function DistanceSquared(a, b)
    local dx = a[1] - b[1]
    local dz = a[3] - b[3]
    return dx * dx + dz * dz
end

-- Whether the alert reaches this position.
--
-- An alert with no anchor has no known extent, so it covers the army -- which
-- is exactly what every caller did before this was scoped, and keeps the old
-- behaviour wherever nothing better is known.
function CoversPosition(alert, position)
    if not alert or not alert.Active then
        return false
    end
    if not alert.AnchorPosition or not position then
        return true
    end
    local radius = Constants.Policy.DefenseAlertWorkRadius
    return DistanceSquared(position, alert.AnchorPosition) <= radius * radius
end

function CoversUnit(alert, unit)
    if not alert or not alert.Active then
        return false
    end
    if not unit or not unit.GetPosition then
        return true
    end
    return CoversPosition(alert, unit:GetPosition())
end

-- Whether the alert reaches every one of these units.
--
-- For a decision that owns a set rather than one unit: it is blocked only when
-- the alert is on top of the whole set, because an alert at one extractor is no
-- reason to stop upgrading the one at home. An empty or absent set has no known
-- extent and falls back to the alert's own state.
function CoversAll(alert, units)
    if not alert or not alert.Active then
        return false
    end
    if units == nil then
        return true
    end
    for _, unit in pairs(units) do
        if not CoversUnit(alert, unit) then
            return false
        end
    end
    -- Either the set is empty, or the alert is on top of all of it.
    return true
end
