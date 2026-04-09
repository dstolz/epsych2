function tf = isMissingInterfaceOption(~, value)
    if ischar(value) || isstring(value)
        tf = strlength(string(value)) == 0;
    elseif iscell(value)
        tf = isempty(value) || all(cellfun(@(item) strlength(string(item)) == 0, value));
    else
        tf = isempty(value) || (isnumeric(value) && any(isnan(value)));
    end
end

