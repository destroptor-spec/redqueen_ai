local sent = {}
function SyncAIChat(data) table.insert(sent, data) end
local currentTick = 0
function GetGameTick() return currentTick end

local policy = { NarrateToChat = true, NarrationIntervalSeconds = 8 }
function import(path)
    if path == "/mods/TheRedQueen/lua/AI/RedQueen/Constants.lua" then
        return { Policy = policy }
    end
    error("unexpected import: " .. tostring(path))
end

local narrator = setmetatable({}, { __index = _G })
setfenv(assert(loadfile("lua/AI/RedQueen/Narrator.lua")), narrator)()

local brain = { Nickname = "Red Queen" }
assert(narrator.Announce(brain, "objective", "Raiding"), "the first thing said is news")
assert(table.getn(sent) == 1 and sent[1].text == "Raiding", "and reaches the chat")
assert(sent[1].sender == "Red Queen", "attributed to the army saying it")

-- The same thing twice is not news, however long ago it was said.
currentTick = 10000
assert(not narrator.Announce(brain, "objective", "Raiding"), "repeats are not narrated")
assert(table.getn(sent) == 1, "and nothing more is sent")

-- A different thing still waits its turn, so the chat window stays readable.
-- The interval runs from the last thing actually said, not the last attempt:
-- a suppressed repeat must not push the next real message further out.
currentTick = 20000
assert(narrator.Announce(brain, "objective", "Pressing"), "a fresh message is said")
currentTick = 20010
assert(not narrator.Announce(brain, "objective", "Defending"),
    "a new message inside the interval must wait")
currentTick = 20000 + policy.NarrationIntervalSeconds * 10
assert(narrator.Announce(brain, "objective", "Defending"), "and is said once the interval passes")

-- Categories are throttled independently: a defence alert must not be silenced
-- by an objective change a second earlier.
currentTick = currentTick + 1
assert(narrator.Announce(brain, "defence", "Under attack"),
    "each category carries its own throttle")

-- State lives on the brain, because an import is shared across every army in
-- the simulation and module-level state would let one Red Queen silence another.
local other = { Nickname = "Second" }
assert(narrator.Announce(other, "objective", "Defending"),
    "another army's narration is its own")

policy.NarrateToChat = false
currentTick = currentTick + 1000
assert(not narrator.Announce(brain, "objective", "Something new"),
    "narration must be switchable off outright")
policy.NarrateToChat = true

print("Red Queen narrator contracts passed")
