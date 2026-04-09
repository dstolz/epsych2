function defaultText = formatInterfaceDefault(~, defaultValue, isList)
    if iscell(defaultValue)
        defaultText = strjoin(defaultValue, ', ');
    elseif isstring(defaultValue)
        defaultText = char(defaultValue);
    elseif isnumeric(defaultValue)
        if isscalar(defaultValue)
            defaultText = num2str(defaultValue);
        else
            defaultText = strjoin(arrayfun(@num2str, defaultValue, UniformOutput = false), ', ');
        end
    elseif islogical(defaultValue)
        defaultText = num2str(defaultValue);
    else
        defaultText = '';
    end

    if isList && isempty(defaultText)
        defaultText = '';
    end
end

