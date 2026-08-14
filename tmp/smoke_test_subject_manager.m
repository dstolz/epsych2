function smoke_test_subject_manager()
% smoke_test_subject_manager()
% Exercise gui.SubjectManager without a human: window lifecycle, the
% single-instance rule, filtering, the retired toggle, the remembered project,
% the commit into a session, and — the path most likely to break — opening
% against a completely empty roster.
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
fprintf('PASS: project selection and the retired toggle drive the table\n');

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
assert(~any(cell2mat(mgr.H.table.Data(:,1))), 'Committed rows should be unticked');
fprintf('PASS: ticking, a typed box, and the commit reach CONFIG\n');

% A clean commit puts the session window in front -- groot's children are in
% stacking order -- while leaving this window open behind it.
stack = findall(groot, 'Type','figure');
assert(strcmp(stack(1).Tag, 'RunExpt'), ...
    'The session window should be raised after a clean commit (front was "%s")', stack(1).Tag);
assert(isgraphics(mgr.H.figure), 'The manager should stay open after committing');
fprintf('PASS: the commit raises the session window and keeps this one open\n');

% 6. Remembered project ----------------------------------------------------
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
