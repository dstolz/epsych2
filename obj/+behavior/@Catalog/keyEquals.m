function tf = keyEquals(a, b)
% tf = behavior.Catalog.keyEquals(a, b)
% Whether two session keys name the same file: separators unified, and case
% ignored on Windows, whose file system ignores it too.
%
% Parameters:
%   a, b - Keys (string arrays of the same size, or one of them scalar).
%
% Returns:
%   tf - Logical array, the size of the larger input.
%
% See also: behavior.Catalog.keyFor

arguments
    a string
    b string
end

a = replace(a, "\", "/");
b = replace(b, "\", "/");
if ispc
    tf = strcmpi(a, b);
else
    tf = strcmp(a, b);
end

end
