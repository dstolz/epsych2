function refreshUI(obj)
    % refreshUI(obj)
    % Reload all tabs from the current Protocol state.
    % Use after loading a protocol or after external model changes.
    obj.EditInfo.Value = obj.Protocol.Info;
    obj.refreshParameterTab();
    obj.refreshOptionsTab();
    obj.refreshCompiledPreview();
end

