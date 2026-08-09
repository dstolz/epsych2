function refreshOptionsTab(obj)
% refreshOptionsTab(obj)
% Sync protocol options from the model into the tab controls.
    if isempty(obj.EditTrialFunc) || ~isvalid(obj.EditTrialFunc)
        return
    end
    obj.EditTrialFunc.Value = obj.Protocol.Options.trialFunc;
    obj.CheckCompileAtRuntime.Value = obj.Protocol.Options.compileAtRuntime;
    obj.CheckIncludeWAVBuffers.Value = obj.Protocol.Options.IncludeWAVBuffers;
end

