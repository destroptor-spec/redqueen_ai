local lifecycle = {}
setmetatable(lifecycle, { __index = _G })
local chunk = assert(loadfile('lua/AI/RedQueen/BaseLifecycle.lua'))
setfenv(chunk, lifecycle)()
function import() return lifecycle end
local nativeChecks = 0
local function NativeCheck(self)
    nativeChecks = nativeChecks + 1
    assert(self.Brain.BuilderManagers[self.FunctionData[1]].EngineerManager)
    self.Status = true
    return true
end
local function ConditionClass()
    return { LocationExists = function() return true end, CheckCondition = NativeCheck, GetStatus = NativeCheck }
end
ImportCondition = ConditionClass()
InstantImportCondition = ConditionClass()
FunctionCondition = ConditionClass()
dofile('hook/lua/sim/BrainConditionsMonitor.lua')
Builder = {
    Create = function(self, brain) self.Brain = brain; self.Priority = 900; return true end,
    GetBuilderStatus = function() nativeChecks = nativeChecks + 1; return true end,
    CalculatePriority = function(self) self.Priority = 900; return true end,
}
dofile('hook/lua/sim/Builder.lua')
local brain = { RedQueenLobbyPersonality = 'redqueen', BuilderManagers = {} }
local function Base()
    local base = {}
    for _, name in ipairs({ 'EngineerManager', 'FactoryManager', 'PlatoonFormManager' }) do
        base[name] = { BuilderData = { Any = { Builders = {} } }, Destroy = function(self)
            assert(base.RedQueenRetired, 'retire before native destruction')
            self.Destroyed = true
        end }
    end
    return base
end
local old = Base()
brain.BuilderManagers.RQFB_1 = old
lifecycle.Register(brain, 'RQFB_1', old)
local builder = setmetatable({}, { __index = Builder })
builder:Create(brain, {}, 'RQFB_1')
table.insert(old.EngineerManager.BuilderData.Any.Builders, builder)
local cached = setmetatable({ Brain = brain, FunctionData = { 'RQFB_1' } }, { __index = ImportCondition })
local instant = setmetatable({ Brain = brain, FunctionData = { 'RQFB_1' } }, { __index = InstantImportCondition })
assert(cached:CheckCondition() and instant:GetStatus() and builder:GetBuilderStatus())
old.EngineerManager:Destroy()
local before = nativeChecks
assert(not cached:LocationExists() and not cached:CheckCondition() and not instant:GetStatus())
assert(not builder:GetBuilderStatus())
builder:CalculatePriority()
assert(builder.Priority == 0 and nativeChecks == before)
brain.BuilderManagers.RQFB_1 = nil
assert(not instant:GetStatus(), 'instant path must reject an absent location')
local replacement = Base()
brain.BuilderManagers.RQFB_1 = replacement
lifecycle.Register(brain, 'RQFB_1', replacement)
local production = { CounterBuildersRegistered = { RQFB_1 = replacement } }
brain.RedQueenModules = { Production = production }
old.FactoryManager:Destroy()
assert(production.CounterBuildersRegistered.RQFB_1 == replacement, 'old teardown cannot erase replacement')
assert(cached:CheckCondition() and instant:GetStatus(), 'shared keys must remain reusable')
assert(not builder:GetBuilderStatus(), 'old builder cannot use replacement generation')
local fresh = setmetatable({}, { __index = Builder })
fresh:Create(brain, {}, 'RQFB_1')
assert(fresh:GetBuilderStatus())
local saved = replacement.PlatoonFormManager
replacement.PlatoonFormManager = nil
assert(not cached:CheckCondition() and not instant:GetStatus(), 'partial managers are invalid')
replacement.PlatoonFormManager = saved
brain.RedQueenCleaned = true
lifecycle.Cleanup(brain)
before = nativeChecks
assert(not instant:GetStatus() and not cached:CheckCondition() and not fresh:GetBuilderStatus())
assert(nativeChecks == before, 'no evaluations during native brain cleanup')
lifecycle.Cleanup(brain)
local stock = { BuilderManagers = { MAIN = Base() } }
local stockCondition = setmetatable({ Brain = stock, FunctionData = { 'MAIN' } }, { __index = InstantImportCondition })
assert(stockCondition:GetStatus(), 'stock Adaptive follows native checks')
assert(not lifecycle.Enabled(stock))
print('Red Queen base lifecycle contracts passed')
