function refreshUI(obj)
    % refreshUI(obj)
    % Reload all visible controls from the current Protocol state.
    % Use after loading a protocol or after external model changes.
    obj.refreshParameterTab();
    obj.refreshOptionsTab();
    obj.refreshCompiledPreview();

    % Update figure title with current protocol version
    ver = obj.Protocol.meta.protocolVersion;
    if isempty(ver)
        obj.Figure.Name = 'Protocol Designer';
    else
        obj.Figure.Name = sprintf('Protocol Designer  [%s]', ver);
    end

    interfaceCount = length(obj.Protocol.Interfaces);
    if interfaceCount == 0
        obj.setStatus('New protocol ready');
    elseif obj.Protocol.COMPILED.ntrials > 0
        obj.setStatus(sprintf('Loaded %d interface(s) and %d compiled trial(s)', interfaceCount, obj.Protocol.COMPILED.ntrials), ...
            'Review the preview table or save the protocol.');
    else
        obj.setStatus(sprintf('Loaded %d interface(s)', interfaceCount));
    end
end

