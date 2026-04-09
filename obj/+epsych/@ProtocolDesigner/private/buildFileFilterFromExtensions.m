function fileFilter = buildFileFilterFromExtensions(~, extensions)
    extensions = cellstr(extensions);
    normalizedExtensions = cellfun(@(ext) regexprep(char(string(ext)), '^\.?', '.'), extensions, UniformOutput = false);
    pattern = strjoin(cellfun(@(ext) ['*' ext], normalizedExtensions, UniformOutput = false), ';');
    description = sprintf('Supported Files (%s)', strjoin(normalizedExtensions, ', '));
    fileFilter = {pattern, description; '*.*', 'All Files (*.*)'};
end

