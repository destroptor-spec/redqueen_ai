local Logger = import("/mods/TheRedQueen/lua/AI/RedQueen/Logger.lua")

-- Development-only opt-in. Alternatively set the synchronized scenario option
-- RedQueenProductionTrace=true. Never infer activation from local wall time.
Enabled = false

local function Alive(unit)
    return unit and not unit.Dead and (not unit.BeenDestroyed or not unit:BeenDestroyed())
end

local function Id(unit)
    return unit and (unit.EntityId or (unit.GetEntityId and unit:GetEntityId())) or "none"
end

local function Blueprint(unit)
    return Alive(unit) and unit.GetBlueprint and unit:GetBlueprint() or {}
end

local function Position(unit)
    local pos = Alive(unit) and unit.GetPosition and unit:GetPosition()
    return pos and string.format("%.1f,%.1f", pos[1], pos[3]) or "none"
end

local function SortedKeys(values)
    local keys = {}
    for key, _ in pairs(values or {}) do table.insert(keys, key) end
    table.sort(keys)
    return keys
end

local function Queue(unit)
    local queue = unit.EngineerBuildQueue or {}
    local head = queue[1] or {}
    local pos = head[2]
    -- Native build-queue coordinates are x,z,orientation (not x,y,z).
    return string.format("%d:%s:%s", table.getn(queue), tostring(head[1] or "none"),
        pos and string.format("%.1f,%.1f", pos[1], pos[2]) or "none")
end

