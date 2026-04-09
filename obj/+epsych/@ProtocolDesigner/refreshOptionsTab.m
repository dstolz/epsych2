function refreshOptionsTab(obj)
    obj.EditTrialFunc.Value = obj.Protocol.Options.trialFunc;
    obj.EditISI.Value = obj.Protocol.Options.ISI;
    obj.CheckCompileAtRuntime.Value = obj.Protocol.Options.compileAtRuntime;
    obj.CheckIncludeWAVBuffers.Value = obj.Protocol.Options.IncludeWAVBuffers;
end

