function onOptionControlChanged(obj)
    trialFuncName = char(string(obj.EditTrialFunc.Value));
    obj.Protocol.setOption('trialFunc', trialFuncName);
    obj.Protocol.setOption('ISI', obj.EditISI.Value);
    obj.Protocol.setOption('compileAtRuntime', obj.CheckCompileAtRuntime.Value);
    obj.Protocol.setOption('IncludeWAVBuffers', obj.CheckIncludeWAVBuffers.Value);
    trialFuncWarning = obj.getTrialFunctionPathWarning(trialFuncName);
    if isempty(trialFuncWarning)
        obj.LabelStatus.Text = 'Options updated';
    else
        obj.LabelStatus.Text = trialFuncWarning;
    end
end

