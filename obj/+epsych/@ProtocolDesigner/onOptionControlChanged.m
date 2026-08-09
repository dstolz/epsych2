function onOptionControlChanged(obj)
% onOptionControlChanged(obj)
% Copy option control values into obj.Protocol.Options and refresh path warnings.
    trialFuncName = char(string(obj.EditTrialFunc.Value));
    obj.Protocol.setOption('trialFunc', trialFuncName);
    obj.Protocol.setOption('compileAtRuntime', obj.CheckCompileAtRuntime.Value);
    obj.Protocol.setOption('IncludeWAVBuffers', obj.CheckIncludeWAVBuffers.Value);
    obj.IsModified_ = true;
    trialFuncWarning = obj.getTrialFunctionPathWarning(trialFuncName);
    if isempty(trialFuncWarning)
        obj.setStatus('Protocol options updated', 'Compile to refresh the preview with the new settings.');
    else
        obj.setStatus(trialFuncWarning, 'Fix the trial function path or choose a callable function before compiling.');
    end
end

