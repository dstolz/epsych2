function smoke_test_subject_manager()
% smoke_test_subject_manager()
% Exercise gui.SubjectManager without a human: window lifecycle, the
% single-instance rule, filtering, the retired toggle, the toolbar, the
% remembered project, the commit into a session, and — the path most likely to
% break — opening against a completely empty roster.
%
% Headless-safe: every window is closed before returning, and the user's
% preferences are restored whether it passes or fails.
%
%   matlab -batch "cd('tmp'); smoke_test_subject_manager"
%
% See also: gui.SubjectManager, documentation/gui/gui_SubjectManager.md

epsych_startup

savedSubjectPrefs = localSavePrefs('ep_RunExpt_Subjects');
savedGuiPrefs     = localSavePrefs('epsych2_gui_SubjectManager');

% Self-healing: a run killed before its cleanup leaves RosterFile pointing into
% tempdir, and every later run would faithfully restore that -- which is how a
% rig ends up silently aimed at a folder the OS has since deleted. A roster
% under tempdir is by definition a test artifact, so it is never put back.
savedSubjectPrefs = localDropTempRoster(savedSubjectPrefs);
cleanupPrefs = onCleanup(@() localRestoreAll(savedSubjectPrefs, savedGuiPrefs));
cleanupFigs  = onCleanup(@localCloseWindows);

root = fullfile(tempdir, 'epsych_manager_smoke');
if isfolder(root), rmdir(root, 's'); end
mkdir(root);
cleanupDir = onCleanup(@() localRemoveDir(root));

repoRoot = fileparts(fileparts(mfilename('fullpath')));
proto = fullfile(repoRoot, 'tmp', 'TEST_NEW_PROTOCOL2.eprot');
assert(isfile(proto), 'Test protocol fixture is missing: %s', proto);

% 1. Empty roster, no session ---------------------------------------------
% Both empty states at once: the table is a 0x0 struct and RunExpt is [].
% This is where an unguarded index would throw.
localCloseWindows();
emptyFile = fullfile(root, 'empty.esub');
epsych.SubjectRoster.setConfiguredFile(emptyFile);

gui.SubjectManager([]);
mgr = localManager();
assert(~isempty(mgr), 'The manager window should exist');
assert(isempty(mgr.RunExpt), 'No session should be attached');
assert(strcmp(mgr.H.emptyState.Visible, 'on'), 'The empty state should be showing');
assert(strcmp(mgr.H.btnAddToSession.Enable, 'off'), ...
    'Add to Session must be disabled with no session open');
assert(contains(mgr.H.emptyState.Text, emptyFile), ...
    'The empty state should name where the roster will be created');
fprintf('PASS: opens on an empty roster with no session, and explains both\n');

% 2. Single instance -------------------------------------------------------
gui.SubjectManager([]);
figs = findall(groot, 'Type','figure', 'Tag','EPsychSubjectManager');
assert(isscalar(figs), 'A second construction must replace, not duplicate (found %d)', numel(figs));
fprintf('PASS: only one manager window at a time\n');

% 3. Populate and re-open --------------------------------------------------
localCloseWindows();
rosterFile = fullfile(root, 'subjects.esub');
epsych.SubjectRoster.setConfiguredFile(rosterFile);

R = epsych.SubjectRoster(rosterFile);
p1 = R.addProject('Tone', DefaultProtocol = proto);
p2 = R.addProject('Gap');
ids = cell(1,4);
for k = 1:4
    ids{k} = R.addSubject(struct('Name', sprintf('S%03d',k), 'Sex','Male', ...
        'Species','Gerbil', 'Weight', 60+k));
    R.assign(ids{k}, p1);
end
R.assign(ids{1}, p2);
R.setActive(ids{4}, p1, false);

delete(findall(groot,'Type','figure','Tag','RunExpt'));
rx = epsych.RunExpt;
gui.SubjectManager(rx);
mgr = localManager();

assert(numel(mgr.H.projectList.Items) == 3, ...
    'The list should hold All Subjects plus two projects');

mgr.H.projectList.Value = p1;
mgr.refresh();
assert(size(mgr.H.table.Data,1) == 3, ...
    'A retired member should be hidden by default (got %d rows)', size(mgr.H.table.Data,1));

mgr.H.showRetired.Value = true;
mgr.refresh();
assert(size(mgr.H.table.Data,1) == 4, 'Show retired should reveal the fourth');
mgr.H.showRetired.Value = false;
mgr.refresh();

% The summary is where an operator reads what a project will apply, and the box
% GUI is now one of those things -- named even when the project inherits it, so
% the field cannot look absent.
assert(any(contains(string(mgr.H.projectSummary.Text), 'Behavior GUI: (built-in default)')), ...
    'A project with no behavior GUI should say it inherits the built-in default');
R.updateProject(p1, struct('BehaviorGUI','ep_GenericGUI'));
mgr.refresh();
assert(any(contains(string(mgr.H.projectSummary.Text), 'Behavior GUI: ep_GenericGUI')), ...
    'The summary should name the project''s behavior GUI');
R.updateProject(p1, struct('BehaviorGUI', epsych.SubjectRoster.BEHAVIORGUI_NONE));
mgr.refresh();
assert(any(contains(string(mgr.H.projectSummary.Text), 'Behavior GUI: (none)')), ...
    'A project set to launch no behavior GUI should say so');
