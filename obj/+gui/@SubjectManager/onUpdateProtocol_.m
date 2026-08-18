function onUpdateProtocol_(self, scope, options)
% onUpdateProtocol_(self, scope)
% onUpdateProtocol_(self, scope, UseProjectDefault = true)
% Bring one subject, the checked ones, or the whole project onto the latest
% protocol version, after saying exactly what will change.
%
% Confirmation names the versions rather than counting rows. "Update 6
% subjects?" is a question an operator cannot answer; "v4 -> v7 for 6 subjects"
% is one they can.
%
% Retired members are never touched, whichever scope asked. A finished animal's
% recorded protocol IS the record of what it ran; moving it onto a version
% saved after the fact would rewrite that for a session that will never happen.
% 'row' says so and stops, the other two skip quietly and say how many.
%
% Parameters:
%   scope - 'row' (the selected row), 'checked', or 'project' (every active
%           subject in the selected project, including any the filter hides).
%
% Options:
%   UseProjectDefault - also move each subject onto the project's default file.
%
% See also: epsych.SubjectRoster.updateProtocol, gui.SubjectManager.onRevertProtocol_
arguments
    self
    scope (1,:) char {mustBeMember(scope, {'row','checked','project'})}
    options.UseProjectDefault (1,1) logical = false
end

projectId = self.selectedProject_();
if isempty(projectId)
    uialert(self.H.figure, ...
        ['Select a project on the left first. What a subject last ran is recorded ' ...
         'per project, so there is nothing to update in the All Projects view.'], ...
        'Update Protocol', 'Icon','info');
    return
end

p = self.Roster.findProject(projectId);
if isempty(p), return, end

% --- who ----------------------------------------------------------------
skipped = 0;

switch scope
    case 'row'
        rec = self.selectedRow_();
        if isempty(rec), return, end
        if self.isRetiredIn_(rec.SubjectID, projectId)
            uialert(self.H.figure, sprintf( ...
                ['"%s" is retired from this project, so its protocol is left as ' ...
                 'the record of what it ran.\n\nRestore it to the project first ' ...
                 'if it is going to run again.'], rec.Name), ...
                'Update Protocol', 'Icon','info');
            return
        end
        ids = {rec.SubjectID};

    case 'checked'
        ids = self.checkedIds_();
        if isempty(ids)
            self.setStatus_('Tick the subjects to update first.');
            return
        end
        [ids, skipped] = self.activeOnly_(ids, projectId);
        if isempty(ids)
            self.setStatus_(sprintf( ...
                'Nothing to update: all %d checked subject(s) are retired.', skipped));
            return
        end

    case 'project'
        % Every ACTIVE member, including any the filter hides: "all in project"
        % that quietly meant "all currently visible" would leave stragglers
        % behind exactly when the operator believed otherwise. Retired members
        % are not stragglers -- they are done.
        recs = self.Roster.subjectsInProject(projectId);
        if isempty(recs)
            self.setStatus_('That project has no active subjects.');
            return
        end
        ids = {recs.SubjectID};
end

% --- what would change ---------------------------------------------------
target = '';
if options.UseProjectDefault
    target = p.DefaultProtocol;
    if isempty(target)
        uialert(self.H.figure, sprintf( ...
            ['Project "%s" has no default protocol. Set one in Edit Project... ' ...
             'first.'], p.Name), 'Update Protocol', 'Icon','warning');
        return
    end
end

% What was left out is said in the same breath as what will change, so a count
% that does not match the ticks is explained before it is noticed.
note = '';
if skipped > 0
    note = sprintf('%d retired subject(s) skipped.', skipped);
end

preview = localPreview(self.Roster, ids, projectId, target);
if isempty(preview.changes)
    uialert(self.H.figure, strtrim([preview.message ' ' note]), ...
        'Update Protocol', 'Icon','info');
    self.refresh();
    return
end

tail = {'', ['Each subject''s previous protocol is kept — the version itself ' ...
    'stays in the file''s archive — so this can be undone with Revert ' ...
    'Protocol Version...']};
