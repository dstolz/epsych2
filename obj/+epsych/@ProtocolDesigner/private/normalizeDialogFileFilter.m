function fileFilter = normalizeDialogFileFilter(~, fileFilter)
    if isempty(fileFilter)
        fileFilter = {'*.*', 'All Files (*.*)'};
        return
    end

    while iscell(fileFilter) && isscalar(fileFilter) && iscell(fileFilter{1})
        fileFilter = fileFilter{1};
    end

    if isstring(fileFilter)
        fileFilter = cellstr(fileFilter);
    end

    if iscell(fileFilter) && size(fileFilter, 2) == 1 && numel(fileFilter) == 2
        fileFilter = reshape(fileFilter, 1, []);
    end

    if ~iscell(fileFilter) || size(fileFilter, 2) ~= 2
        return
    end

    patterns = cellfun(@(value) char(string(value)), fileFilter(:, 1), 'UniformOutput', false);
    isAllFiles = cellfun(@localIsAllFilesPattern_, patterns);
    if any(~isAllFiles)
        fileFilter = fileFilter(~isAllFiles, :);
    end
end

function tf = localIsAllFilesPattern_(pattern)
    pattern = strtrim(lower(char(string(pattern))));
    tf = strcmp(pattern, '*') || strcmp(pattern, '*.*');
end