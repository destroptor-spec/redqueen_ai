local originalCalls = 0

function CDROverCharge()
    originalCalls = originalCalls + 1
end

SimUnitEnhancements = {}

dofile("hook/lua/AI/AIBehaviors.lua")

local commander = { EntityId = 10 }
local redQueenBrain = { RedQueenContext = {} }

CDROverCharge(redQueenBrain, commander)
assert(originalCalls == 0, "unupgraded Red Queen commander must not enter overcharge combat")

SimUnitEnhancements[commander.EntityId] = { Back = "ResourceAllocation" }
CDROverCharge(redQueenBrain, commander)
assert(originalCalls == 1, "upgraded Red Queen commander may use maintained combat behavior")

SimUnitEnhancements[commander.EntityId] = nil
CDROverCharge({}, commander)
assert(originalCalls == 2, "commander gate must not alter other AI brains")

print("Red Queen commander safety contracts passed")
