-- Refuse a hostile engineer assignment instead of walking into it.
--
-- Native `EngineerMoveWithSafePath` asks for a threat-constrained path and,
-- when there is none, returns true regardless -- the comment in the shipped
-- source says the direct move "would have been" issued and leaves the build
-- command to take the engineer there. Observed in a match as engineers
-- travelling into the enemy base, and reproduced against that source.
--
-- Returning false is the signal the native callers already understand: the
-- assignment is abandoned rather than performed at a walk into fire.
--
-- Hooked here rather than in platoon.lua, which is where a first attempt put it
-- and where it took down the whole simulation: the function is *used* there as
-- `AIUtils.EngineerMoveWithSafePath` but *defined* here, so capturing the bare
-- global in platoon.lua read a name that does not exist in that file's
-- environment. `system/config.lua` installs a strict metatable that raises on
-- exactly that, which aborted the import of platoon.lua and crashed the sim
-- before the first frame. Hook the file that defines the symbol.
--
-- Scoped to Red Queen brains by the same marker the platoon thread hook uses.
-- This function is global to every AI in the simulation, so an unguarded change
-- here would alter the opponents Red Queen is measured against.
local EngineerSurvival = import("/mods/TheRedQueen/lua/AI/RedQueen/EngineerSurvival.lua")
local Logger = import("/mods/TheRedQueen/lua/AI/RedQueen/Logger.lua")
local NativeEngineerMoveWithSafePath = EngineerMoveWithSafePath
EngineerMoveWithSafePath = function(aiBrain, unit, destination)
    if aiBrain and aiBrain.RedQueenLobbyPersonality then
        local allowed, reason = EngineerSurvival.RouteVerdict(aiBrain, unit, destination)
        if not allowed then
            -- Rate-limited by reason so a contested map cannot fill the log.
            -- RouteVerdict has already counted this refusal, so the running
            -- total is read from there instead of kept a second time here; the
            -- count itself is reported as `engsurvival=` in the state line,
            -- because "it happened at least once" was all this line ever said.
            if EngineerSurvival.EventCount(aiBrain, "Refused", reason) <= 1 then
                Logger.Info(aiBrain, "engineer assignment refused reason=" .. tostring(reason))
            end
            return false
        end
    end
    return NativeEngineerMoveWithSafePath(aiBrain, unit, destination)
end
