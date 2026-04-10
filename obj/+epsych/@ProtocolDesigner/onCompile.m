function onCompile(obj, alertTarget)
    if nargin < 2 || isempty(alertTarget)
        alertTarget = obj.Figure;
    end

    try
        obj.Protocol.compile();
        obj.refreshCompiledPreview();
        obj.setStatus(sprintf('Compiled %d trial(s)', obj.Protocol.COMPILED.ntrials), ...
            'Review the compiled preview below or save the protocol.');
    catch ME
        obj.showCompileFailure(ME, alertTarget);
    end
end

