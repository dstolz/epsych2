function addToSession(self)
% addToSession(self)
% Commit the checked subjects into the session's CONFIG.
%
% Collects what the operator ticked and typed, hands it to
% epsych.SubjectRoster.assignToSession, and renders the report. All the
% decisions -- box assignment, protocol resolution, validation, all-or-nothing
% refusal -- belong to the engine, so this method has no rules of its own and
% the whole path stays testable without a window.
%
% On success the window closes and the session window is raised: the
% operator's next stop is the session, not this table. It stays open on
% failure, or when nothing was checked, so the operator can fix the problem
% without reopening it.
%
% See also: epsych.SubjectRoster.assignToSession, gui.SubjectManager.refresh
arguments
    self
end

ids = self.checkedIds_();
if isempty(ids)
    self.setStatus_('Tick at least one subject first.');
    return
end

boxes = nan(1, numel(ids));
protocols = cell(1, numel(ids));
for i = 1:numel(ids)
    if self.BoxOverrides_.isKey(ids{i})
        boxes(i) = self.BoxOverrides_(ids{i});
    end
    protocols{i} = self.resolveProtocol_(ids{i});
end

try
    report = self.Roster.assignToSession(self.RunExpt, ids, ...
        ProjectID = self.selectedProject_(), ...
        BoxIDs = boxes, ...
        Protocols = protocols);
catch ME
    vprintf(0, 1, ME);
    uialert(self.H.figure, ME.message, 'Add to Session', 'Icon','error');
    return
end

if report.aborted
    uialert(self.H.figure, report.message, 'Add to Session', 'Icon','warning');
    self.setStatus_(report.message);
    return
end

if ~report.ok
    detail = report.message;
    if ~isempty(report.skipped)
        detail = sprintf('%s\n\n%s', detail, localSkipList(report.skipped));
    end
    uialert(self.H.figure, detail, 'Add to Session', 'Icon','info');
    self.setStatus_(report.message);
    return
end

% Untick and clear the per-row overrides only for what actually went in, so a
% skipped subject keeps the box the operator typed for it.
added = {report.added.Name};
for i = 1:numel(self.Rows_)
    if ~any(strcmp(self.Rows_(i).Name, added)), continue, end
    id = self.Rows_(i).SubjectID;
    self.Checked_ = setdiff(self.Checked_, {id});
    if self.BoxOverrides_.isKey(id), self.BoxOverrides_.remove(id); end
    if self.ProtocolOverrides_.isKey(id), self.ProtocolOverrides_.remove(id); end
end

self.refresh();
self.setStatus_(report.message);

summary = localAddedList(report.added);
if ~isempty(report.skipped)
    % Raised only once the report is dismissed: the alert belongs to this
    % window, so closing it out from under the operator would bury the list
    % of what didn't make it in.
    uialert(self.H.figure, sprintf('%s\n\n%s\n\n%s', report.message, summary, ...
        localSkipList(report.skipped)), 'Add to Session', 'Icon','info', ...
        'CloseFcn', @(~,~) localFinish(self));
else
    localFinish(self);
end

end

% -----------------------------------------------------------------------
function localFinish(self)
% Raise the session window, then close this one: a full commit means the
% operator's next stop is the session, not this table.
localRaiseSession(self.RunExpt);
if isvalid(self)
    delete(self);
end
end

% -----------------------------------------------------------------------
function localRaiseSession(runExpt)
% Bring the session window forward so the operator sees the rows land in it.
% This window is closed by the caller straight after: a full commit is the end
% of the visit, and the operator's next stop is the session.
try
    if isempty(runExpt) || ~isvalid(runExpt), return, end
    if ~isfield(runExpt.H,'figure1') || ~isgraphics(runExpt.H.figure1), return, end

    % figure(), not uifigure(): the latter rejects a handle argument outright.
    fig = runExpt.H.figure1;
    fig.Visible = 'on';
    figure(fig);
catch ME
    vprintf(2, ME);
end
end

% -----------------------------------------------------------------------
function txt = localAddedList(added)
% One line per committed subject: name, box, protocol file name.
lines = cell(1, numel(added));
for i = 1:numel(added)
    [~, pn, pe] = fileparts(added(i).Protocol);
    lines{i} = sprintf('  %s  (box %d, %s%s)', added(i).Name, added(i).BoxID, pn, pe);
end
txt = sprintf('Added:\n%s', strjoin(lines, newline));
end

% -----------------------------------------------------------------------
function txt = localSkipList(skipped)
% One line per subject that was not added, and why.
lines = cell(1, numel(skipped));
for i = 1:numel(skipped)
    lines{i} = sprintf('  %s - %s', skipped(i).Name, skipped(i).reason);
end
txt = sprintf('Not added:\n%s', strjoin(lines, newline));
end
