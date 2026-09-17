-- Ownership of temporary guard orders, shared with native engineer assignment.
-- A lease never authorizes clearing a newer platoon, queue, or guard target.
local function Alive(unit)
    return unit and not unit.Dead and (not unit.BeenDestroyed or not unit:BeenDestroyed())
end

function Unclaimed(unit, record)
    return Alive(unit) and unit.RedQueenAssist == record
        and (not unit.GetArmy or unit:GetArmy() == record.Army)
        and unit.PlatoonHandle == record.Platoon
        and table.getn(unit.EngineerBuildQueue or {}) == 0
end

function Owns(unit, record)
    if not record or not Unclaimed(unit, record) then return false end
    return unit.GetGuardedUnit and unit:GetGuardedUnit() == record.Target
end

function Resume(unit)
    local manager = unit.BuilderManagerData and unit.BuilderManagerData.EngineerManager
    if manager and manager.DelayAssign then manager:DelayAssign(unit, 50) end
end

function Release(unit, record, resume)
    if not record or unit.RedQueenAssist ~= record then return false end
    local owned = Owns(unit, record)
    local idle = Unclaimed(unit, record) and unit.IsIdleState and unit:IsIdleState()
    unit.RedQueenAssist = nil
    unit.RedQueenAssistUntil = nil
    unit.RedQueenIdleAssistUntil = nil
    if owned then IssueClearCommands({ unit }) end
    if owned or idle then
        record.Released = true
        -- Give the native manager a real assignment opportunity before another
        -- opportunistic assist. Custom emergency/expansion jobs may take it now.
        unit.RedQueenAssistRetryTick = GetGameTick() + 50
        if resume then Resume(unit) end
    end
    return owned or idle
end

function Start(unit, target, seconds, kind, objective, fallback)
    local record = {
        Unit = unit, Target = target, Kind = kind, Objective = objective,
        Fallback = fallback, Tick = GetGameTick(),
        Until = GetGameTick() + seconds * 10,
        Army = unit.GetArmy and unit:GetArmy(), Platoon = unit.PlatoonHandle,
    }
    IssueGuard({ unit }, target)
    unit.RedQueenAssist = record
    if kind == "Commander" then unit.RedQueenAssistUntil = record.Until
    else unit.RedQueenIdleAssistUntil = record.Until end
    -- The native hook retains a valid lease and resumes work on expiry, even
    -- if the production scheduler has not run in the meantime.
    Resume(unit)
    return record
end

function HoldNative(unit)
    local record = unit and unit.RedQueenAssist
    if not record then return false end
    local pending = GetGameTick() <= record.Tick + 1 and Unclaimed(unit, record)
    if record.Until > GetGameTick() and Alive(record.Target)
        and (Owns(unit, record) or pending)
    then return true end
    Release(unit, record, false)
    return false
end