R.updateProject(p1, struct('BehaviorGUI',''));
mgr.refresh();
fprintf('PASS: project selection, the retired toggle, and the behavior GUI summary\n');

% 3b. Copy Project needs a project ----------------------------------------
% All three surfaces are switched together in updateEnableStates_, and Copy is
% the one project action that creates something yet is still gated on a
% selection: there is nothing to copy in the All Projects view.
assert(strcmp(mgr.H.btnCopyProject.Enable,'on') && ...
       strcmp(mgr.H.mnu_copy_project.Enable,'on') && ...
       strcmp(mgr.H.tb_copy_project.Enable,'on'), ...
    'Copy Project should be available with a project selected');
mgr.H.projectList.Value = '';   % <All Projects>
mgr.refresh();
assert(strcmp(mgr.H.btnCopyProject.Enable,'off') && ...
       strcmp(mgr.H.mnu_copy_project.Enable,'off') && ...
       strcmp(mgr.H.tb_copy_project.Enable,'off'), ...
    'Copy Project should be off in the All Projects view, like Edit and Delete');
mgr.H.projectList.Value = p1;
mgr.refresh();

% The engine behind the action, exercised where the dialogs cannot be: the copy
% lands in the list, keeps the source intact, and leaves the source's members
% in both projects.
pCopy = R.copyProject(p1, 'Tone (copy)', IncludeSubjects = true);
mgr.refresh();
assert(ismember(pCopy, mgr.H.projectList.ItemsData), ...
    'A copied project should appear in the list after a refresh');
mgr.H.projectList.Value = pCopy;
mgr.refresh();
assert(size(mgr.H.table.Data,1) == 3, ...
    'The copy should hold the three active members (got %d)', size(mgr.H.table.Data,1));
mgr.H.projectList.Value = p1;
mgr.refresh();
assert(size(mgr.H.table.Data,1) == 3, 'The source project must be untouched');
R.deleteProject(pCopy);
mgr.refresh();
fprintf('PASS: Copy Project follows the selection, and a copy shows up in the list\n');

% 4. Filtering -------------------------------------------------------------
mgr.H.filter.Value = 'S002';
mgr.refresh();
assert(size(mgr.H.table.Data,1) == 1 && strcmp(mgr.H.table.Data{1,2}, 'S002'), ...
    'The filter should narrow to one row');

% A string that is a regex but not a substring must match nothing rather
% than raise: this is why the filter uses contains, not regexp.
mgr.H.filter.Value = 'S(0';
mgr.refresh();
assert(size(mgr.H.table.Data,1) == 0, 'A regex-looking filter should simply match nothing');
assert(strcmp(mgr.H.emptyState.Visible,'on'), 'A filter with no matches should show the empty state');

mgr.H.filter.Value = '';
mgr.refresh();
assert(size(mgr.H.table.Data,1) == 3, 'Clearing the filter should restore the rows');
fprintf('PASS: filtering narrows, tolerates regex characters, and clears\n');

% 4b. Live search, anywhere in the name --------------------------------------
% The operator types into the field; ValueChangingFcn fires per keystroke with
% the whole string so far, and Value stays empty until the edit commits. The
% match must be a substring anywhere, not a prefix, and every character typed
% must count -- writing the in-flight text back into Value used to re-render
% the field mid-edit and search only the first character.
for name = {'SUBJ-ID-1231','SUBJ-ID-1232','SUBJ-ID-12314b','SUBJ-ID-9990'}
    id = R.addSubject(struct('Name', name{1}, 'Species','Gerbil'));
    R.assign(id, p1);
end
mgr.refresh();
assert(size(mgr.H.table.Data,1) == 7, 'The four new subjects should be showing');

keystrokes = '123';
for k = 1:numel(keystrokes)
    localType(mgr, keystrokes(1:k));
end

assert(size(mgr.H.table.Data,1) == 3, ...
    'Typing "123" should match every name containing it (got %d rows)', size(mgr.H.table.Data,1));
assert(all(contains(mgr.H.table.Data(:,2), '123')), ...
    'Every matched row should contain the typed text');
assert(isempty(mgr.H.filter.Value), ...
    'The in-flight text must not be written back into the field while typing');

% Backspacing to empty must restore the list, not fall back to stale text.
localType(mgr, '12');
assert(size(mgr.H.table.Data,1) == 3, 'Typing "12" should still match the three');
localType(mgr, '');
assert(size(mgr.H.table.Data,1) == 7, 'Deleting the filter should restore every row');

% Commit, then Clear via the button.
localType(mgr, '1231');
localCommit(mgr, '1231');
assert(size(mgr.H.table.Data,1) == 2, ...
    '"1231" should match the two names containing it (got %d)', size(mgr.H.table.Data,1));
fprintf('PASS: live search matches anywhere in the name, character by character\n');

localClickClear(mgr);
assert(size(mgr.H.table.Data,1) == 7, 'Clear should restore every row');
assert(isempty(mgr.H.filter.Value), 'Clear should empty the field');
fprintf('PASS: Clear drops both the committed and the in-flight filter\n');

% Leave the roster as section 5 expects.
for name = {'SUBJ-ID-1231','SUBJ-ID-1232','SUBJ-ID-12314b','SUBJ-ID-9990'}
    R.deleteSubject(R.findSubject(name{1}).SubjectID);
end
mgr.refresh();
assert(size(mgr.H.table.Data,1) == 3, 'The roster should be back to three visible rows');

