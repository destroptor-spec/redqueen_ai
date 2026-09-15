local RedQueenSurvival = import("/mods/TheRedQueen/lua/AI/RedQueen/EngineerSurvival.lua")
local NativeAssignEngineerTask = EngineerManager.AssignEngineerTask

EngineerManager.AssignEngineerTask = function(self, unit)
    if self.Brain and self.Brain.RedQueenLobbyPersonality
        and RedQueenSurvival.IsRetreating(unit)
    then
        self:DelayAssign(unit, 50)
        return
    end
    return NativeAssignEngineerTask(self, unit)
end
