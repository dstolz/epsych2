function value = normalizeCompiledPreviewValue(obj, rawValue, columnType)
    if nargin < 3
        columnType = '';
    end
    if isempty(rawValue)
        value = '';
        return
    end

    if ischar(rawValue)
        if isequal(columnType, 'File')
            value = obj.getFileNameDisplayText(rawValue);
        else
            value = rawValue;
        end
        return
    end

    if isnumeric(rawValue) || islogical(rawValue)
        value = rawValue;
        return
    end

    if isstring(rawValue)
        if isscalar(rawValue)
            if isequal(columnType, 'File')
                value = obj.getFileNameDisplayText(rawValue);
            else
                value = char(rawValue);
            end
        else
            value = strjoin(cellfun(@(item) obj.normalizeCompiledPreviewValueAsText(item, columnType), cellstr(rawValue(:).'), 'UniformOutput', false), '; ');
        end
        return
    end

    if iscell(rawValue)
        if isscalar(rawValue)
            value = obj.normalizeCompiledPreviewValue(rawValue{1}, columnType);
        else
            value = strjoin(cellfun(@(item) obj.normalizeCompiledPreviewValueAsText(item, columnType), rawValue(:).', 'UniformOutput', false), '; ');
        end
        return
    end

    if isstruct(rawValue)
        if isscalar(rawValue) && isfield(rawValue, 'file') && ~isempty(rawValue.file)
            if isequal(columnType, 'File')
                value = obj.getFileNameDisplayText(rawValue.file);
            else
                value = char(string(rawValue.file));
            end
        else
            value = obj.normalizeCompiledPreviewValueAsText(rawValue, columnType);
        end
        return
    end

    value = obj.normalizeCompiledPreviewValueAsText(rawValue, columnType);
end