% 4c. Toolbar --------------------------------------------------------------
% Every tool must carry a real icon and a tooltip -- a toolbar is icon-only, so
% a tool with neither is unusable -- and its Enable has to track the button and
% menu item for the same action. The three surfaces are switched together in
% updateEnableStates_, so a tool left behind would offer an action the rest of
% the window has already refused.
tools = findall(mgr.H.toolbar, 'Type','uipushtool');
assert(numel(tools) == 15, 'Expected 15 toolbar tools (found %d)', numel(tools));
for tool = tools(:)'
    assert(isequal(size(tool.Icon), [16 16 3]), '%s has no 16x16 icon', tool.Tag);
    assert(~isempty(tool.Tooltip), '%s has no tooltip', tool.Tag);
end

assert(strcmp(mgr.H.tb_add_to_session.Enable,'off'), ...
    'Add to Session should be off with nothing checked');
localTick(mgr, 1, true);
assert(strcmp(mgr.H.tb_add_to_session.Enable,'on'), ...
    'Ticking a row should enable the session tool');
assert(strcmp(mgr.H.tb_add_to_project.Enable,'on'), ...
    'and the project tool with it');
localTick(mgr, 1, false);
assert(strcmp(mgr.H.tb_add_to_session.Enable,'off'), 'Unticking should disable it again');
fprintf('PASS: every tool has an icon and a tooltip, and enabling follows the ticks\n');

% Retire and Restore are one tool wearing two faces. The icon has to follow the
% tooltip: a retired selection offering to retire it again is the one thing an
% icon-only control cannot explain away.
retireIcon = mgr.H.tb_retire.Icon;
mgr.H.showRetired.Value = true;
mgr.refresh();
retiredRow = find(strcmp(mgr.H.table.Data(:,2), 'S004'));
assert(isscalar(retiredRow), 'The retired subject should be showing');

localTick(mgr, retiredRow, true);
assert(contains(mgr.H.tb_retire.Tooltip, 'Restore'), ...
    'A retired selection should offer Restore (got "%s")', mgr.H.tb_retire.Tooltip);
assert(~isequaln(mgr.H.tb_retire.Icon, retireIcon), 'The Restore face needs its own icon');

localTick(mgr, retiredRow, false);
assert(contains(mgr.H.tb_retire.Tooltip, 'Retire'), 'Unticking should put Retire back');
assert(isequaln(mgr.H.tb_retire.Icon, retireIcon), 'and the Retire icon with it');

mgr.H.showRetired.Value = false;
mgr.refresh();
fprintf('PASS: the Retire tool swaps icon and tooltip for Restore\n');

% 5. Tick rows and commit --------------------------------------------------
localTick(mgr, 1, true);
localTick(mgr, 2, true);
localSetBox(mgr, 2, 9);

assert(contains(mgr.H.countLabel.Text, '2 checked'), ...
    'The count label should report two checked (got "%s")', mgr.H.countLabel.Text);
assert(strcmp(mgr.H.btnAddToSession.Enable,'on'), 'Add to Session should be enabled');

mgr.addToSession();

assert(numel(rx.CONFIG) == 2, 'Two subjects should be in CONFIG (got %d)', numel(rx.CONFIG));
boxes = arrayfun(@(c) c.SUBJECT.BoxID, rx.CONFIG);
assert(ismember(9, boxes), 'The typed box should have been honoured (got %s)', mat2str(boxes));
fprintf('PASS: ticking, a typed box, and the commit reach CONFIG\n');

% A clean commit is the end of the visit: the session window comes forward --
% groot's children are in stacking order -- and this window closes itself.
stack = findall(groot, 'Type','figure');
assert(strcmp(stack(1).Tag, 'RunExpt'), ...
    'The session window should be raised after a clean commit (front was "%s")', stack(1).Tag);
assert(~isvalid(mgr), 'The manager should close itself once everything went in');
assert(isempty(localManager()), 'and leave no manager window behind');
fprintf('PASS: the commit raises the session window and closes this one\n');

% 6. Remembered project ----------------------------------------------------
gui.SubjectManager(rx);
mgr = localManager();
mgr.H.projectList.Value = p2;
% Fire the listbox's own callback: only an operator selection is remembered,
% so setting Value alone deliberately does not persist anything.
mgr.H.projectList.ValueChangedFcn(mgr.H.projectList, []);
localCloseWindows();

gui.SubjectManager(rx);
mgr = localManager();
assert(strcmp(mgr.H.projectList.Value, p2), ...
    'The manager should reopen on the project last selected');
fprintf('PASS: the selected project survives closing the window\n');

% 7. revealSubject ---------------------------------------------------------
mgr.revealSubject('S004');
assert(~isempty(mgr.H.table.Selection), 'revealSubject should select a row');
row = mgr.H.table.Selection(1);
assert(strcmp(mgr.H.table.Data{row,2}, 'S004'), ...
    'revealSubject should land on the named subject');

mgr.revealSubject('NOT_IN_ROSTER');
assert(contains(mgr.H.status.Text, 'not in the roster'), ...
    'An unknown subject should be reported, not thrown');
fprintf('PASS: revealSubject finds a retired subject and reports an unknown one\n');

