local Constants = import("/mods/TheRedQueen/lua/AI/RedQueen/Constants.lua")
local Logger = import("/mods/TheRedQueen/lua/AI/RedQueen/Logger.lua")

local Boards = {}

local function TeamKey(context)
    local parts = {}
    for _, armyIndex in pairs(context.AlliedArmies) do
        table.insert(parts, tostring(armyIndex))
    end
    return table.concat(parts, ":")
end

local function IsAlive(brain)
    return brain and brain.Status ~= "Defeat" and brain.Status ~= "Recalled"
end

local function DistanceSquared(a, b)
    local dx = a[1] - b[1]
    local dz = a[3] - b[3]
    return dx * dx + dz * dz
end

---@class RedQueenTeamCoordinator
TeamCoordinator = ClassSimple {
    __init = function(self, brain, context)
        self.Brain = brain
        self.Context = context
        self.Key = TeamKey(context)
        self.LastTransferTick = -100000

        local board = Boards[self.Key]
        if not board then
            board = {
                Members = {},
                ExpansionClaims = {},
                AttackProposals = {},
                SupportRequests = {},
            }
            Boards[self.Key] = board
        end
        self.Board = board
        board.Members[brain.Army] = {
            Brain = brain,
            RegisteredTick = GetGameTick(),
            LastUpdateTick = GetGameTick(),
        }
    end,

    Destroy = function(self)
        if self.Board then
            self.Board.Members[self.Brain.Army] = nil
            self.Board.AttackProposals[self.Brain.Army] = nil
            self.Board.SupportRequests[self.Brain.Army] = nil
        end
    end,

    Update = function(self, economy, intel, world)
        local tick = GetGameTick()
        local member = self.Board.Members[self.Brain.Army]
        if member then
            member.LastUpdateTick = tick
            member.EconomyMode = economy.State.Mode
            member.Surplus = economy.State.Surplus
        end

        local localThreat = intel:GetThreatNear(world.StartPosition, math.max(120, world.Width / 12))
        if localThreat > 25 then
            self.Board.SupportRequests[self.Brain.Army] = {
                Army = self.Brain.Army,
                Position = world.StartPosition,
                Threat = localThreat,
                ExpiresTick = tick + 300,
            }
        else
            self.Board.SupportRequests[self.Brain.Army] = nil
        end

        self:CleanExpired(tick)
        self:TryResourceAssistance(economy, tick)
    end,

    CleanExpired = function(self, tick)
        for clusterId, claim in pairs(self.Board.ExpansionClaims) do
            if claim.ExpiresTick < tick or not IsAlive(ArmyBrains[claim.Army]) then
                self.Board.ExpansionClaims[clusterId] = nil
            end
        end
        for army, proposal in pairs(self.Board.AttackProposals) do
            if proposal.ExpiresTick < tick or not IsAlive(ArmyBrains[army]) then
                self.Board.AttackProposals[army] = nil
            end
        end
        for army, request in pairs(self.Board.SupportRequests) do
            if request.ExpiresTick < tick or not IsAlive(ArmyBrains[army]) then
                self.Board.SupportRequests[army] = nil
            end
        end
    end,

    TryResourceAssistance = function(self, economy, tick)
        local cooldown = Constants.Policy.ResourceTransferCooldownSeconds * 10
        if tick - self.LastTransferTick < cooldown or not economy:HasResourceSurplus() then
            return
        end

        local donor = self.Brain
        local donorMassRatio = donor:GetEconomyStoredRatio("MASS") or 0
        local donorEnergyRatio = donor:GetEconomyStoredRatio("ENERGY") or 0

        for _, allyArmy in pairs(self.Context.AlliedArmies) do
            if allyArmy ~= donor.Army then
                local ally = ArmyBrains[allyArmy]
                if IsAlive(ally) then
                    local massFraction = 0
                    local energyFraction = 0
                    if donorMassRatio >= Constants.Policy.ResourceSurplusRatio
                        and (ally:GetEconomyStoredRatio("MASS") or 0) <= Constants.Policy.AllyDistressRatio
                    then
                        massFraction = Constants.Policy.ResourceTransferFraction
                    end
                    if donorEnergyRatio >= Constants.Policy.ResourceSurplusRatio
                        and (ally:GetEconomyStoredRatio("ENERGY") or 0) <= Constants.Policy.AllyDistressRatio
                    then
                        energyFraction = Constants.Policy.ResourceTransferFraction
                    end

                    if massFraction > 0 or energyFraction > 0 then
                        local mass = donor:TakeResource("MASS", massFraction * donor:GetEconomyStored("MASS")) or 0
                        local energy = donor:TakeResource("ENERGY", energyFraction * donor:GetEconomyStored("ENERGY")) or 0
                        ally:GiveResource("MASS", mass)
                        ally:GiveResource("ENERGY", energy)
                        self.LastTransferTick = tick
                        Logger.Info(donor, string.format("assisted ally=%d mass=%.1f energy=%.1f", allyArmy, mass, energy))
                        return
                    end
                end
            end
        end
    end,

    ClaimExpansion = function(self, clusterId)
        self.Board.ExpansionClaims[clusterId] = {
            Army = self.Brain.Army,
            ExpiresTick = GetGameTick() + Constants.Policy.ExpansionClaimSeconds * 10,
        }
    end,

    IsExpansionClaimedByOther = function(self, clusterId)
        local claim = self.Board.ExpansionClaims[clusterId]
        return claim and claim.Army ~= self.Brain.Army and claim.ExpiresTick >= GetGameTick()
    end,

    PublishAttack = function(self, objective)
        if not objective or not objective.Position then
            self.Board.AttackProposals[self.Brain.Army] = nil
            return
        end
        self.Board.AttackProposals[self.Brain.Army] = {
            Army = self.Brain.Army,
            Position = objective.Position,
            Layer = objective.Layer,
            Type = objective.Type,
            Priority = objective.Priority,
            LaunchTick = GetGameTick() + 100,
            ExpiresTick = GetGameTick() + Constants.Policy.AttackProposalSeconds * 10,
        }
    end,

    GetCoordinatedAttack = function(self)
        local best = nil
        for army, proposal in pairs(self.Board.AttackProposals) do
            if army ~= self.Brain.Army and proposal.ExpiresTick >= GetGameTick() then
                if not best or proposal.Priority > best.Priority then
                    best = proposal
                end
            end
        end
        return best
    end,

    GetSupportRequest = function(self, origin)
        local best = nil
        local bestScore = nil
        for army, request in pairs(self.Board.SupportRequests) do
            if army ~= self.Brain.Army then
                local distance = math.sqrt(DistanceSquared(origin, request.Position))
                local score = request.Threat - distance * 0.02
                if not bestScore or score > bestScore then
                    best = request
                    bestScore = score
                end
            end
        end
        return best
    end,
}

function Create(brain, context)
    return TeamCoordinator(brain, context)
end
