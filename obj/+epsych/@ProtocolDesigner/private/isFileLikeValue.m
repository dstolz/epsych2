function tf = isFileLikeValue(~, value)
    tf = ischar(value) || isstring(value) || iscell(value);
end