% 7b. Protocol versions ----------------------------------------------------
% The column, the banner, and the fact that both follow the roster. The update
% and revert commands themselves are engine-tested (smoke_test_subject_roster);
% what matters here is that the window notices and stops saying so once fixed.
pvA = fullfile(root, 'phase_a.eprot');
copyfile(proto, pvA);
PA = epsych.Protocol.load(pvA);
PA.save(pvA);
vA1 = epsych.Protocol.versionOnDisk(pvA);

R.updateProject(p1, struct('DefaultProtocol', pvA));
for k = 1:numel(ids)
    R.rememberProtocol(ids{k}, p1, pvA);
end

% Put the view back where this section needs it: revealSubject above leaves
% All Subjects selected with retired rows showing.
localClickClear(mgr);
mgr.H.projectList.Value = p1;
mgr.H.showRetired.Value = false;
mgr.refresh();

col = find(strcmp(mgr.H.table.ColumnName, 'Version'));
assert(isscalar(col), 'The table should carry exactly one Version column');
assert(size(mgr.H.table.Data,1) == 3, ...
    'Expected the three active members of the project, got %d row(s): %s', ...
    size(mgr.H.table.Data,1), mgr.H.emptyState.Text);
assert(all(strcmp(mgr.H.table.Data(:,col), vA1)), ...
    'Every row should show the version recorded for it');
assert(mgr.H.rightGrid.RowHeight{2} == 0, ...
    'The banner must stay collapsed while everyone is on the current version');

% The operator edits and saves the protocol behind the manager's back.
PA.save(pvA);
vA2 = epsych.Protocol.versionOnDisk(pvA);
mgr.refresh();

assert(mgr.H.rightGrid.RowHeight{2} > 0, 'A stale protocol should open the banner');
assert(contains(mgr.H.bannerLabel.Text, 'behind'), ...
    'The banner should say what is wrong (got "%s")', mgr.H.bannerLabel.Text);
assert(all(strcmp(mgr.H.table.Data(:,col), vA1)), ...
    'The column shows the version each subject is on, not the one in the file');

rep = R.updateProtocol(ids(1:3), p1);
assert(rep.ok && numel(rep.updated) == 3, 'All three should have been updated');
mgr.refresh();
assert(mgr.H.rightGrid.RowHeight{2} == 0, 'The banner should close once nothing is behind');
assert(all(strcmp(mgr.H.table.Data(:,col), vA2)), 'The column should show the new version');
fprintf('PASS: the Version column and the stale-protocol banner track the roster\n');

% 7b2. Retired members sit outside the protocol workflow --------------------
% S004 is retired from this project and still recorded on the older version, so
% every version surface has to leave it alone: no banner, no update, no revert.
% What a finished animal is recorded as having run IS the record.
mgr.H.showRetired.Value = true;
mgr.refresh();

rowRetired = find(strcmp(mgr.H.table.Data(:,2), 'S004'));
assert(isscalar(rowRetired), 'The retired subject should be showing');
assert(strcmp(mgr.H.table.Data{rowRetired,col}, vA1), ...
    'The retired member should still be recorded on the version it ran');
assert(mgr.H.rightGrid.RowHeight{2} == 0, ...
    'A retired member behind the file must not open the banner (got "%s")', ...
    mgr.H.bannerLabel.Text);

% Ticking only that row leaves every version action unavailable...
localTick(mgr, rowRetired, true);
assert(strcmp(mgr.H.mnu_update_checked.Enable, 'off'), ...
    'Update Checked should be off when every ticked subject is retired');
assert(strcmp(mgr.H.mnu_use_default.Enable, 'off'), ...
    'Switch to Project Default should be off for the same reason');

% ...and asking for it anyway changes nothing and says why. Checked first on
% purpose: the assertions above fail before this reaches a confirmation dialog,
% so a regression cannot leave a modal waiting on a headless run.
mgr.H.mnu_update_checked.MenuSelectedFcn([], []);
st4 = R.protocolStatus(ids{4}, p1);
assert(strcmp(st4.Version, vA1), 'A retired subject must not be moved onto a newer version');
assert(contains(mgr.H.status.Text, 'retired'), ...
    'The status line should say why nothing happened (got "%s")', mgr.H.status.Text);
localTick(mgr, rowRetired, false);

% Revert is refused by the same rule.
mgr.H.table.Selection = rowRetired;
mgr.H.table.SelectionChangedFcn([], []);
assert(strcmp(mgr.H.mnu_revert.Enable, 'off'), 'Revert should be off on a retired row');

% An active row puts both back, so this is the retired flag and not a stuck menu.
rowActive = find(strcmp(mgr.H.table.Data(:,2), 'S001'));
mgr.H.table.Selection = rowActive;
mgr.H.table.SelectionChangedFcn([], []);
assert(strcmp(mgr.H.mnu_revert.Enable, 'on'), 'Revert should be available on an active row');
localTick(mgr, rowActive, true);
assert(strcmp(mgr.H.mnu_update_checked.Enable, 'on'), ...
    'Update Checked should be available once an active subject is ticked');
localTick(mgr, rowActive, false);

mgr.H.table.Selection = [];
mgr.H.showRetired.Value = false;
mgr.refresh();
fprintf('PASS: retired members are left out of the banner, updates, and revert\n');

% The designer command is wired and refuses politely with nothing selected.
mgr.H.table.Selection = [];
mgr.H.cmnu_open_designer.MenuSelectedFcn([], []);
assert(contains(mgr.H.status.Text, 'Select a subject first'), ...
    'Open in Designer with no selection should ask for one (got "%s")', mgr.H.status.Text);
