function refresh(self, opts)
% refresh(self)
% refresh(self, Reload = false)
% Re-read the roster and repopulate every control.
%
% Every callback ends here rather than patching individual widgets, so the
% window can never show a half-updated view, and a change another rig made
% between actions is picked up. There is no timer and no file watcher: the
% roster is re-read here, and the status line reports when.
%
% Parameters:
%   Reload - re-read the roster file first. Default true. The filter passes
%            false so that typing repaints the view without a disk read per
%            keystroke; every other caller wants the fresh copy.
%
% See also: gui.SubjectManager.buildUI, epsych.SubjectRoster.reload
arguments
    self
    opts.Reload (1,1) logical = true
end

if ~isfield(self.H,'figure') || ~isgraphics(self.H.figure), return, end

% Repopulating the table and the listbox fires their callbacks; this guard
% stops those from being read back as operator choices.
self.Refreshing_ = true;
restoreFlag = onCleanup(@() localClearFlag(self));

% --- roster health -------------------------------------------------------
if isempty(self.Roster) || ~isvalid(self.Roster)
    self.H.rosterLabel.Text = 'No roster';
    self.showEmptyState_('The subject roster could not be opened. Use Roster File... to choose one.');
    self.updateEnableStates_();
    return
end

if opts.Reload
    self.Roster.reload();
end

[~, rosterName, rosterExt] = fileparts(self.Roster.FilePath);
label = [rosterName rosterExt];
if ~self.Roster.IsWritable || self.Roster.IsReadOnly
    label = [label '  (read-only)'];
    self.H.rosterLabel.FontColor = [0.80 0.45 0.05];
else
    self.H.rosterLabel.FontColor = [0.35 0.38 0.42];
end
self.H.rosterLabel.Text = label;
self.H.rosterLabel.Tooltip = self.Roster.FilePath;

% --- projects ------------------------------------------------------------
% A project restored from preferences, or selected programmatically, is applied
% here once the list actually has items.
wanted = self.H.projectList.Value;
if ~isempty(self.PendingProject_)
    wanted = self.PendingProject_;
    self.PendingProject_ = '';
end

projects = self.Roster.Projects;

items = {self.ALL_SUBJECTS};
data  = {''};
if ~isempty(projects)
    [~, order] = sort(lower(string({projects.Name})));
    projects = projects(order);
    items = [items, {projects.Name}];
    data  = [data,  {projects.ProjectID}];
end

self.H.projectList.Items = items;
self.H.projectList.ItemsData = data;

if any(strcmp(wanted, data))
    self.H.projectList.Value = wanted;
else
    self.H.projectList.Value = '';
end

self.updateProjectSummary_();

% --- subjects ------------------------------------------------------------
recs = self.visibleSubjects_();
self.Rows_ = recs;

if isempty(recs)
    self.showEmptyState_(self.emptyStateText_());
    self.H.countLabel.Text = '0 shown';
    self.updateEnableStates_();
    return
end

self.H.emptyState.Visible = 'off';
self.H.table.Visible = 'on';

nRows = numel(recs);
data = cell(nRows, 9);
retired = false(nRows, 1);
projectId = self.selectedProject_();

for i = 1:nRows
    r = recs(i);

    data{i,1} = any(strcmp(r.SubjectID, self.Checked_));
    data{i,2} = r.Name;

    % Empty, not NaN: an unassigned box must read as blank ("one will be
    % chosen for you"), and a numeric column renders NaN literally.
    box = [];
    if self.BoxOverrides_.isKey(r.SubjectID)
        box = self.BoxOverrides_(r.SubjectID);
    end
    data{i,3} = box;

    pfn = self.resolveProtocol_(r.SubjectID);
    if isempty(pfn)
        data{i,4} = '(none)';
    else
        [~, pn, pe] = fileparts(pfn);
        data{i,4} = [pn pe];
    end

    data{i,5} = r.Species;
    data{i,6} = r.Sex;
    data{i,7} = r.Weight;

    [lastRun, isRetired] = localMembershipInfo(self.Roster, r.SubjectID, projectId);
    data{i,8} = lastRun;
    retired(i) = isRetired;
    if isRetired
        data{i,9} = 'Retired';
    else
        data{i,9} = 'Active';
    end
end

self.H.table.Data = data;

% Retired rows are greyed rather than hidden when Show retired is on, so the
% distinction is visible without reading the last column.
try
    removeStyle(self.H.table);
catch
end
if any(retired)
    addStyle(self.H.table, uistyle('FontColor',[0.55 0.58 0.62]), 'row', find(retired));
end

nChecked = numel(self.checkedIds_());
total = numel(self.Roster.Subjects);
self.H.countLabel.Text = sprintf('%d of %d shown \x00B7 %d checked', nRows, total, nChecked);

self.updateEnableStates_();

if ~isempty(self.Roster.LoadError)
    self.setStatus_(self.Roster.LoadError);
elseif isempty(self.H.status.Text)
    self.setStatus_(sprintf('Last read %s', char(datetime('now', Format='HH:mm:ss'))));
end

end

% -----------------------------------------------------------------------
function localClearFlag(self)
self.Refreshing_ = false;
end

% -----------------------------------------------------------------------
function [lastRun, isRetired] = localMembershipInfo(roster, subjectId, projectId)
% Last-run text and retired state for one subject, in a project or anywhere.
lastRun = '';
isRetired = false;

if isempty(roster.Memberships), return, end

mine = roster.Memberships(strcmp({roster.Memberships.SubjectID}, subjectId));
if isempty(mine), return, end

if ~isempty(projectId)
    mine = mine(strcmp({mine.ProjectID}, projectId));
    if isempty(mine), return, end
    isRetired = ~mine(1).Active;
else
    % In the All Subjects view a subject counts as retired only when it is
    % retired everywhere; still active in one study is still active.
    isRetired = ~any([mine.Active]);
end

stamps = [mine.Modified];
stamps = stamps(~isnat(stamps));
if ~isempty(stamps)
    lastRun = char(max(stamps), 'dd-MMM-yyyy HH:mm');
end
end
