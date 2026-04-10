function pairDisplay = getPairDisplayValue(obj, parameter)
    pairDisplay = obj.getParameterPair(parameter);
    if isempty(pairDisplay)
        pairDisplay = '<None>';
    end
end