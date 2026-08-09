function shortPath = getShortDisplayPath(~, folderPath)
    if isempty(folderPath)
        shortPath = '<no folder>';
        return
    end

    pathParts = regexp(folderPath, '[\\/]+', 'split');
    pathParts = pathParts(~cellfun(@isempty, pathParts));
    if numel(pathParts) <= 2
        shortPath = folderPath;
    else
        shortPath = fullfile('...', pathParts{end-1}, pathParts{end});
    end
end

