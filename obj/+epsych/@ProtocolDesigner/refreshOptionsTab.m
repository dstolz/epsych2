function refreshOptionsTab(obj)
    if isempty(obj.EditTrialFunc) || ~isvalid(obj.EditTrialFunc)
        return
    end
    obj.EditTrialFunc.Value = obj.Protocol.Options.trialFunc;
    obj.CheckCompileAtRuntime.Value = obj.Protocol.Options.compileAtRuntime;
    obj.CheckIncludeWAVBuffers.Value = obj.Protocol.Options.IncludeWAVBuffers;
end

