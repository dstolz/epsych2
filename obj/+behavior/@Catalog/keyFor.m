function key = keyFor(root, file)
% key = behavior.Catalog.keyFor(root, file)
% A session's KEY: its path relative to root, with "/" between folders, in its
% on-disk spelling.
%
% A key names the same session on every machine a dataset is copied to, which
% is what lets a project file, an export and a generated script refer to it;
% fullfile(root, key) finds it again. Compare keys with keyEquals.
%
% Parameters:
%   root - The data root.
%   file - A file under root.
%
% Returns:
%   key - 1x1 string, e.g. "ProjA/SUBJ-ID-1234/SUBJ-ID-1234_261007T114223_Pre.mat".
%
% See also: behavior.Catalog.keyEquals

arguments
    root (1,1) string
    file (1,1) string
end

r = replace(root, "\", "/");
f = replace(file, "\", "/");
if endsWith(r, "/"), r = extractBefore(r, strlength(r)); end

if ~startsWith(f, r + "/", 'IgnoreCase', ispc)
    error('behavior:Catalog:NotUnderRoot', '"%s" is not under the data root "%s".', file, root);
end

key = extractAfter(f, strlength(r) + 1);

end
