function errorEntries = validatePairedParameterLengths(obj)
    % validatePairedParameterLengths(obj)
    % Collect validation errors for pair groups whose value counts differ.
    %
    % Returns:
    % 	errorEntries	- Struct array with per-parameter mismatch messages.
    parameters = obj.getAllParameters();
    pairGroups = struct('name', {}, 'parameters', {}, 'memberNames', {}, 'valueCounts', {});

    for paramIdx = 1:numel(parameters)
        parameter = parameters(paramIdx);
        pairName = obj.getParameterPair(parameter);
        if isempty(pairName)
            continue
        end

        valueCount = localGetParameterValueCount_(parameter.Value);
        memberName = localGetParameterDisplayName_(parameter);
        groupIdx = find(strcmp({pairGroups.name}, pairName), 1);
        if isempty(groupIdx)
            pairGroups(end + 1).name = pairName; %#ok<AGROW>
            pairGroups(end).parameters = {parameter};
            pairGroups(end).memberNames = {memberName};
            pairGroups(end).valueCounts = valueCount;
        else
            pairGroups(groupIdx).parameters{end + 1} = parameter;
            pairGroups(groupIdx).memberNames{end + 1} = memberName;
            pairGroups(groupIdx).valueCounts(end + 1) = valueCount;
        end
    end

    errorEntries = struct('parameter', {}, 'message', {});
    for groupIdx = 1:numel(pairGroups)
        valueCounts = pairGroups(groupIdx).valueCounts;
        if isempty(valueCounts) || all(valueCounts == valueCounts(1))
            continue
        end

        memberSummary = arrayfun(@(idx) sprintf('%s (%d)', ...
            pairGroups(groupIdx).memberNames{idx}, double(valueCounts(idx))), ...
            1:numel(pairGroups(groupIdx).memberNames), 'UniformOutput', false);
        message = sprintf('Pair mismatch for %s: paired parameters must have the same number of values: %s', ...
            pairGroups(groupIdx).name, strjoin(memberSummary, ', '));

        for memberIdx = 1:numel(pairGroups(groupIdx).parameters)
            errorEntries(end + 1).parameter = pairGroups(groupIdx).parameters{memberIdx}; %#ok<AGROW>
            errorEntries(end).message = message;
        end
    end
end

function valueCount = localGetParameterValueCount_(value)
    if isnumeric(value) || islogical(value)
        if isempty(value) || isscalar(value)
            valueCount = 1;
        else
            valueCount = numel(reshape(value, 1, []));
        end
        return
    end

    if isstring(value)
        valueCount = max(1, numel(value));
        return
    end

    if ischar(value)
        valueCount = 1;
        return
    end

    if iscell(value)
        if isempty(value)
            valueCount = 1;
        else
            valueCount = numel(reshape(value, 1, []));
        end
        return
    end

    valueCount = 1;
end

function memberName = localGetParameterDisplayName_(parameter)
    try
        memberName = sprintf('%s.%s', parameter.Module.Name, parameter.Name);
    catch
        memberName = char(string(parameter.Name));
    end
end