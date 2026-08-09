function v = safeToNumeric_(~, x)
if isstring(x) || ischar(x)
    x = char(x);
    switch x
        case 'Inf'
            v = Inf;
        case '-Inf'
            v = -Inf;
        case 'NaN'
            v = NaN;
        otherwise
            v = str2double(x);
    end
else
    v = double(x);
end
