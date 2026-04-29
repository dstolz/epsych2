function [items, fullpaths] = FindConfigFiles(self, root)
% FindConfigFiles — Return relative list and fullpaths of *.ecfg under root.
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
