function vstr = formatStimTypeValue_(~, value)
if isempty(value)
    vstr = '[none]';
    return
end
names = arrayfun(@(s) char(s.DisplayName), value, 'UniformOutput', false);
if numel(names) == 1
    vstr = names{1};
else
    previewCount = min(3, numel(names));
    preview = strjoin(names(1:previewCount), ', ');
    if numel(names) > previewCount
        vstr = sprintf('[%s, ... (%d stims)]', preview, numel(names));
    else
        vstr = sprintf('[%s]', preview);
    end
end