ProductionTrace = ClassSimple {
    __init = function(self, brain, modules)
        self.Brain = brain
        self.Modules = modules
        self.Subsystems = {}
        self.Engineers = {}
        self.Requests = {}
        self.Sequence = 0
        self.LastSample = -100000
        self.Entities = { placement = {}, projects = {} }
        self.EntitySequence = 0
        self.Stopped = false
        self:Emit("start", string.format("map=%q faction=%s", tostring(ScenarioInfo and ScenarioInfo.name),
            tostring(brain.RedQueenContext and brain.RedQueenContext.FactionIndex)))
    end,

    Emit = function(self, event, detail)
        Logger.Info(self.Brain, string.format("production trace tick=%d event=%s %s", GetGameTick(), event, detail))
    end,

    Safe = function(self, method, ...)
        if self.Stopped then return end
        local ok, failure = pcall(method, self, unpack(arg))
        if not ok and not self.FailureReported then
            self.FailureReported = true
            Logger.Warning(self.Brain, "production trace unavailable: " .. tostring(failure))
        end
    end,

    TaskFlags = function(self, unit)
        local flags = {}
        for _, name in ipairs({ "UnitBeingBuilt", "UnitBeingAssist", "UnitBeingBuiltBehavior", "Combat",
            "ForkedEngineerTask", "ProcessBuild", "NotBuildingThread", "GoingHome" }) do
            local value = unit[name]
            if value then
                table.insert(flags, name .. ":" .. ((type(value) == "table" or type(value) == "userdata")
                    and tostring(Id(value)) or tostring(value)))
            end
        end
        return table.concat(flags, ",")
    end,

    EnabledFor = function(self, subsystem)
        local options = ScenarioInfo and ScenarioInfo.Options or {}
        local selected = options.RedQueenTraceSubsystems
        return not selected or selected[subsystem] == true
    end,

    Observe = function(self, subsystem, key, state, detail)
        if self.Stopped or not self:EnabledFor(subsystem) then return end
        local bucket = self.Subsystems[subsystem]
        if not bucket then
            bucket = { States = {}, Count = 0, Counters = {}, Overflow = 0 }
            self.Subsystems[subsystem] = bucket
        end
        bucket.Counters[state] = (bucket.Counters[state] or 0) + 1
        if state == "evaluated:selection" then return end
        if not bucket.States[key] and bucket.Count >= 64 then
            bucket.Overflow = bucket.Overflow + 1
            return
        end
        if not bucket.States[key] then bucket.Count = bucket.Count + 1 end
        if bucket.States[key] ~= state then
            bucket.States[key] = state
            self:Emit(subsystem, "state=" .. state .. " " .. (detail or ""))
        end
    end,

    Flush = function(self)
        for _, name in ipairs(SortedKeys(self.Subsystems)) do
            local bucket = self.Subsystems[name]
            for _, state in ipairs(SortedKeys(bucket.Counters)) do
                self:Emit("aggregate", string.format("subsystem=%s state=%s count=%d", name, state, bucket.Counters[state]))
            end
            if bucket.Overflow > 0 then
                self:Emit("overflow", string.format("subsystem=%s count=%d coverage=incomplete", name, bucket.Overflow))
            end
            -- Decision identities are scoped to one sampling interval. No
            -- lifetime history or unit references accumulate in these maps.
            bucket.States = {}
            bucket.Count = 0
            bucket.Counters = {}
            bucket.Overflow = 0
        end
    end,

    UnitStarted = function(self, builder, unit)
        local hash = Blueprint(unit).CategoriesHash or {}
        local subsystem = hash.EXPERIMENTAL and "projects" or hash.FACTORY and "placement"
        if not subsystem or not self:EnabledFor(subsystem) then return end
        local entities = self.Entities[subsystem]
        if entities[unit] then return end
        local count = 0
        for _ in pairs(entities) do count = count + 1 end
        if count >= 64 then
            self:Observe(subsystem, "entity-overflow", "overflow", "coverage=incomplete")
            return
        end
        self.EntitySequence = self.EntitySequence + 1
        local manager = builder and builder.BuilderManagerData and builder.BuilderManagerData.EngineerManager
        local record = { Lifetime = self.EntitySequence, Builder = builder, Tick = GetGameTick(), Progress = 0,
            Location = manager and manager.LocationType or "unknown" }
        if subsystem == "placement" then
            local position = unit.GetPosition and unit:GetPosition()
            for _, request in ipairs(self.Requests) do
                local entry = request.Entry
                local point = entry and entry[2]
                if request.Unit == builder and entry and entry[1] == Blueprint(unit).BlueprintId and position and point
                    and math.abs(position[1] - point[1]) < 2 and math.abs(position[3] - point[2]) < 2 then
                    record.Request = request.Id
                    request.Construction = record.Lifetime
                    break
                end
            end
        end
        entities[unit] = record
        self:Emit("construction-start", string.format("subsystem=%s unit=%s lifetime=%d builder=%s manager=%q position=%s request=%s",
            subsystem, tostring(Id(unit)), record.Lifetime, tostring(Id(builder)), record.Location, Position(unit), tostring(record.Request or "unmatched")))
    end,

    Terminal = function(self, unit, outcome)
        for _, subsystem in ipairs({ "placement", "projects" }) do
            local record = self.Entities[subsystem][unit]
            if record then
                self:Emit("construction-outcome", string.format("subsystem=%s unit=%s lifetime=%d outcome=%s age=%.1f request=%s",
                    subsystem, tostring(Id(unit)), record.Lifetime, outcome, (GetGameTick() - record.Tick) / 10, tostring(record.Request or "unmatched")))
                self.Entities[subsystem][unit] = nil
            end
        end
    end,

    UnitCompleted = function(self, unit, builder)
        self:Terminal(unit, "completed")
        local bp = Blueprint(unit)
        local hash = bp.CategoriesHash or {}
        if self:EnabledFor("placement") and (hash.ENGINEER or hash.FACTORY) then
            self:Observe("placement", tostring(Id(unit)), "completed", string.format("unit=%s blueprint=%s engineer=%s factory=%s position=%s",
                tostring(Id(unit)), tostring(bp.BlueprintId), tostring(hash.ENGINEER or false), tostring(hash.FACTORY or false), Position(unit)))
        end
    end,

    UnitLost = function(self, unit)
        self:Terminal(unit, "destroyed")
        local hash = (unit.GetBlueprint and unit:GetBlueprint() or {}).CategoriesHash or {}
        if hash.COMMAND then self:Observe("lifecycle", "acu", "acu-loss", "unit=" .. tostring(Id(unit))) end
        if hash.ENGINEER or hash.FACTORY then
            self:Observe("placement", tostring(Id(unit)), "lost", "unit=" .. tostring(Id(unit)))
        end
    end,

    SampleEntities = function(self)
        for _, subsystem in ipairs({ "placement", "projects" }) do
            for unit, record in pairs(self.Entities[subsystem]) do
                if not Alive(unit) then
                    self:Terminal(unit, "unknown")
                else
                    local progress = unit.GetFractionComplete and unit:GetFractionComplete() or 0
                    local state = self.Modules.Economy.State
                    local guards = unit.GetGuards and unit:GetGuards() or {}
                    local owner = record.Builder and record.Builder.BuilderManagerData and record.Builder.BuilderManagerData.EngineerManager
                    local health = unit.GetHealth and unit:GetHealth() or 0
                    local nearby = self.Modules.Intel and self.Modules.Intel.GetThreatNear
                        and self.Modules.Intel:GetThreatNear(unit:GetPosition(), 60, "Land") or 0
                    self:Emit("construction-progress", string.format("subsystem=%s unit=%s lifetime=%d progress=%.4f delta=%.4f position=%s manager=%q builder=%s builderAlive=%s target=%s assistants=%d mass=%.2f energy=%.2f health=%s observedThreat=%.1f damageDelta=%.1f currentManager=%q storedMass=%s storedEnergy=%s stall=%s",
                        subsystem, tostring(Id(unit)), record.Lifetime, progress, progress - record.Progress, Position(unit),
                        record.Location, tostring(Id(record.Builder)), tostring(Alive(record.Builder)),
                        tostring(Id(record.Builder and record.Builder.UnitBeingBuilt)), table.getn(guards),
                        state.MassIncome or 0, state.EnergyIncome or 0, tostring(health), nearby, math.max(0, (record.Health or health) - health),
                        tostring(owner and owner.LocationType), tostring(state.MassStoredRatio), tostring(state.EnergyStoredRatio), tostring(state.StallRisk)))
                    record.Health = health
                    record.Progress = progress
                    if progress >= 1 then self:Terminal(unit, "completed") end
                end
            end
        end
    end,

    ExpansionAttempt = function(self, unit, buildingType, started, requestedEntry)
        if not self:EnabledFor("placement") then return end
        self.Sequence = self.Sequence + 1
        self:Emit("expansion", string.format("request=%d unit=%s type=%s accepted=%s queue=%q position=%s",
            self.Sequence, tostring(Id(unit)), buildingType, tostring(started), Queue(unit), Position(unit)))
        if requestedEntry then
            local pos = requestedEntry[2]
            self:Emit("request-placement", string.format("request=%d blueprint=%s position=%.1f,%.1f", self.Sequence,
                tostring(requestedEntry[1]), pos[1], pos[2]))
        end
        if started then
            if table.getn(self.Requests) >= 64 then
                self:Observe("placement", "request-overflow", "overflow", "coverage=incomplete")
                return
            end
            local tail = requestedEntry
            table.insert(self.Requests, { Id = self.Sequence, Unit = unit, Tick = GetGameTick(), Entry = tail })
        end
    end,

    ExpansionBlocked = function(self, reason)
        if not self:EnabledFor("placement") then return end
        if self.LastBlock ~= reason or GetGameTick() - (self.LastBlockTick or -100000) >= 600 then
            self:Emit("expansion-blocked", "reason=" .. reason)
            self.LastBlock = reason
            self.LastBlockTick = GetGameTick()
        end
    end,

    Sample = function(self)
        local production = self.Modules.Production
        local counts = production.Counts or {}
        local targets = production:GetFactoryTargets(counts)
        local deficit = (counts.Total or 0) < (targets.Total or 0)
        if not self:EnabledFor("placement") then return end
        local state = self.Modules.Economy.State
        local units = self.Brain:GetListOfUnits(categories.ENGINEER - categories.COMMAND, false) or {}
        table.sort(units, function(a, b) return Id(a) < Id(b) end)
        local present = {}
        local pending = { Land = 0, Air = 0, Naval = 0 }
        for _, unit in pairs(self.Brain:GetListOfUnits(categories.FACTORY * categories.STRUCTURE, false) or {}) do
            if Alive(unit) and unit.GetFractionComplete and unit:GetFractionComplete() < 1 then
                local hash = Blueprint(unit).CategoriesHash or {}
                local domain = hash.AIR and "Air" or hash.NAVAL and "Naval" or "Land"
                pending[domain] = pending[domain] + 1
            end
        end
        self:Emit("capacity", string.format("mass=%.2f energy=%.2f live=%d target=%d land=%d/%d/%d air=%d/%d/%d naval=%d/%d/%d engineers=%d",
            state.MassIncome, state.EnergyIncome, counts.Total or 0, targets.Total or 0,
            counts.Land or 0, pending.Land, targets.Land or 0, counts.Air or 0, pending.Air, targets.Air or 0,
            counts.Naval or 0, pending.Naval, targets.Naval or 0, table.getn(units)))
        for index, unit in ipairs(units) do
            if index > 64 then
                self:Observe("placement", "engineer-overflow", "overflow", "coverage=incomplete")
                break
            end
            if Alive(unit) then
                local id = Id(unit)
                present[id] = true
                local platoon = unit.PlatoonHandle
                local manager = unit.BuilderManagerData and unit.BuilderManagerData.EngineerManager
                local states = {}
                for _, name in ipairs({ "Building", "Moving", "Guarding", "Reclaiming", "Capturing", "Repairing", "Upgrading" }) do
                    if unit.IsUnitState and unit:IsUnitState(name) then table.insert(states, name) end
                end
                local detail = string.format("unit=%s manager=%s plan=%q builder=%q position=%s idle=%s states=%q flags=%q queue=%q target=%s progress=%s reservations=%s/%s/%s/%s",
                    tostring(id), tostring(manager and manager.LocationType), tostring(platoon and platoon.PlanName),
                    tostring(platoon and platoon.BuilderName), Position(unit), tostring(unit.IsIdleState and unit:IsIdleState()),
                    table.concat(states, ","), self:TaskFlags(unit), Queue(unit), tostring(Id(unit.UnitBeingBuilt)),
                    tostring(Alive(unit.UnitBeingBuilt) and unit.UnitBeingBuilt.GetFractionComplete and unit.UnitBeingBuilt:GetFractionComplete()),
                    tostring(unit.RedQueenProductionBuildUntil), tostring(unit.RedQueenFactoryAssistUntil),
                    tostring(production.ForwardBaseActive and production.ForwardBaseActive.Engineer == unit),
                    tostring(unit.RedQueenEmergencyDefenseUntil))
                local old = self.Engineers[id]
                if not old or old.Detail ~= detail or GetGameTick() - old.Tick >= 600 then
                    self:Emit("engineer", detail)
                    self.Engineers[id] = { Detail = detail, Tick = GetGameTick() }
                end
            end
        end
        for id, _ in pairs(self.Engineers) do
            if not present[id] then
                self:Emit("absent", "unit=" .. tostring(id) .. " reason=dead-or-transferred")
                self.Engineers[id] = nil
            end
        end
        local retained = {}
        for _, request in ipairs(self.Requests) do
            local status = "engineer-lost"
            if request.Construction then
                status = "construction-started"
            elseif Alive(request.Unit) then
                status = "queue-absent"
                for _, entry in ipairs(request.Unit.EngineerBuildQueue or {}) do
                    if entry == request.Entry then status = "queued" end
                end
            end
            if request.Status ~= status then
                self:Emit("request-state", string.format("request=%d unit=%s status=%s age=%.0f", request.Id,
                    tostring(Id(request.Unit)), status, (GetGameTick() - request.Tick) / 10))
                request.Status = status
            end
            if status == "queued" then
                if GetGameTick() - request.Tick < 6000 then table.insert(retained, request)
                else self:Emit("request-state", string.format("request=%d status=unknown-expired", request.Id)) end
            end
        end
        self.Requests = retained
    end,

    Update = function(self)
        if GetGameTick() - self.LastSample >= 300 then
            self.LastSample = GetGameTick()
            self:Safe(self.Sample)
            self:Safe(self.SampleEntities)
            self:Safe(self.Flush)
        end
    end,

    Destroy = function(self)
        for _, subsystem in ipairs({ "placement", "projects" }) do
            for unit in pairs(self.Entities[subsystem]) do self:Terminal(unit, "cleanup-unknown") end
        end
        self:Flush()
        self.Stopped = true
        self.Subsystems = {}
        self.Entities = { placement = {}, projects = {} }
        self.Engineers = {}
        self.Requests = {}
    end,
}

function Create(brain, modules)
    if Enabled or (ScenarioInfo and ScenarioInfo.Options and ScenarioInfo.Options.RedQueenProductionTrace == true) then
        local selected = ScenarioInfo.Options.RedQueenTraceArmy or 2
        if brain:GetArmyIndex() == selected then return ProductionTrace(brain, modules) end
    end
    return nil
end
