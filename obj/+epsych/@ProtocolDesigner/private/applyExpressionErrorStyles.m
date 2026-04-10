function applyExpressionErrorStyles(obj)
    try
        removeStyle(obj.TableParams);
    catch
    end

    if isempty(obj.ParameterHandles)
        return
    end

    colorMode = localGetColorMode_(obj);
    switch lower(colorMode)
        case 'interface'
            localApplyCategoricalRowStyles_(obj, localGetTableColumn_(obj.TableParams.Data, 1));
        case 'module'
            localApplyCategoricalRowStyles_(obj, localGetTableColumn_(obj.TableParams.Data, 2));
        otherwise
            localApplyTypeRowStyles_(obj);
    end

    userData = obj.TableParams.UserData;
    if isempty(userData) || ~isstruct(userData) || ~isfield(userData, 'ExpressionErrors')
        return
    end

    errorEntries = userData.ExpressionErrors;
    if isempty(errorEntries)
        return
    end

    errorRows = [];
    for rowIdx = 1:numel(obj.ParameterHandles)
        parameter = obj.ParameterHandles{rowIdx};
        if ~isempty(obj.getExpressionErrorMessage(parameter))
            errorRows = [errorRows, rowIdx];
        end
    end

    if isempty(errorRows)
        return
    end

    style = uistyle('BackgroundColor', [1.0 0.88 0.88], 'FontColor', [0.60 0.00 0.00]);
    addStyle(obj.TableParams, style, 'row', errorRows);
end

function colorMode = localGetColorMode_(obj)
    colorMode = 'Type';
    if ~isprop(obj, 'DropDownColorBy') || isempty(obj.DropDownColorBy)
        return
    end

    try
        colorMode = char(string(obj.DropDownColorBy.Value));
    catch
        colorMode = 'Type';
    end
end

function values = localGetTableColumn_(tableData, columnIndex)
    if isempty(tableData)
        values = {};
        return
    end

    values = tableData(:, columnIndex);
    values = cellfun(@(value) char(string(value)), values, 'UniformOutput', false);
end

function localApplyTypeRowStyles_(obj)
    parameterTypes = cellfun(@(parameter) char(string(parameter.Type)), obj.ParameterHandles, 'UniformOutput', false);
    typeStyles = localParameterTypeStyles_();
    for styleIdx = 1:size(typeStyles, 1)
        rowIndices = find(strcmpi(parameterTypes, typeStyles{styleIdx, 1}));
        if isempty(rowIndices)
            continue
        end

        style = uistyle( ...
            'BackgroundColor', typeStyles{styleIdx, 2}, ...
            'FontColor', typeStyles{styleIdx, 3});
        addStyle(obj.TableParams, style, 'row', rowIndices);
    end
end

function localApplyCategoricalRowStyles_(obj, groupValues)
    if isempty(groupValues)
        return
    end

    palette = localCategoricalPalette_();
    uniqueGroups = unique(groupValues, 'stable');
    for groupIdx = 1:numel(uniqueGroups)
        rowIndices = find(strcmp(groupValues, uniqueGroups{groupIdx}));
        if isempty(rowIndices)
            continue
        end

        paletteIdx = mod(groupIdx - 1, size(palette, 1)) + 1;
        style = uistyle( ...
            'BackgroundColor', palette{paletteIdx, 1}, ...
            'FontColor', palette{paletteIdx, 2});
        addStyle(obj.TableParams, style, 'row', rowIndices);
    end
end

function typeStyles = localParameterTypeStyles_()
    typeStyles = {
    'Float', [0.89 0.98 0.96], [0.08 0.42 0.35];
    'Integer', [1.00 0.95 0.84], [0.50 0.31 0.06];
    'Boolean', [0.92 0.98 0.86], [0.21 0.44 0.11];
    'Buffer', [1.00 0.91 0.87], [0.60 0.23 0.11];
    'Coefficient Buffer', [0.98 0.90 0.95], [0.50 0.18 0.38];
    'String', [0.89 0.95 1.00], [0.14 0.34 0.57];
    'File', [0.93 0.92 1.00], [0.29 0.23 0.60];
    'Undefined', [0.95 0.96 0.97], [0.37 0.40 0.44]
        };
end

function palette = localCategoricalPalette_()
    palette = {
    [0.90 0.96 1.00], [0.11 0.33 0.54];
    [0.91 0.98 0.92], [0.16 0.42 0.18];
    [1.00 0.94 0.86], [0.52 0.29 0.07];
    [0.96 0.91 0.99], [0.45 0.19 0.49];
    [1.00 0.91 0.92], [0.55 0.18 0.24];
    [0.93 0.95 1.00], [0.25 0.25 0.59];
    [0.94 0.97 0.88], [0.34 0.43 0.08];
    [0.98 0.92 0.88], [0.54 0.24 0.11]
    };
end

