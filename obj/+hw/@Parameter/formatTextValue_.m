function valueText = formatTextValue_(~, value)
if isstring(value)
    value = cellstr(value);
end

if ischar(value)
    valueText = value;
    return
end

if iscell(value)
    flatValues = value;
    if numel(flatValues) == 1 && iscell(flatValues{1})
        flatValues = flatValues{1};
    end
    flatValues = flatValues(~cellfun(@isempty, flatValues));
    if isempty(flatValues)
        valueText = '';
    elseif numel(flatValues) == 1
        valueText = char(string(flatValues{1}));
    else
        previewCount = min(3, numel(flatValues));
        preview = strjoin(cellfun(@(item) char(string(item)), flatValues(1:previewCount), UniformOutput = false), ', ');
        if numel(flatValues) > previewCount
            valueText = sprintf('[%s, ... (%d values)]', preview, numel(flatValues));
        else
            valueText = sprintf('[%s]', preview);
        end
    end
    return
end

valueText = char(string(value));
