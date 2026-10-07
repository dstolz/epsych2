function P = open(root, options)
% P = behavior.Project.open(root)
% P = behavior.Project.open(root, Store = folder)
% The project of a data root: its project.json when there is one, else an
% empty project in memory. Opening WRITES NOTHING -- no folder, no file.
%
% A file that cannot be read, a project.json that is a folder, or a file
% written by a newer EPsych (FormatVersion above FORMAT_VERSION) opens the
% project ReadOnly, with a Warnings entry saying why and whatever could be
% read kept, so nothing this version does not understand is overwritten.
%
% Parameters:
%   root  - Data root folder. Must exist.
%   Store - Store folder for a root that cannot be written (the project file
%           is then <Store>/project.json). Default "" =
%           <root>/<behavior.Catalog.StoreFolder>.
%
% Returns:
%   P - behavior.Project
%
% See also: behavior.Project.save, behavior.Project.canWrite

arguments
    root (1,1) string
    options.Store (1,1) string = ""
end

if ~isfolder(root)
    error('behavior:Project:NoRoot', 'The data root "%s" is not a folder.', root);
end
root = localAbsolute(root);
if strtrim(options.Store) == ""
    store = string(fullfile(root, behavior.Catalog.StoreFolder));
else
    store = localAbsolute(options.Store);
end
file = string(fullfile(store, behavior.Project.FileName));

if isfile(file)
    stamp = behavior.Project.stamp_(file);
    [s, why] = behavior.Project.readFile_(file);
    if why == ""
        P = behavior.Project.fromStruct_(s, root, store);
    else
        P = behavior.Project(root, store);
        P.ReadOnly = true;
        P.Warnings(end+1, 1) = "The project file cannot be read (" + why ...
            + "), so it is opened read-only and will not be overwritten: " + file;
        vprintf(1, 'behavior.Project: %s', P.Warnings(end))
    end
    P.LoadedStamp = stamp;
elseif isfolder(file)
    P = behavior.Project(root, store);
    P.ReadOnly = true;
    P.Warnings(end+1, 1) = "The project file is a folder, so the project cannot be saved: " + file;
    vprintf(1, 'behavior.Project: %s', P.Warnings(end))
else
    P = behavior.Project(root, store);
end

vprintf(2, 'behavior.Project: opened %s', P.summary())

end


function p = localAbsolute(p)
% An absolute path with no trailing separator (except a drive root).
p = strtrim(p);
if ispc
    isAbs = ~isempty(regexp(p, '^([A-Za-z]:[\\/]|[\\/]{2})', 'once'));
else
    isAbs = startsWith(p, "/");
end
if ~isAbs
    p = string(fullfile(pwd, p));
end
if isfolder(p)
    d = dir(p);
    d = d(strcmp({d.name}, '.'));
    if ~isempty(d)
        p = string(d(1).folder);
    end
end
if strlength(p) > 3 && (endsWith(p, "\") || endsWith(p, "/"))
    p = extractBefore(p, strlength(p));
end
end
