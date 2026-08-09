function values = normalizeParameterValuesForTrials_(~, value)
if isnumeric(value) || islogical(value)
    if isempty(value) || isscalar(value)
        values = {value};
    else
        values = num2cell(reshape(value, 1, []));
    end
    return
end

if isstring(value)
    if isscalar(value)
        values = {char(value)};
    else
        values = reshape(cellstr(value), 1, []);
    end
    return
end

if ischar(value)
    values = {value};
    return
end

if iscell(value)
    if isempty(value)
        values = {value};
    else
        values = reshape(value, 1, []);
    end
    return
end

values = {value};