assert(isempty(findall(groot,'Type','figure','Name','Protocol Designer')), ...
    'Nothing should have been opened');
fprintf('PASS: Open Protocol in Designer is wired and needs a row\n');

% 7c. Project options: links and the archived flag --------------------------
% The summary is the operator's read-only view of what a project carries, the
% link panel is the only clickable thing in this window, and an archived project
% has to be hideable without ever being lost.
L = [epsych.SubjectRoster.makeLink('Notebook','elog.lab.edu/tone'), ...
     epsych.SubjectRoster.makeLink('docs.google.com/spreadsheets/d/1')];
Pu = struct('Investigator','D. Stolzberg', 'IACUCProtocol','R-2026-11');
Pu.Links = L;   % assigned: struct('Links',L) would build one struct per link
R.updateProject(p1, Pu);

mgr.H.projectList.Value = p1;
mgr.refresh();

summary = string(mgr.H.projectSummary.Text);
assert(any(contains(summary, 'Investigator: D. Stolzberg')), ...
    'The summary should name the investigator');
assert(any(contains(summary, 'IACUC: R-2026-11')), ...
    'The summary should carry the IACUC protocol number');

links = mgr.H.projectLinks.Children;
assert(numel(links) == 2, 'Both links should be shown (got %d)', numel(links));
assert(all(arrayfun(@(h) isa(h,'matlab.ui.control.Hyperlink'), links)), ...
    'Links should be clickable hyperlinks, not labels');
% The address lives in the tooltip, not in URL: the click is routed through
% openLink so a stored address is re-checked before anything navigates.
assert(all(arrayfun(@(h) isempty(h.URL), links)), ...
    'A link must not carry a URL that would navigate before it is checked');
assert(any(arrayfun(@(h) strcmp(h.Tooltip,'https://elog.lab.edu/tone'), links)), ...
    'The normalized address should be the tooltip');

% A linkless project must collapse the panel rather than leave a gap.
mgr.H.projectList.Value = p2;
mgr.refresh();
assert(isempty(mgr.H.projectLinks.Children) && mgr.H.projectLinks.RowHeight{1} == 0, ...
    'A project with no links should collapse the link panel');
fprintf('PASS: project links render as checked hyperlinks and collapse when absent\n');

R.updateProject(p2, struct('Archived', true));
mgr.H.showArchived.Value = false;
mgr.H.projectList.Value = p1;
mgr.refresh();
assert(~any(contains(string(mgr.H.projectList.Items), 'Gap')), ...
    'An archived project should be hidden while another is selected');

mgr.H.showArchived.Value = true;
mgr.refresh();
assert(any(contains(string(mgr.H.projectList.Items), 'Gap  (archived)')), ...
    'Show archived should reveal it, marked');
assert(any(strcmp(mgr.H.projectList.ItemsData, p2)), ...
    'The archived project must still be selectable by its ID');

% Selected and then hidden: it has to stay, or the operator loses their place.
mgr.H.projectList.Value = p2;
mgr.H.showArchived.Value = false;
mgr.refresh();
assert(strcmp(mgr.H.projectList.Value, p2), ...
    'The selected archived project must survive turning the toggle off');
assert(any(contains(string(mgr.H.projectSummary.Text), 'Archived')), ...
    'The summary should say a project is archived');
R.updateProject(p2, struct('Archived', false));
mgr.H.projectList.Value = p1;
mgr.refresh();
fprintf('PASS: archived projects hide, stay reachable, and keep the selection\n');

% The dialog itself: modal and blocking, so it is inspected from a timer that
% fires on the queue uiwait is pumping, then cancelled the way the operator would.
built = localDriveProjectDialog(mgr.H.btnEditProject, 'Edit Project');
assert(built.found, 'The Edit Project dialog did not open');
assert(built.links == 2, 'The dialog should seed its link table with both links (got %d)', built.links);
assert(built.hasArchived, 'The dialog should carry the Archived checkbox');
assert(isempty(findall(groot,'Type','figure','Name','Edit Project')), ...
    'Cancel should have closed the dialog');
fprintf('PASS: the project dialog builds, seeds its links, and cancels cleanly\n');

% The same dialog reached through Copy, which is the one caller whose title the
% seed cannot imply: a copy arrives with a name filled in, exactly like an edit.
% Driven from a project with no members, so the "what about the subjects?"
% confirmation -- an in-figure modal the probe cannot reach -- is not raised.
pEmptyProj = R.addProject('LonelyStudy');
mgr.refresh();
mgr.H.projectList.Value = pEmptyProj;
mgr.refresh();
built = localDriveProjectDialog(mgr.H.btnCopyProject, 'Copy Project');
assert(built.found, 'The Copy Project dialog did not open under its own title');
assert(strcmp(built.fields.Name, 'LonelyStudy (copy)'), ...
    'The copy should open on a name that does not collide (got "%s")', built.fields.Name);
assert(isempty(R.findProject('LonelyStudy (copy)')), ...
    'Cancelling the dialog must not have created anything');
R.deleteProject(pEmptyProj);
mgr.H.projectList.Value = p1;
mgr.refresh();
fprintf('PASS: Copy opens the dialog under its own title, on a free name\n');

% 7d. Session defaults: the settings that moved off the Customize dialog ----
% The point of moving them is that they arrive already filled in. A blank field
% would silently inherit whatever the previous study left on the rig, which is
% the ambiguity the move was meant to remove.
assert(any(built.tabs == "Session Defaults (template)"), ...
    'The project dialog should have a Session Defaults (template) tab (got %s)', strjoin(built.tabs, ', '));