if ~isempty(note)
    tail = [{'', note}, tail];
end

answer = uiconfirm(self.H.figure, [preview.lines, tail], ...
    'Update Protocol', ...
    'Options', {'Update','Cancel'}, ...
    'DefaultOption','Update', 'CancelOption','Cancel', 'Icon','question');
if ~strcmp(answer, 'Update'), return, end

% --- apply ---------------------------------------------------------------
report = self.Roster.updateProtocol(ids, projectId, ...
    UseProjectDefault = options.UseProjectDefault);

% An override was the operator saying "use this file next session"; a committed
% update supersedes it, and leaving it in place would make the table keep
% showing the old choice over the new record.
for i = 1:numel(report.updated)
    if self.ProtocolOverrides_.isKey(report.updated(i).SubjectID)
        self.ProtocolOverrides_.remove(report.updated(i).SubjectID);
    end
end

self.refresh();
self.setStatus_(strtrim([report.message ' ' note]));

if ~report.ok
    uialert(self.H.figure, report.message, 'Update Protocol', 'Icon','info');
end

end

% -----------------------------------------------------------------------
function preview = localPreview(roster, ids, projectId, target)
% Work out what an update would do, without doing it.
%
% This asks the same questions updateProtocol does, so the confirmation cannot
% promise something different from what happens.
preview = struct('changes', {{}}, 'lines', {{}}, 'message', '');

st = roster.protocolStatus(ids, projectId);
changes = {};

for i = 1:numel(st)
    if isempty(target)
        file = st(i).Protocol;
    else
        file = target;
    end

    if isempty(file) || ~isfile(file)
        continue
    end

    latest = epsych.Protocol.versionOnDisk(file);
    sameFile = strcmpi(strrep(file,'/',filesep), strrep(st(i).Protocol,'/',filesep));
    if sameFile && strcmp(latest, st(i).Version)
        continue
    end

    changes{end+1} = struct('Name', st(i).Name, ...
        'From', st(i).Protocol, 'FromVersion', st(i).Version, ...
        'To', file, 'ToVersion', latest);
end

preview.changes = changes;

if isempty(changes)
    preview.message = sprintf(['Nothing to update: all %d subject(s) are already on ' ...
        'the current protocol version.'], numel(st));
    return
end

lines = {sprintf('Update %d of %d subject(s)?', numel(changes), numel(st)), ''};

% One line per distinct move rather than per subject: a project of sixteen
% animals on one protocol is one sentence, not sixteen identical ones.
keys = cellfun(@(c) localMoveKey(c), changes, 'uni', 0);
[uniqueKeys, ~, which] = unique(keys, 'stable');
for k = 1:numel(uniqueKeys)
    n = nnz(which == k);
    c = changes{find(which == k, 1)};
    lines{end+1} = sprintf('  %s  (%d subject%s)', localMoveText(c), n, localPlural(n));
end

preview.lines = lines;
end

% -----------------------------------------------------------------------
function k = localMoveKey(c)
k = sprintf('%s|%s|%s|%s', c.From, c.FromVersion, c.To, c.ToVersion);
end

% -----------------------------------------------------------------------
function txt = localMoveText(c)
[~, fn, fe] = fileparts(c.From);
[~, tn, te] = fileparts(c.To);
from = localVer(c.FromVersion);
to   = localVer(c.ToVersion);

if strcmpi([fn fe], [tn te])
    txt = sprintf('%s%s: %s -> %s', tn, te, from, to);
elseif isempty(fn)
    txt = sprintf('(none) -> %s%s %s', tn, te, to);
else
    txt = sprintf('%s%s %s -> %s%s %s', fn, fe, from, tn, te, to);
end
end

% -----------------------------------------------------------------------
function v = localVer(v)
if isempty(v), v = '(not recorded)'; end
end

% -----------------------------------------------------------------------
function s = localPlural(n)
s = 's';
if n == 1, s = ''; end
end
