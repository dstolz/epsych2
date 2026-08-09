function text = normalizeCompiledPreviewValueAsText(obj, rawValue, columnType)
    if nargin < 3
        columnType = '';
    end
    if isempty(rawValue)
        text = '';
        return
    end

    if ischar(rawValue)
        if isequal(columnType, 'File')
            text = obj.getFileNameDisplayText(rawValue);
        else
            text = rawValue;
        end
        return
    end

    if isstring(rawValue)
        text = strjoin(cellfun(@(item) obj.normalizeCompiledPreviewValueAsText(item, columnType), cellstr(string(rawValue(:).')), 'UniformOutput', false), '; ');
        return
    end

    if isnumeric(rawValue) || islogical(rawValue)
        if isscalar(rawValue)
            text = num2str(rawValue);
        else
            text = mat2str(rawValue);
        end
        return
    end

    if isa(rawValue, 'stimgen.StimType')
        if isscalar(rawValue)
            text = char(string(rawValue.DisplayName));
        else
            names = arrayfun(@(item) char(string(item.DisplayName)), rawValue(:).', 'UniformOutput', false);
            text = strjoin(names, '; ');
        end
        return
    end

    if iscell(rawValue)
        text = strjoin(cellfun(@(item) obj.normalizeCompiledPreviewValueAsText(item, columnType), rawValue(:).', 'UniformOutput', false), '; ');
        return
    end

    if isstruct(rawValue)
        if isscalar(rawValue)
            fieldNames = fieldnames(rawValue);
            if isempty(fieldNames)
                text = '[struct]';
            else
                firstField = fieldNames{1};
                text = sprintf('%s=%s', firstField, obj.normalizeCompiledPreviewValueAsText(rawValue.(firstField), columnType));
            end
        else
            text = sprintf('[%dx%d struct]', size(rawValue, 1), size(rawValue, 2));
        end
        return
    end

    if isobject(rawValue)
        if isscalar(rawValue)
            text = sprintf('[%s]', class(rawValue));
        else
            text = sprintf('[%dx%d %s]', size(rawValue, 1), size(rawValue, 2), class(rawValue));
        end
        return
    end

    text = char(string(rawValue));
end

