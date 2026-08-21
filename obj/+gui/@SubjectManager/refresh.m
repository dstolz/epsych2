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
    self.H.rosterLabel.Text = 'Roster: (none)';
    self.showEmptyState_('The subject roster could not be opened. Use Roster File... to choose one.');
    self.updateEnableStates_();
    return
end

% No roster file has been chosen on this workstation. Not an error state and
% not a dialog: browsing is harmless, so the window explains itself and waits.
% The demand comes from ensureRoster_, at the first action that would write.
if ~self.Roster.IsBound
    self.H.rosterLabel.Text = 'Roster: (no file chosen)';
    self.H.rosterLabel.FontColor = [0.80 0.45 0.05];
    self.H.rosterLabel.Tooltip = '';
    self.H.projectList.Items = {self.ALL_SUBJECTS};
    self.H.projectList.ItemsData = {''};
    self.H.projectList.Value = '';
    self.updateProjectSummary_();
    self.Rows_ = [];
    self.Statuses_ = [];
    self.Retired_ = [];
    self.showVersionBanner_('');
    self.showEmptyState_(self.emptyStateText_());
    self.H.countLabel.Text = '';
    self.updateEnableStates_();
    return
end

if opts.Reload
    self.Roster.reload();
end

% The whole path, not the file name: which of two rosters this is, and whether
% it is somewhere sensible, is exactly what an operator comes here to check.
label = ['Roster: ' self.Roster.FilePath];

% A configured path whose FOLDER is gone is a stale pointer, not a roster
% waiting to be created -- a share that moved, a drive that is not mounted, a
% temp folder that was cleaned up. Left unmarked it looks identical to a fresh
% empty roster, which is how a rig can quietly appear to have lost every
% animal. Naming a file inside a folder that DOES exist stays silent: that is
% the normal way to start one.
if self.rosterFolderMissing_()
    label = [label '   (folder not found)'];
    self.H.rosterLabel.FontColor = [0.80 0.45 0.05];
elseif ~self.Roster.IsWritable || self.Roster.IsReadOnly
    label = [label '   (read-only)'];
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

% An archived project is hidden, never dropped -- except the one currently
% selected, which stays listed so it cannot vanish out from under an operator
% who is looking at it, or who has just archived it from the edit dialog.
if ~isempty(projects) && ~self.H.showArchived.Value
    keep = ~[projects.Archived] | strcmp({projects.ProjectID}, wanted);
    projects = projects(keep);
end

items = {self.ALL_SUBJECTS};
data  = {''};
if ~isempty(projects)
    [~, order] = sort(lower(string({projects.Name})));
    projects = projects(order);

    % Marked in the item text because a uilistbox has no per-item styling.
    names = {projects.Name};
    archived = [projects.Archived];
    names(archived) = strcat(names(archived), '  (archived)');

    items = [items, names];
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
    self.Statuses_ = [];
    self.Retired_ = [];
    self.showVersionBanner_('');
    self.showEmptyState_(self.emptyStateText_());
    self.H.countLabel.Text = '0 shown';
    self.updateEnableStates_();
    return
end

self.H.emptyState.Visible = 'off';
self.H.table.Visible = 'on';

nRows = numel(recs);
data = cell(nRows, 11);
retired = false(nRows, 1);
projectId = self.selectedProject_();

% The template the Settings column compares against, fetched once per repaint.
project = [];
if ~isempty(projectId)
    project = self.Roster.findProject(projectId);
end

% One engine call for the whole table rather than one per row: the roster
% caches its file reads across the batch, so a project on a single protocol
% peeks at that .eprot once per repaint.
self.Statuses_ = self.Roster.protocolStatus({recs.SubjectID}, projectId);
versionFlag = zeros(nRows, 1);   % 0 neutral, 1 needs attention, 2 muted

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

    [data{i,4}, data{i,5}, versionFlag(i)] = self.protocolCells_(r.SubjectID, self.Statuses_(i));

    [lastRun, isRetired, mrec] = localMembershipInfo(self.Roster, r.SubjectID, projectId);
    data{i,6} = localSettingsCell(project, mrec);

    data{i,7} = r.Species;
    data{i,8} = r.Sex;
    data{i,9} = r.Weight;

    data{i,10} = lastRun;
    retired(i) = isRetired;
    if isRetired
        data{i,11} = 'Retired';
    else
        data{i,11} = 'Active';
    end
end

self.H.table.Data = data;
self.Retired_ = retired;

% Retired rows are greyed rather than hidden when Show retired is on, so the
% distinction is visible without reading the last column.
try
    removeStyle(self.H.table);
catch
end
if any(retired)
    addStyle(self.H.table, uistyle('FontColor',[0.55 0.58 0.62]), 'row', find(retired));
end

