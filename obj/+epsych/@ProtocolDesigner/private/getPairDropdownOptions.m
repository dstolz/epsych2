function options = getPairDropdownOptions(obj)
    options = {'<None>'};
    parameters = obj.getAllParameters();
    if isempty(parameters)
        options = [options, {'<Create Pair...>'}];
        return
    end

    pairNames = cell(1, numel(parameters));
    keepMask = false(1, numel(parameters));
    for idx = 1:numel(parameters)
        pairName = obj.getParameterPair(parameters(idx));
        if isempty(pairName)
            continue
        end
        pairNames{idx} = pairName;
        keepMask(idx) = true;
    end

    pairNames = unique(pairNames(keepMask), 'stable');
    options = [options, pairNames, {'<Create Pair...>'}];
end