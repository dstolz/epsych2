function values = columnize_(~, values)
% values = columnize_(obj, values)
% Ensure a column vector; return NaN for empty.
%
% Parameters:
%   obj — psychophysics.Staircase instance (unused)
%   values — array
%
% Returns:
%   values — column vector; NaN when input is empty

if isempty(values)
    values = nan;
else
    values = values(:);
end