for f = ["DefaultDataPath" "SavingFcn" "TimerPeriod" "VideoRootDir" "IntanRootDir" "BehaviorGUI" ...
         "TimerStartFcn" "TimerRunTimeFcn" "TimerStopFcn" "TimerErrorFcn"]
    assert(isfield(built.fields, f), 'The dialog is missing the %s field', f);
    v = built.fields.(f);
    assert(~isempty(v) && (~ischar(v) || ~isempty(strtrim(v))), ...
        'The %s field opened empty; it should be seeded from recents or the machine setting', f);
end
assert(built.fields.TimerPeriod >= 0.001 && built.fields.TimerPeriod <= 1, ...
    'The timer period should open on a usable value (got %g)', built.fields.TimerPeriod);

% Recently-used values seed the next project. Written the way the dialog writes
% them, then read back through a fresh New Project dialog.
setpref('ep_RunExpt_Subjects', 'RecentDataPath',  {fullfile(root,'recent_data')});
setpref('ep_RunExpt_Subjects', 'RecentSavingFcn', {'ep_TimerFcn_Stop'});
setpref('ep_RunExpt_Subjects', 'RecentTimerPeriod', 0.025);

fresh = localDriveProjectDialog(mgr.H.btnNewProject, 'New Project');
assert(fresh.found, 'The New Project dialog did not open');
assert(strcmp(fresh.fields.DefaultDataPath, fullfile(root,'recent_data')), ...
    'A new project should open on the most recently used data path (got "%s")', ...
    fresh.fields.DefaultDataPath);
assert(strcmp(fresh.fields.SavingFcn, 'ep_TimerFcn_Stop'), ...
    'A new project should open on the most recently used saving function (got "%s")', ...
    fresh.fields.SavingFcn);
assert(fresh.fields.TimerPeriod == 0.025, ...
    'A new project should open on the most recently used timer period (got %g)', ...
    fresh.fields.TimerPeriod);
fprintf('PASS: session defaults are seeded, and a new project opens on the last values used\n');

