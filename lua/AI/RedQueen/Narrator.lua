local Constants = import("/mods/TheRedQueen/lua/AI/RedQueen/Constants.lua")

-- What Red Queen is doing, said out loud for a spectator.
--
-- The logs describe every decision but only after the match, and a behaviour
-- that looks wrong on screen is far easier to recognise than to find in
-- thirty thousand lines. This narrates the handful of decisions that change
-- what the army is visibly doing.
--
-- SyncAIChat only appends to the Sync table, which the UI drains -- no
-- simulation state and no random draw, so narration cannot change a result.
-- Resolved lazily through pcall because reading a global that does not exist
-- raises under the strict metatable and would abort the brain.
local function Send(brain, text)
    local ok, sync = pcall(function() return SyncAIChat end)
    if not ok or type(sync) ~= "function" then
        return false
    end
    sync({
        group = "all",
        text = text,
        sender = brain.Nickname or "Red Queen",
    })
    return true
end

-- Throttled per category and per brain. Per brain because an import is shared
-- across every army in the simulation, so module-level state would let one
-- Red Queen silence another.
function Announce(brain, category, text)
    if not Constants.Policy.NarrateToChat or not brain or not text then
        return false
    end
    local tick = GetGameTick()
    brain.RedQueenNarration = brain.RedQueenNarration or {}
    local last = brain.RedQueenNarration[category]
    if last then
        -- The same thing twice is not news, however long ago it was said, and
        -- a different thing still waits its turn so the window stays readable.
        if last.Text == text then
            return false
        end
        if tick - last.Tick < Constants.Policy.NarrationIntervalSeconds * 10 then
            return false
        end
    end
    if not Send(brain, text) then
        return false
    end
    brain.RedQueenNarration[category] = { Tick = tick, Text = text }
    return true
end
