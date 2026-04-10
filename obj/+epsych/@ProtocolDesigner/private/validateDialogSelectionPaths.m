function [isValid, allowedExtensions] = validateDialogSelectionPaths(obj, selectedPaths, fileFilter)
    allowedExtensions = localGetAllowedExtensions_(obj.normalizeDialogFileFilter(fileFilter));
    if isempty(allowedExtensions)
        isValid = true;
        return
    end

    invalidMask = cellfun(@(path) ~localHasAllowedExtension_(path, allowedExtensions), selectedPaths);
    isValid = ~any(invalidMask);
end

function allowedExtensions = localGetAllowedExtensions_(fileFilter)
    allowedExtensions = {};
    if ~iscell(fileFilter) || size(fileFilter, 2) ~= 2
        return
    end

    patterns = cellfun(@(value) char(string(value)), fileFilter(:, 1), 'UniformOutput', false);
    for idx = 1:numel(patterns)
        tokens = regexp(patterns{idx}, ';', 'split');
        for tokenIdx = 1:numel(tokens)
            token = strtrim(lower(tokens{tokenIdx}));
            if strcmp(token, '*') || strcmp(token, '*.*')
                allowedExtensions = {};
                return
            end

            extToken = regexp(token, '^\*\.(.+)$', 'tokens', 'once');
            if isempty(extToken)
                allowedExtensions = {};
                return
            end

            allowedExtensions = [allowedExtensions, {['.' extToken{1}]}];
        end
    end

    if ~isempty(allowedExtensions)
        allowedExtensions = unique(allowedExtensions, 'stable');
    end
end

function tf = localHasAllowedExtension_(filePath, allowedExtensions)
    [~, ~, ext] = fileparts(char(string(filePath)));
    tf = any(strcmpi(ext, allowedExtensions));
end