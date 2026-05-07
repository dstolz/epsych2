function values = normalizeValues(value)
% values = hw.Parameter.normalizeValues(value)
% Convert any scalar, vector, cell array, or string array to a uniform
% 1×N cell array of individual trial levels, for storage in hw.Parameter.Values.
%
% Parameters:
%   value - any type: numeric scalar/vector, logical, char, string array, or cell array
%
% Returns:
%   values (1,:) cell - one element per trial level
if isnumeric(value) || islogical(value)
    if isempty(value)
        values = {};
    else
        values = num2cell(reshape(value, 1, []));
    end
elseif isstring(value)
    if isscalar(value)
        values = {char(value)};
    else
        values = reshape(cellstr(value), 1, []);
    end
elseif ischar(value)
    values = {value};
elseif iscell(value)
    values = reshape(value, 1, []);
elseif isa(value, 'stimgen.StimType')
    if isempty(value)
        values = {};
    else
        values = num2cell(reshape(value, 1, []));
    end
else
    values = {value};
end
