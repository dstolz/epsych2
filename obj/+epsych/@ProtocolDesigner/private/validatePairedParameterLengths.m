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

        valueCount = localGetParameterValueCount_(parameter.Values);
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

function valueCount = localGetParameterValueCount_(values)
    % Count design-time trial levels the same way protocol compilation does
    % (see Protocol.expand_cross_product / normalizeParameterValuesForTrials_):
    % hw.Parameter.Values is a cell with one element per level, and an empty
    % level set expands to a single trial. Counting Values here—rather than the
    % runtime scalar Value—keeps the paired-length check consistent with compile,
    % which otherwise falsely flags e.g. an Integer whose Value holds the array
    % against a String whose Value holds a single level.
    if iscell(values)
        valueCount = max(1, numel(values));
        return
    end

    % Defensive fallback for non-cell Values (not expected in normal use).
    if isnumeric(values) || islogical(values) || isstring(values)
        valueCount = max(1, numel(values));
    else
        valueCount = 1;
    end
end

function memberName = localGetParameterDisplayName_(parameter)
    try
        memberName = sprintf('%s.%s', parameter.Module.Name, parameter.Name);
    catch
        memberName = char(string(parameter.Name));
    end
end