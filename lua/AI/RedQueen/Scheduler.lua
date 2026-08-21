local Logger = import("/mods/TheRedQueen/lua/AI/RedQueen/Logger.lua")

---@class RedQueenScheduledTask
---@field Name string
---@field Interval number
---@field NextTick number
---@field Callback function

---@class RedQueenScheduler
---@field Brain AIBrain
---@field Tasks RedQueenScheduledTask[]
---@field Running boolean
Scheduler = ClassSimple {
    __init = function(self, brain)
        self.Brain = brain
        self.Tasks = {}
        self.Running = false
    end,

    Add = function(self, name, interval, offset, callback)
        table.insert(self.Tasks, {
            Name = name,
            Interval = math.max(1, interval),
            NextTick = GetGameTick() + (offset or 0),
            Callback = callback,
        })
    end,

    Start = function(self)
        if self.Running then
            return
        end
        self.Running = true
        local thread = ForkThread(self.Run, self)
        self.Brain.Trash:Add(thread)
    end,

    Stop = function(self)
        self.Running = false
    end,

    Run = function(self)
        while self.Running and self.Brain.Status == "InProgress" do
            local tick = GetGameTick()
            for taskIndex = 1, table.getn(self.Tasks) do
                local task = self.Tasks[taskIndex]
                if tick >= task.NextTick then
                    task.NextTick = tick + task.Interval
                    local ok, message = pcall(task.Callback)
                    if not ok then
                        Logger.Error(self.Brain, string.format("scheduler task '%s' failed: %s", task.Name, tostring(message)))
                    end
                end
            end
            WaitTicks(1)
        end
    end,
}

function Create(brain)
    return Scheduler(brain)
end
