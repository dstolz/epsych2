function refreshUI(obj)
    % refreshUI(obj)
    % Reload all visible controls from the current Protocol state.
    % Use after loading a protocol or after external model changes.
    obj.refreshParameterTab();
    obj.refreshOptionsTab();
    obj.refreshCompiledPreview();
end