% 7f. The membership dialog and the Settings column -------------------------
% Session settings live on the membership; the Subject menu opens the same
% field grid tagged MembershipDlg_, with no Default Protocol row (a
% membership's protocol goes through the protocol-memory workflow).
mgr.H.projectList.Value = p1;
mgr.refresh();
mgr.H.table.Selection = 1;
mgr.H.table.SelectionChangedFcn([], []);
assert(strcmp(mgr.H.mnu_edit_membership.Enable, 'on'), ...
    'Session Settings... should be enabled with a project and a selected row');

mdlg = localDriveProjectDialog( ...
    @() mgr.H.mnu_edit_membership.MenuSelectedFcn([], []), ...
    sprintf('Session Settings - %s in Tone', mgr.H.table.Data{1,2}), ...
    'MembershipDlg_');
assert(mdlg.found, 'The membership dialog did not open');
assert(~isfield(mdlg.fields, 'DefaultProtocol'), ...
    'The membership dialog must not offer a Default Protocol row');
for f = ["DefaultDataPath" "SavingFcn" "TimerPeriod" "BehaviorGUI" ...
         "TimerStartFcn" "TimerRunTimeFcn" "TimerStopFcn" "TimerErrorFcn" ...
         "VideoRootDir" "IntanRootDir"]
    assert(isfield(mdlg.fields, f), 'The membership dialog is missing the %s field', f);
end

% The Settings column says whether a membership still matches its project's
% template -- what makes the commit-time mismatch refusal predictable.
scol = find(strcmp(mgr.H.table.ColumnName, 'Settings'));
assert(~isempty(scol), 'The table should have a Settings column');
assert(strcmp(mgr.H.table.Data{1,scol}, 'template'), ...
    'A stamped membership should read "template" (got "%s")', mgr.H.table.Data{1,scol});
firstRec = R.findSubject(mgr.H.table.Data{1,2});
firstId = firstRec.SubjectID;
R.updateMembership(firstId, p1, struct('TimerPeriod', 0.5));
mgr.refresh();
assert(strcmp(mgr.H.table.Data{1,scol}, 'edited'), ...
    'A diverged membership should read "edited" (got "%s")', mgr.H.table.Data{1,scol});

% Re-apply Project Template is the named fix: gated on checked rows, and the
% roster method it calls puts the row back on "template".
assert(strcmp(mgr.H.mnu_reapply_template.Enable, 'off'), ...
    'Re-apply should be disabled with nothing checked');
R.reapplyTemplate({firstId}, p1);
mgr.refresh();
assert(strcmp(mgr.H.table.Data{1,scol}, 'template'), ...
    'Re-applying the template should put the row back on "template"');
fprintf('PASS: membership dialog, Settings column, and Re-apply Template\n');

% 7e. No roster file chosen -------------------------------------------------
% What a fresh install looks like. There is no default location any more, so
% the window has to open, explain itself, and leave exactly the three actions
% that would ask for a file switched on -- browsing must never pop a dialog,
% and everything that writes must be unreachable until a file exists.
%
% The prompt itself (gui.SubjectManager.ensureRoster_) is modal and is not
% driven here: uiconfirm would block this test with nothing to click it.
localCloseWindows();
epsych.SubjectRoster.setConfiguredFile('');

gui.SubjectManager([]);
mgr = localManager();
assert(~isempty(mgr), 'The manager must still open with no roster file chosen');
assert(~mgr.Roster.IsBound, 'The roster should be unbound');
assert(contains(mgr.H.rosterLabel.Text, 'no file chosen'), ...
    'The header should say no file is chosen (got "%s")', mgr.H.rosterLabel.Text);
assert(strcmp(mgr.H.emptyState.Visible,'on') && ...
    contains(mgr.H.emptyState.Text, 'No subject roster file has been chosen'), ...
    'The empty state should explain that there is no roster yet');

for on = {'btnNewProject','btnNewSubject','tb_new_project','tb_new_subject'}
    assert(strcmp(mgr.H.(on{1}).Enable, 'on'), ...
        '%s must stay enabled: clicking it is how the operator is asked for a file', on{1});
end
for off = {'btnAddToProject','btnRemoveFromProject','btnRetire','btnEditProject', ...
           'btnDeleteProject','btnAddToSession','btnEditSubject'}
    assert(strcmp(mgr.H.(off{1}).Enable, 'off'), ...
        '%s must be disabled until a roster file exists', off{1});
end
fprintf('PASS: with no roster file the window explains itself and offers only the actions that ask for one\n');

% And the roster itself refuses to be written behind the window's back.
threw = false;
try
    mgr.Roster.addProject('ShouldNotSave');
catch ME
    threw = strcmp(ME.identifier, 'epsych:SubjectRoster:NoFile');
end
assert(threw, 'An unbound roster must refuse a project outright');

localCloseWindows();
epsych.SubjectRoster.setConfiguredFile(rosterFile);
gui.SubjectManager(rx);
mgr = localManager();
% The whole path, not the file name: an operator checking where the records
% live must not have to hover a tooltip to find out.
assert(mgr.Roster.IsBound && strcmp(mgr.H.rosterLabel.Text, ['Roster: ' rosterFile]), ...
    'Pointing the rig back at a file should show the full path (got "%s")', ...
    mgr.H.rosterLabel.Text);
assert(strcmp(mgr.H.btnRosterFile.Enable,'on'), ...
    'Change... must always be available: it is the way out of every roster problem');
fprintf('PASS: naming a file puts the window straight back to work, path in view\n');

% 7f. A configured path whose folder has gone -------------------------------
% The failure this rig actually hit: a roster pointer left behind by a killed
% test, aimed at a temp folder that was later cleaned up. It looked exactly
% like a fresh empty roster, and saveAtomic_ would have re-created the folder
% and saved into it. Both halves are now marked and refused.
localCloseWindows();
goneDir = fullfile(root, 'was_a_share');
mkdir(goneDir);
goneFile = fullfile(goneDir, 'subjects.esub');
epsych.SubjectRoster.setConfiguredFile(goneFile);
rmdir(goneDir, 's');

gui.SubjectManager([]);
mgr = localManager();
assert(contains(mgr.H.rosterLabel.Text, 'folder not found'), ...
    'A stale roster path must be marked, not shown as a normal empty roster (got "%s")', ...
    mgr.H.rosterLabel.Text);
assert(contains(mgr.H.emptyState.Text, 'no longer exists'), ...
    'The empty state should explain a stale path rather than say "no subjects yet"');
assert(~isfolder(goneDir), 'Merely opening the window must not re-create the folder');
fprintf('PASS: a roster path whose folder has gone is marked rather than mistaken for an empty roster\n');

localCloseWindows();
epsych.SubjectRoster.setConfiguredFile(rosterFile);
gui.SubjectManager(rx);
mgr = localManager();

% 8. Teardown --------------------------------------------------------------
delete(mgr);
assert(isempty(findall(groot,'Type','figure','Tag','EPsychSubjectManager')), ...
    'delete should remove the window');
fprintf('PASS: delete tears the window down\n');

localCloseWindows();
fprintf('\nALL SUBJECT MANAGER SMOKE TESTS PASSED\n');

end

% -----------------------------------------------------------------------
function mgr = localManager()
% The live manager object, via its figure's UserData.
mgr = [];
f = findall(groot, 'Type','figure', 'Tag','EPsychSubjectManager');
if isempty(f), return, end
mgr = f(1).UserData;
end

% -----------------------------------------------------------------------
function localType(mgr, sofar)
% One keystroke, the way MATLAB delivers it: ValueChangingFcn carries the whole
% in-flight string while the field's own Value is still the last committed one.
mgr.H.filter.ValueChangingFcn(mgr.H.filter, struct('Value', sofar));
end

% -----------------------------------------------------------------------
function localCommit(mgr, text)
% Enter or focus loss: MATLAB updates Value first, then fires ValueChangedFcn.
mgr.H.filter.Value = text;
mgr.H.filter.ValueChangedFcn(mgr.H.filter, []);
end

% -----------------------------------------------------------------------
function localClickClear(mgr)
% Press the Clear button in the filter strip.
b = findall(mgr.H.figure, 'Type','uibutton', 'Text','Clear');
assert(isscalar(b), 'Expected exactly one Clear button (found %d)', numel(b));
b.ButtonPushedFcn(b, []);
end

% -----------------------------------------------------------------------
function localTick(mgr, row, value)
% Tick a checkbox the way the table's own callback would.
mgr.H.table.Data{row,1} = value;
mgr.H.table.CellEditCallback([], struct( ...
    'Indices', [row 1], 'NewData', value, 'PreviousData', ~value));
end

% -----------------------------------------------------------------------
function localSetBox(mgr, row, value)
% Type a box number the way the table's own callback would.
previous = mgr.H.table.Data{row,3};
mgr.H.table.Data{row,3} = value;
mgr.H.table.CellEditCallback([], struct( ...
    'Indices', [row 3], 'NewData', value, 'PreviousData', previous));
end

% -----------------------------------------------------------------------
function built = localDriveProjectDialog(control, name, tagPrefix)
% Press a control that opens a modal project dialog, record what it built, and
% cancel it. control is a button, or a function handle that launches the
% dialog (the membership dialog opens from a menu item, which has no
% ButtonPushedFcn); tagPrefix defaults to the project dialog's.
%
% projectDialog_ blocks in uiwait, so nothing written after the click runs until
% the dialog closes; the inspection has to happen in a timer callback, which
% fires on the same event queue uiwait is pumping. The timer repeats instead of
% firing once, and its StopFcn deletes whatever is still standing: a probe that
% merely missed the window would otherwise hang this test forever rather than
% fail it.
built = struct('found', false, 'links', 0, 'hasArchived', false, ...
    'tabs', strings(1,0), 'fields', struct());

if nargin < 3, tagPrefix = 'ProjectDlg_'; end

t = timer('Name','projectDialogProbe', ...
    'ExecutionMode','fixedSpacing', 'Period', 0.5, 'TasksToExecute', 20, ...
    'TimerFcn', @(~,~) localInspect(), ...
    'StopFcn', @(~,~) localForceClose());
cleanupTimer = onCleanup(@() localKillTimer(t));
start(t);

if isa(control, 'function_handle')
    control();
else
    control.ButtonPushedFcn(control, []);
end

    function localInspect()
        dlg = findall(groot, 'Type','figure', 'Name', name);
        if isempty(dlg), return, end
        dlg = dlg(1);

        % The figure carries its Name from the moment it is created, so it is
        % findable while its controls are still being laid out. Cancel is the
        % last thing projectDialog_ builds: until it exists, this tick is too
        % early, and acting on it would tear the window down mid-construction.
        cancelBtn = findall(dlg, 'Type','uibutton', 'Text','Cancel');
        if isempty(cancelBtn), return, end

        built.found = true;

        tbl = findall(dlg, 'Type','uitable');
        if ~isempty(tbl)
            built.links = size(tbl(1).Data, 1);
        end
        built.hasArchived = ~isempty(findall(dlg, 'Type','uicheckbox'));

        % The membership dialog has no tabs; an empty findall result is a
        % GraphicsPlaceholder whose .Title would throw.
        tabs = findall(dlg, 'Type','uitab');
        if ~isempty(tabs)
            built.tabs = string({tabs.Title});
        end

        % Session defaults by Tag rather than by label, so rewording a label
        % does not silently stop this from checking anything.
        for h = findall(dlg, '-regexp', 'Tag', ['^' tagPrefix])'
            built.fields.(erase(h.Tag, tagPrefix)) = h.Value;
        end

        cancelBtn(1).ButtonPushedFcn(cancelBtn(1), []);

        stop(t);
    end

    function localForceClose()
        % Deleting the figure is what releases uiwait when Cancel could not be
        % found or pressed.
        for dlg = findall(groot, 'Type','figure', 'Name', name)'
            dlg.CloseRequestFcn = '';
            delete(dlg);
        end
    end
end

% -----------------------------------------------------------------------
function localKillTimer(t)
if ~isvalid(t), return, end
if strcmp(t.Running, 'on'), stop(t); end
delete(t);
end

% -----------------------------------------------------------------------
function localCloseWindows()
delete(findall(groot, 'Type','figure', 'Tag','EPsychSubjectManager'));
delete(findall(groot, 'Type','figure', 'Tag','RunExpt'));
end

% -----------------------------------------------------------------------
function saved = localSavePrefs(group)
saved = struct('existed', ispref(group), 'values', struct());
if saved.existed
    saved.values = getpref(group);
end
end

% -----------------------------------------------------------------------
function localRestoreAll(savedSubjectPrefs, savedGuiPrefs)
localRestorePrefs('ep_RunExpt_Subjects', savedSubjectPrefs);
localRestorePrefs('epsych2_gui_SubjectManager', savedGuiPrefs);
end

% -----------------------------------------------------------------------
function saved = localDropTempRoster(saved)
% Drop a RosterFile that points into tempdir from a preference snapshot.
if ~saved.existed || ~isfield(saved.values, 'RosterFile'), return, end

p = char(string(saved.values.RosterFile));
if startsWith(lower(p), lower(tempdir))
    fprintf('NOTE: dropping a stale test roster path from the preferences: %s\n', p);
    saved.values = rmfield(saved.values, 'RosterFile');
end
end

% -----------------------------------------------------------------------
function localRestorePrefs(group, saved)
if ispref(group)
    rmpref(group);
end
if ~saved.existed, return, end
names = fieldnames(saved.values);
for i = 1:numel(names)
    setpref(group, names{i}, saved.values.(names{i}));
end
end

% -----------------------------------------------------------------------
function localRemoveDir(root)
if isfolder(root)
    try
        rmdir(root, 's');
    catch ME
        vprintf(2, ME);
    end
end
end
