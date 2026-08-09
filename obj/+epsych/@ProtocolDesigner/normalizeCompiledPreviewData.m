function previewData = normalizeCompiledPreviewData(obj, rawData, columnTypes)
    if isempty(rawData)
        previewData = cell(0, 0);
        return
    end

    if nargin < 3 || isempty(columnTypes)
        columnTypes = repmat({''}, 1, size(rawData, 2));
    end

    if ~iscell(rawData)
        rawData = num2cell(rawData);
    end

    previewData = rawData;
    for rowIdx = 1:size(rawData, 1)
        for colIdx = 1:size(rawData, 2)
            previewData{rowIdx, colIdx} = obj.normalizeCompiledPreviewValue(rawData{rowIdx, colIdx}, columnTypes{colIdx});
        end
    end
end

