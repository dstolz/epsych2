function P = fromStruct_(s, root, store)
% P = behavior.Project.fromStruct_(s, root, store)
% A project from a decoded project file (jsondecode output, or toStruct's),
% forgivingly. What jsondecode does to shapes is undone here: string arrays
% come back as cellstr (or char for one element), an array of objects as a
% struct array or a cell, an empty array as [], datetimes as ISO text.
%
% A field this version does not know is ignored (debug log); a field it
% expects and the file lacks takes its default, since the file may predate
% it; a section or record that cannot be read is dropped with a Warnings
% entry. A FormatVersion newer than FORMAT_VERSION makes the project
% ReadOnly, keeping what could be read.
%
% Parameters:
%   s     - scalar struct
%   root  - absolute data root
%   store - absolute store folder
%
% Returns:
%   P - behavior.Project, Dirty false, its merge base set to what was read

P = behavior.Project(root, store);
if ~isstruct(s) || ~isscalar(s)
    P.ReadOnly = true;
    P.Warnings(end+1, 1) = "The project file holds no project object; it is opened read-only.";
    vprintf(1, 'behavior.Project: %s', P.Warnings(end))
    return
end

known = ["FormatVersion" "Revision" "Saved" "Root" "Writer" "Settings" "SettingsModified" ...
    "Presets" "Facets" "Groupings" "Sessions" "Subjects" "Selection"];
names = string(fieldnames(s));
for f = reshape(setdiff(names, known), 1, [])
    vprintf(2, 'behavior.Project: ignoring unknown field "%s" in %s', f, P.File)
end
warn = strings(0, 1);

% --- version ------------------------------------------------------------
v = localGet(s, "FormatVersion", []);
if isempty(v)
    vprintf(2, 'behavior.Project: %s has no FormatVersion; reading it as version %d', ...
        P.File, behavior.Project.FORMAT_VERSION)
    v = behavior.Project.FORMAT_VERSION;
end
if ~isnumeric(v) || ~isscalar(v) || ~isfinite(v)
    P.ReadOnly = true;
    warn(end+1, 1) = "The project file's FormatVersion is not a number; it is opened read-only.";
    v = behavior.Project.FORMAT_VERSION;
elseif v > behavior.Project.FORMAT_VERSION
    P.ReadOnly = true;
    warn(end+1, 1) = sprintf(['The project file was written by a newer EPsych (FormatVersion %g; ' ...
        'this one reads %g). It is opened read-only so nothing it holds is lost.'], ...
        v, behavior.Project.FORMAT_VERSION);
end
P.FormatVersion = double(v);

% --- scalars ------------------------------------------------------------
try
    r = double(localGet(s, "Revision", 0));
    if isscalar(r) && isfinite(r) && r >= 0, P.Revision = r; end
    P.Saved = behavior.Project.parseIso_(localText(localGet(s, "Saved", "")));
    P.Writer = localText(localGet(s, "Writer", ""));
    fileRoot = localText(localGet(s, "Root", ""));
    if fileRoot ~= "" && ~behavior.Catalog.keyEquals(fileRoot, root)
        vprintf(2, 'behavior.Project: %s was saved for "%s" and is read for "%s" (a moved or copied root)', ...
            P.File, fileRoot, root)
    end
catch ME
    warn(end+1, 1) = "The file's revision, save time or writer could not be read: " + ME.message;
end

% --- settings -----------------------------------------------------------
if ismember("Settings", names)
    [P.Settings, w] = behavior.Settings.fromStruct(s.Settings);
    warn = [warn; "Settings: " + w];
end
try
    P.SettingsModified = behavior.Project.parseIso_(localText(localGet(s, "SettingsModified", "")));
catch ME
    warn(end+1, 1) = "SettingsModified could not be read: " + ME.message;
end

% --- presets ------------------------------------------------------------
[recs, w] = localRecords(localGet(s, "Presets", []), "Presets");
warn = [warn; w];
notes = cell(numel(recs), 1);
for k = 1:numel(recs)
    r = recs{k};
    try
        name = strtrim(localText(localGet(r, "Name", "")));
        if name == "", error('behavior:Project:InvalidName', 'it has no name'); end
        [st, w] = behavior.Settings.fromStruct(localGet(r, "Settings", struct()));
        notes{k} = "Preset """ + name + """: " + w;
        rec = struct('Name', name, 'Settings', st.toStruct(), ...
            'View', localView(localGet(r, "View", struct())), ...
            'Modified', behavior.Project.parseIso_(localText(localGet(r, "Modified", ""))));
        P.Presets = localPut(P.Presets, rec);
    catch ME
        notes{k} = string(sprintf('Preset %d could not be read (%s) and is dropped.', k, ME.message));
    end
end
warn = [warn; vertcat(strings(0, 1), notes{:})];

% --- facets -------------------------------------------------------------
F = localGet(s, "Facets", struct());
if isstruct(F) && isscalar(F)
    D = P.Facets;
    for f = ["GroupBy" "ColorBy" "XAxis" "Value" "Kind"]
        t = localText(localGet(F, f, D.(f)));
        if t ~= "", D.(f) = t; end
    end
    try
        D.Modified = behavior.Project.parseIso_(localText(localGet(F, "Modified", "")));
    catch ME
        warn(end+1, 1) = "Facets.Modified could not be read: " + ME.message;
    end
    P.Facets = D;
else
    warn(end+1, 1) = "Facets could not be read; the defaults are used.";
end

% --- groupings ----------------------------------------------------------
[recs, w] = localRecords(localGet(s, "Groupings", []), "Groupings");
warn = [warn; w];
notes = cell(numel(recs), 1);
for k = 1:numel(recs)
    r = recs{k};
    try
        name = strtrim(localText(localGet(r, "Name", "")));
        if name == "", error('behavior:Project:InvalidName', 'it has no name'); end
        levels = behavior.Project.checkLevels_(localTextRow(localGet(r, "Levels", [])));
        [subj, w1] = localAssignments(localGet(r, "Subjects", []), "Subject", levels, name);
        [sess, w2] = localAssignments(localGet(r, "Sessions", []), "Key", levels, name);
        notes{k} = [w1; w2];
        rec = struct('Name', name, 'Levels', levels, 'Subjects', subj, 'Sessions', sess, ...
            'Modified', behavior.Project.parseIso_(localText(localGet(r, "Modified", ""))));
        P.Groupings = localPut(P.Groupings, rec);
    catch ME
        notes{k} = string(sprintf('Grouping %d could not be read (%s) and is dropped.', k, ME.message));
    end
end
warn = [warn; vertcat(strings(0, 1), notes{:})];

% --- sessions -----------------------------------------------------------
[recs, w] = localRecords(localGet(s, "Sessions", []), "Sessions");
warn = [warn; w];
n = numel(recs);
key = strings(n, 1); hidden = false(n, 1); reason = strings(n, 1);
window = strings(n, 1); comment = strings(n, 1); modified = NaT(n, 1);
ok = false(n, 1);
notes = cell(n, 1);
for k = 1:n
    r = recs{k};
    try
        key(k) = behavior.Project.cleanKey_(localText(localGet(r, "Key", "")));
        if key(k) == "", error('behavior:Project:InvalidKey', 'it has no key'); end
        hidden(k) = localLogical(localGet(r, "Hidden", false));
        reason(k) = localText(localGet(r, "HiddenReason", ""));
        window(k) = localText(localGet(r, "Window", ""));
        if window(k) ~= ""
            window(k) = psychophysics.TrialWindow.parse(window(k)).toText();
        end
        comment(k) = localText(localGet(r, "Comment", ""));
        modified(k) = behavior.Project.parseIso_(localText(localGet(r, "Modified", "")));
        ok(k) = true;
    catch ME
        notes{k} = string(sprintf('Session record %d could not be read (%s) and is dropped.', k, ME.message));
    end
end
warn = [warn; vertcat(strings(0, 1), notes{:})];
T = table(key, hidden, reason, window, comment, modified, ...
    'VariableNames', P.Sessions.Properties.VariableNames);
T = T(ok, :);
T = T(~(~T.Hidden & T.HiddenReason == "" & T.Window == "" & T.Comment == ""), :);
P.Sessions = localUniqueLatest(T, "Key");

% --- subjects -----------------------------------------------------------
[recs, w] = localRecords(localGet(s, "Subjects", []), "Subjects");
warn = [warn; w];
n = numel(recs);
subject = strings(n, 1); comment = strings(n, 1); modified = NaT(n, 1);
ok = false(n, 1);
notes = cell(n, 1);
for k = 1:n
    r = recs{k};
    try
        subject(k) = strtrim(localText(localGet(r, "Subject", "")));
        comment(k) = localText(localGet(r, "Comment", ""));
        modified(k) = behavior.Project.parseIso_(localText(localGet(r, "Modified", "")));
        ok(k) = subject(k) ~= "" && comment(k) ~= "";
    catch ME
        notes{k} = string(sprintf('Subject record %d could not be read (%s) and is dropped.', k, ME.message));
    end
end
warn = [warn; vertcat(strings(0, 1), notes{:})];
T = table(subject, comment, modified, 'VariableNames', P.Subjects.Properties.VariableNames);
P.Subjects = localUniqueLatest(T(ok, :), "Subject");

% --- selection ----------------------------------------------------------
S = localGet(s, "Selection", struct());
if isstruct(S) && isscalar(S)
    try
        keys = behavior.Project.cleanKey_(localTextRow(localGet(S, "Keys", [])));
        [~, ia] = unique(behavior.Project.normKey_(keys), 'stable');
        P.Selection = struct('Keys', keys(sort(ia)), ...
            'Modified', behavior.Project.parseIso_(localText(localGet(S, "Modified", ""))));
    catch ME
        warn(end+1, 1) = "Selection could not be read (" + ME.message + "); nothing is selected.";
    end
else
    warn(end+1, 1) = "Selection could not be read; nothing is selected.";
end

for k = 1:numel(warn)
    vprintf(1, 'behavior.Project: %s', warn(k))
end
P.Warnings = [P.Warnings; warn];
P.Base_ = behavior.Project.baseOf_(P);
P.Dirty = false;

end


% =========================================================================
function v = localGet(r, name, default)
% A field of a decoded record, or default when the file predates it.
if any(strcmp(fieldnames(r), name))
    v = r.(name);
else
    v = default;
end
end


function t = localText(v)
% One string from what jsondecode gives for text ([] for an empty array).
if isstring(v) && isscalar(v)
    t = v;
elseif ischar(v) && (isrow(v) || isempty(v))
    t = string(v);
elseif isempty(v)
    t = "";
else
    error('behavior:Project:NotText', 'a %s where text was expected', class(v));
end
if ismissing(t), t = ""; end
end


function t = localTextRow(v)
% A (1,:) string from what jsondecode gives for a string array: cellstr, or
% char for a single element, or [] for none.
if isempty(v)
    t = strings(1, 0);
elseif ischar(v)
    t = string(v);
elseif iscellstr(v) || isstring(v)
    t = reshape(string(v), 1, []);
else
    error('behavior:Project:NotText', 'a %s where a list of text was expected', class(v));
end
t(ismissing(t)) = "";
end


function tf = localLogical(v)
if (islogical(v) || isnumeric(v)) && isscalar(v)
    tf = logical(v);
else
    error('behavior:Project:NotLogical', 'a %s where true/false was expected', class(v));
end
end


function [recs, warn] = localRecords(v, what)
% An array of objects as a row cell of scalar structs, whatever jsondecode
% made of it (a struct array when every object had the same fields, a cell
% otherwise, [] for none).
warn = strings(0, 1);
if isempty(v)
    recs = cell(1, 0);
elseif isstruct(v)
    recs = num2cell(reshape(v, 1, []));
elseif iscell(v)
    recs = reshape(v, 1, []);
    good = cellfun(@(x) isstruct(x) && isscalar(x), recs);
    if ~all(good)
        warn(end+1, 1) = sprintf('%d %s entries are not records and are dropped.', sum(~good), what);
        recs = recs(good);
    end
else
    recs = cell(1, 0);
    warn(end+1, 1) = what + " is not a list of records and is ignored.";
end
end


function V = localView(v)
% A preset's view: struct() when it has none.
V = struct();
if ~isstruct(v) || ~isscalar(v) || isempty(fieldnames(v)), return, end
D = behavior.Project.defaultFacets_();
for f = ["GroupBy" "ColorBy" "XAxis" "Value" "Kind"]
    t = localText(localGet(v, f, ""));
    if t == "", t = D.(f); end
    V.(f) = t;
end
end


function [list, warn] = localAssignments(v, idField, levels, grouping)
% A grouping's Subjects or Sessions list; an assignment to a level the
% grouping does not have is dropped (it would break the invariant assign
% keeps).
[recs, warn] = localRecords(v, "Grouping """ + grouping + """ " + idField);
n = numel(recs);
ids = strings(1, n);
lev = strings(1, n);
for k = 1:n
    ids(k) = strtrim(localText(localGet(recs{k}, idField, "")));
    lev(k) = strtrim(localText(localGet(recs{k}, "Level", "")));
end
if idField == "Key", ids = behavior.Project.cleanKey_(ids); end
keep = ids ~= "" & lev ~= "";
bad = keep & ~ismember(lev, levels);
for k = find(bad)
    vprintf(1, 'behavior.Project: grouping "%s": "%s" was assigned to "%s", which is not one of its levels; dropped', ...
        grouping, ids(k), lev(k))
end
if any(bad)
    warn = [warn; sprintf('Grouping "%s": %d assignment(s) to a level it does not have were dropped.', ...
        grouping, sum(bad))];
end
keep = keep & ~bad;
list = reshape(cell2struct([num2cell(ids(keep)); num2cell(lev(keep))], ...
    {char(idField); 'Level'}, 1), 1, []);
end


function S = localPut(S, rec)
% Add a named record; a duplicate name keeps the later Modified.
i = find(arrayfun(@(x) x.Name == rec.Name, S), 1);
if isempty(i)
    S(end+1) = rec;
elseif ~(rec.Modified <= S(i).Modified)
    S(i) = rec;
end
end


function T = localUniqueLatest(T, idVar)
% One row per id (keyEquals rule), the later Modified kept.
if height(T) < 2, return, end
[~, order] = sort(T.Modified, 'descend', 'MissingPlacement', 'last');
T = T(order, :);
[~, ia] = unique(behavior.Project.normKey_(T.(idVar)), 'stable');
T = T(sort(ia), :);
end