% A retired member is out of the version workflow entirely: nothing here will
% update it, so drawing it as needing attention would be an alarm with no
% action behind it. Its version is muted instead, and it is counted out of the
% banner and the tooltip -- which speak for the Update All button, and so must
% describe exactly the subjects that button would move.
versionFlag(retired & versionFlag == 1) = 2;
localStyleVersions(self.H.table, versionFlag);
self.showVersionBanner_(localBannerText(self.Statuses_(~retired)));
self.H.table.Tooltip = localTableTooltip(self.Statuses_(~retired));

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
function localStyleVersions(tbl, flag)
% Colour the Version cell by how much attention it wants.
%
% Only "the file moved on without you" is a warning. A subject that has simply
% never run has no version to be behind, and colouring that would make a fresh
% project of sixteen animals light up entirely orange.
warn = find(flag == 1);
if ~isempty(warn)
    addStyle(tbl, uistyle('FontColor',[0.80 0.36 0.02], 'FontWeight','bold'), ...
        'cell', [warn, repmat(5, numel(warn), 1)]);
end

muted = find(flag == 2);
if ~isempty(muted)
    addStyle(tbl, uistyle('FontColor',[0.55 0.58 0.62]), ...
        'cell', [muted, repmat(5, numel(muted), 1)]);
end

% Held on an earlier version on purpose: blue rather than the warning orange,
% because there is nothing here for the operator to put right.
held = find(flag == 3);
if ~isempty(held)
    addStyle(tbl, uistyle('FontColor',[0.13 0.40 0.72], 'FontWeight','bold'), ...
        'cell', [held, repmat(5, numel(held), 1)]);
end
end

% -----------------------------------------------------------------------
function txt = localBannerText(st)
% The one-line summary above the table, or '' to collapse it.
txt = '';
if isempty(st), return, end

nBehind  = nnz(strcmp({st.Status}, 'outdated'));
nMissing = nnz(strcmp({st.Status}, 'missing'));
nDiffers = nnz(strcmp({st.Status}, 'differs'));
nHeld    = nnz(strcmp({st.Status}, 'pinned'));

parts = {};
if nBehind > 0
    parts{end+1} = sprintf('%d subject(s) are behind the protocol saved on disk', nBehind);
end
% Stated but never the reason the banner opens: a held subject is somebody's
% decision, so it is worth seeing next to the counts that are problems, and
% not worth a strip of its own over an otherwise healthy project.
if nHeld > 0 && ~isempty(parts)
    parts{end+1} = sprintf('%d held on an earlier version', nHeld);
end
if nMissing > 0
    parts{end+1} = sprintf('%d protocol file(s) are missing', nMissing);
end
if nDiffers > 0
    parts{end+1} = sprintf('%d are not on the project default', nDiffers);
end
if isempty(parts), return, end

txt = [upper(parts{1}(1)) parts{1}(2:end)];
if numel(parts) > 1
    txt = sprintf('%s; %s', txt, strjoin(parts(2:end), '; '));
end
txt = [txt '.'];
end

% -----------------------------------------------------------------------
function tip = localTableTooltip(st)
% Name the subjects behind the file, rather than only counting them.
%
% Held subjects are named too: the Version cell says a hold exists, and this is
% where what it is held against is written down.
base = 'Right-click a subject to set, update, revert, or open its protocol.';
tip = base;
if isempty(st), return, end

behind = st(strcmp({st.Status}, 'outdated') | strcmp({st.Status}, 'missing') ...
    | strcmp({st.Status}, 'pinned'));
if isempty(behind), return, end

lines = arrayfun(@(s) sprintf('%s: %s', s.Name, s.Message), behind, 'uni', 0);
tip = [{base, ''}, lines(:)'];
end

% -----------------------------------------------------------------------
function txt = localSettingsCell(project, mrec)
% The Settings cell: does this membership still match the project's template?
% '' outside a project view or with no membership -- there is nothing to
% compare. isequaln so two "inherit" TimerPeriods (NaN) agree, matching the
% commit-time mismatch check this column exists to make predictable.
txt = '';
if isempty(project) || isempty(mrec), return, end

txt = 'template';
for f = epsych.SubjectRoster.SESSION_FIELDS
    pv = project.(f{1});
    mv = mrec.(f{1});
    % Both-empty agrees whatever the shapes: a stamped '' comes back from a
    % MAT round trip as 1x0 while a fresh record holds 0x0, and isequaln
    % alone would flag every untouched membership as edited.
    if isempty(pv) && isempty(mv), continue, end
    if ~isequaln(pv, mv)
        txt = 'edited';
        return
    end
end
end

% -----------------------------------------------------------------------
function [lastRun, isRetired, mrec] = localMembershipInfo(roster, subjectId, projectId)
% Last-run text, retired state, and (in a project view) the membership record
% itself for one subject.
lastRun = '';
isRetired = false;
mrec = [];

if isempty(roster.Memberships), return, end

mine = roster.Memberships(strcmp({roster.Memberships.SubjectID}, subjectId));
if isempty(mine), return, end

if ~isempty(projectId)
    mine = mine(strcmp({mine.ProjectID}, projectId));
    if isempty(mine), return, end
    isRetired = ~mine(1).Active;
    mrec = mine(1);
else
    % In the All Projects view a subject counts as retired only when it is
    % retired everywhere; still active in one study is still active.
    isRetired = ~any([mine.Active]);
end

stamps = [mine.Modified];
stamps = stamps(~isnat(stamps));
if ~isempty(stamps)
    lastRun = char(max(stamps), 'dd-MMM-yyyy HH:mm');
end
end
