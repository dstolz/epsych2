function [items, fullpaths] = FindConfigFiles(self, root)
% [items, fullpaths] = FindConfigFiles(self, root)
% Recursively list .ecfg files beneath a configuration root.
%
% Parameters:
%	root	- Root folder to scan for configuration files.
%
% Returns:
%	items		- Relative file paths under root, sorted alphabetically.
%	fullpaths	- Absolute file paths in the same order as items.
arguments
    self %#ok<INUSA>
    root (1,1) string
end

d = dir(fullfile(root,"**","*.ecfg"));
if isempty(d)
    items = string.empty(0,1);
    fullpaths = string.empty(0,1);
    return
end

fullpaths = string({d.folder}) + filesep + string({d.name});

prefix = root;
if ~endsWith(prefix,filesep)
    prefix = prefix + filesep;
end
items = replace(fullpaths,prefix,"");

[items,idx] = sort(items);
fullpaths = fullpaths(idx);
