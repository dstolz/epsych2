function pairName = promptForNewPairName(obj)
    existingOptions = obj.getPairDropdownOptions();
    existingPairNames = setdiff(existingOptions, {'<None>', '<Create Pair...>'}, 'stable');

    answer = inputdlg({'Pair Name'}, 'Create Pair', 1, {''});
    if isempty(answer)
        pairName = '';
        return
    end

    pairName = strtrim(answer{1});
    if isempty(pairName)
        error('Pair name cannot be empty.');
    end
    if any(strcmp(pairName, {'<None>', '<Create Pair...>'}))
        error('Pair name cannot use a reserved dropdown label.');
    end
    if any(strcmp(pairName, existingPairNames))
        error('Pair "%s" already exists. Select it from the dropdown instead.', pairName);
    end
end