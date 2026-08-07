function focusParameterFind(obj)
% focusParameterFind(obj)
% Move keyboard focus to the parameter Find box (Ctrl+F).
    if isempty(obj.EditFindParam) || ~isvalid(obj.EditFindParam)
        return
    end

    focus(obj.EditFindParam);
    obj.setStatus('Find parameter by name', ...
        'Type part of a name, use * and ? as wildcards, or press Ctrl+H to rename matches.');
end
