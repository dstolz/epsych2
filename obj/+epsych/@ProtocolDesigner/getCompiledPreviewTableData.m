function [columnNames, columnTypes, tableData] = getCompiledPreviewTableData(obj, maxRows)
% [columnNames, columnTypes, tableData] = getCompiledPreviewTableData(obj, maxRows)
% Build normalized compiled-trial table data ordered by informativeness.
%
% Parameters:
% 	maxRows	- Maximum number of rows to return (default: inf for all rows).
%
% Returns:
% 	columnNames	- Ordered display names for compiled columns.
% 	columnTypes	- Ordered parameter types matching columnNames.
% 	tableData	- Normalized cell matrix suitable for uitable/cell2table.
    if nargin < 2 || isempty(maxRows)
        maxRows = inf;
    end

    parameters = obj.Protocol.COMPILED.parameters;
    trials = obj.Protocol.COMPILED.trials;

    if isempty(parameters)
        columnNames = {'No Compiled Trials'};
        columnTypes = {'String'};
        tableData = cell(0, 1);
        return
    end

    columnTypes = {parameters.Type};
    columnNames = {parameters.Name};

    columnOrder = localRankCompiledColumns_(obj, trials, columnTypes);
    columnNames = columnNames(columnOrder);
    columnTypes = columnTypes(columnOrder);

    rowCount = size(trials, 1);
    if isinf(maxRows)
        rowsToInclude = rowCount;
    else
        rowsToInclude = min(rowCount, max(0, floor(double(maxRows))));
    end

    if rowsToInclude <= 0
        tableData = cell(0, numel(columnOrder));
        return
    end

    rawData = trials(1:rowsToInclude, columnOrder);
    tableData = obj.normalizeCompiledPreviewData(rawData, columnTypes);
end

function columnOrder = localRankCompiledColumns_(obj, trials, columnTypes)
% columnOrder = localRankCompiledColumns_(obj, trials, columnTypes)
% Rank columns so highly varying columns are shown first.
    nCols = size(trials, 2);
    if nCols <= 1
        columnOrder = 1:nCols;
        return
    end

    sampleRows = min(size(trials, 1), 500);
    if sampleRows <= 1
        columnOrder = 1:nCols;
        return
    end

    sampleData = trials(1:sampleRows, :);
    scores = zeros(1, nCols);

    for colIdx = 1:nCols
        normalizedValues = strings(sampleRows, 1);
        for rowIdx = 1:sampleRows
            normalizedValues(rowIdx) = string(obj.normalizeCompiledPreviewValueAsText(sampleData{rowIdx, colIdx}, columnTypes{colIdx}));
        end

        uniqueCount = numel(unique(normalizedValues));
        nonMissingFrac = mean(strlength(strtrim(normalizedValues)) > 0);
        isVarying = uniqueCount > 1;

        % Varying columns are generally more informative in large trial tables.
        scores(colIdx) = double(isVarying) * 1000 + double(uniqueCount) + nonMissingFrac;
    end

    sortMatrix = [-scores(:), (1:nCols)'];
    sortedRows = sortrows(sortMatrix, [1 2]);
    columnOrder = sortedRows(:, 2).';
end
