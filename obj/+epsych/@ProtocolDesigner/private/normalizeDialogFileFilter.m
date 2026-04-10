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
end