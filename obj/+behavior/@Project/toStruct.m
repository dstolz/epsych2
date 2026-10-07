function s = toStruct(P)
% s = toStruct(P)
% The project file's content as a struct jsonencode writes exactly: every
% datetime as ISO text to the millisecond ("" = never), string lists as
% cellstr rows and records as row cells of structs (so one element is still
% a JSON ARRAY), "find it" numbers as []. It holds no NaN, Inf or missing
% string -- a stray one is replaced and logged -- so the file never carries
% null.
%
% Session and subject rows are written in key order, so two saves of the
% same decisions write the same text.
%
% Returns:
%   s - scalar struct: FormatVersion, Revision, Saved, Root, Writer,
%       Settings, SettingsModified, Presets, Facets, Groupings, Sessions,
%       Subjects, Selection

iso = @behavior.Project.iso_;

s = struct();
s.FormatVersion = behavior.Project.FORMAT_VERSION;
s.Revision = P.Revision;
s.Saved = iso(P.Saved);
s.Root = replace(P.Root, "\", "/");
s.Writer = P.Writer;
s.Settings = P.Settings.toStruct();
s.SettingsModified = iso(P.SettingsModified);

s.Presets = cell(1, numel(P.Presets));
for k = 1:numel(P.Presets)
    r = P.Presets(k);
    s.Presets{k} = struct('Name', r.Name, 'Settings', r.Settings, 'View', r.View, ...
        'Modified', iso(r.Modified));
end

F = P.Facets;
s.Facets = struct('GroupBy', F.GroupBy, 'ColorBy', F.ColorBy, 'XAxis', F.XAxis, ...
    'Value', F.Value, 'Kind', F.Kind, 'Modified', iso(F.Modified));

s.Groupings = cell(1, numel(P.Groupings));
for k = 1:numel(P.Groupings)
    G = P.Groupings(k);
    subj = cell(1, numel(G.Subjects));
    for j = 1:numel(G.Subjects)
        subj{j} = struct('Subject', G.Subjects(j).Subject, 'Level', G.Subjects(j).Level);
    end
    sess = cell(1, numel(G.Sessions));
    for j = 1:numel(G.Sessions)
        sess{j} = struct('Key', G.Sessions(j).Key, 'Level', G.Sessions(j).Level);
    end
    s.Groupings{k} = struct('Name', G.Name, 'Levels', {localCellRow(G.Levels)}, ...
        'Subjects', {subj}, 'Sessions', {sess}, 'Modified', iso(G.Modified));
end

T = P.Sessions;
[~, order] = sort(behavior.Project.normKey_(T.Key));
T = T(order, :);
s.Sessions = cell(1, height(T));
for k = 1:height(T)
    s.Sessions{k} = struct('Key', T.Key(k), 'Hidden', T.Hidden(k), ...
        'HiddenReason', T.HiddenReason(k), 'Window', T.Window(k), ...
        'Comment', T.Comment(k), 'Modified', iso(T.Modified(k)));
end

T = P.Subjects;
[~, order] = sort(behavior.Project.normKey_(T.Subject));
T = T(order, :);
s.Subjects = cell(1, height(T));
for k = 1:height(T)
    s.Subjects{k} = struct('Subject', T.Subject(k), 'Comment', T.Comment(k), ...
        'Modified', iso(T.Modified(k)));
end

s.Selection = struct('Keys', {localCellRow(P.Selection.Keys)}, 'Modified', iso(P.Selection.Modified));

[s, n] = localFinite(s);
if n > 0
    vprintf(0, 1, 'behavior.Project: %d NaN, Inf or missing value(s) were replaced before writing %s', n, P.File)
end

end


function c = localCellRow(x)
c = reshape(cellstr(x), 1, []);
end


function [v, n] = localFinite(v)
% v with every non-finite number replaced by [] and every missing string by
% "", and how many there were: jsonencode would write null for either.
n = 0;
if isstruct(v)
    for e = 1:numel(v)
        for f = reshape(string(fieldnames(v)), 1, [])
            [v(e).(f), k] = localFinite(v(e).(f));
            n = n + k;
        end
    end
elseif iscell(v)
    for e = 1:numel(v)
        [v{e}, k] = localFinite(v{e});
        n = n + k;
    end
elseif isfloat(v) && ~all(isfinite(v(:)))
    n = 1;
    v = [];
elseif isstring(v) && any(ismissing(v(:)))
    n = 1;
    v(ismissing(v)) = "";
end
end
