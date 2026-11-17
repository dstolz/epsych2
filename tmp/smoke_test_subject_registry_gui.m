function smoke_test_subject_registry_gui()
% smoke_test_subject_registry_gui()
% The lab-database parts of gui.SubjectManager and RunExpt's Customize dialog,
% over FakeSubjectRegistry: with no registry nothing of it shows (lamp, menu,
% column, context item); with one, the column flags endpoints and low weights,
% Link / Unlink / Import / Link Project / Refresh / Retire Endpointed do what
% they say, and Add Checked to Session asks before committing animals the
% registry has concerns about. The operator's answers come through the
% manager's RegistryPickerFcn / RegistryConfirmFcn, so no timer races a modal
% window.
%
% Opens windows: run it on a hidden desktop.
%   matlab -batch "cd('tmp'); smoke_test_subject_registry_gui"
%
% See also: smoke_test_subject_registry, FakeSubjectRegistry, gui.SubjectManager

epsych_startup

savedSubjectPrefs = localSavePrefs('ep_RunExpt_Subjects');
savedGuiPrefs     = localSavePrefs('epsych2_gui_SubjectManager');
savedEPsychPrefs  = localSavePrefs('EPsych');
cleanupPrefs = onCleanup(@() localRestoreAll(savedSubjectPrefs, savedGuiPrefs, savedEPsychPrefs));
cleanupFigs  = onCleanup(@localCloseWindows);
cleanupReg   = onCleanup(@() epsych.SubjectRegistry.current(Reset=true));

root = fullfile(tempdir, 'epsych_registry_gui_smoke');
if isfolder(root), rmdir(root, 's'); end
mkdir(root);
cleanupDir = onCleanup(@() localRemoveDir(root));

if ispref('EPsych', 'SubjectRegistry'), rmpref('EPsych', 'SubjectRegistry'); end
epsych.SubjectRegistry.current(Reset=true);

rosterFile = fullfile(root, 'subjects.esub');
epsych.SubjectRoster.setConfiguredFile(rosterFile);
R = epsych.SubjectRoster(rosterFile);
p1 = R.addProject('Detection');
sA = R.addSubject(struct('Name', 'G001', 'RegistryID', 'SUBJ-ID-1'));
sB = R.addSubject(struct('Name', 'G002', 'RegistryID', 'SUBJ-ID-2'));
sC = R.addSubject(struct('Name', 'SUBJ-ID-3'));
for s = {sA, sB, sC}
    R.assign(s{1}, p1);
end

% 1. No registry: nothing shows -------------------------------------------
localCloseWindows();
gui.SubjectManager([]);
mgr = localManager();
mgr.H.projectList.Value = p1;
mgr.refresh();
assert(strcmp(mgr.H.btnRegistry.Visible, 'off') && strcmp(mgr.H.mnu_registry.Visible, 'off') ...
    && strcmp(mgr.H.cmnu_reg_link.Visible, 'off'), 'With no registry the lamp, menu and context item are hidden');
assert(isequal(mgr.H.rosterGrid.ColumnWidth{2}, 0), 'The lamp takes no space with no registry');
assert(numel(mgr.H.table.ColumnName) == 12 && size(mgr.H.table.Data, 2) == 12, ...
    'With no registry the table keeps its 12 columns');
fprintf('PASS: with no registry the window is unchanged\n');

% 2. A registry: lamp, menu, column, and flags ----------------------------
F = FakeSubjectRegistry();
F.Status = epsych.SubjectRegistry.emptyStatus(["SUBJ-ID-1" "SUBJ-ID-2"]);
F.Status.Known(:) = true;
F.Status.Endpointed(1) = true;
F.Status.EndpointAt(1) = datetime(2026,10,3, 'TimeZone', 'local');
F.Status.WeightG(2) = 50;
F.Status.BaselineG(2) = 80;
F.Status.AsOf(:) = datetime('now', 'TimeZone', 'local');
F.Subjects = table(["SUBJ-ID-3"; "SUBJ-ID-4"; "SUBJ-ID-5"; "SUBJ-ID-9"], ...
    ["Detection"; "Detection"; "Detection"; "Other"], ["proj-1"; "proj-1"; "proj-1"; "proj-2"], ...
    ["Female"; "Male"; "Male"; "Male"], ["Gerbil"; "Gerbil"; "Gerbil"; "Gerbil"], ...
    NaT(4, 1), false(4, 1), 'VariableNames', epsych.SubjectRegistry.emptySubjects().Properties.VariableNames);
F.ProjectsTable = table(["proj-1"; "proj-2"], ["Detection"; "Other"], [true; true], ...
    'VariableNames', {'RegistryID', 'Name', 'IsActive'});
epsych.SubjectRegistry.current(Use = F);
mgr.refresh();
assert(strcmp(mgr.H.btnRegistry.Visible, 'on') && contains(mgr.H.btnRegistry.Text, 'Fake DB: connected'), ...
    'The lamp shows the registry and its state');
assert(strcmp(mgr.H.mnu_registry.Visible, 'on') && strcmp(mgr.H.mnu_registry.Text, 'Fake DB'), ...
    'The menu is shown, named after the registry');
assert(numel(mgr.H.table.ColumnName) == 13 && strcmp(mgr.H.table.ColumnName{13}, 'Fake DB'), ...
    'The registry column is added');
col = string(mgr.H.table.Data(:, 13));
names = string(mgr.H.table.Data(:, 2));
assert(contains(col(names == "G001"), "endpoint 2026-10-03"), 'An endpoint is shown with its date');
assert(contains(col(names == "G002"), "62% of baseline"), 'A low weight is shown against baseline');
assert(col(names == "SUBJ-ID-3") == string(char(8212)), 'An unlinked subject shows a dash');
mgr.H.btnRegistry.ButtonPushedFcn(mgr.H.btnRegistry, []);
assert(F.SettingsOpened == 1, 'The lamp opens the registry settings');
fprintf('PASS: lamp, menu and column follow the registry; flags are shown\n');

% 3. Link and unlink ------------------------------------------------------
rowC = find(names == "SUBJ-ID-3");
mgr.H.table.Selection = rowC;
mgr.RegistryPickerFcn = @(T, varargin) localPick(T, "SUBJ-ID-3");
localMenu(mgr.H.mnu_reg_link);
R.reload();
c = R.findSubject(sC);
assert(strcmp(c.RegistryID, 'SUBJ-ID-3') && strcmp(c.Sex, 'Female'), 'Link stores the id and copies identity');
names = string(mgr.H.table.Data(:, 2));
mgr.H.table.Selection = find(names == "SUBJ-ID-3");
localMenu(mgr.H.mnu_reg_unlink);
R.reload();
assert(isempty(R.findSubject(sC).RegistryID), 'Unlink clears the id');
mgr.RegistryPickerFcn = @(varargin) [];
localMenu(mgr.H.mnu_reg_link);
R.reload();
assert(isempty(R.findSubject(sC).RegistryID), 'A cancelled pick changes nothing');
fprintf('PASS: link and unlink\n');

% 4. Link project, then import from it ------------------------------------
mgr.RegistryPickerFcn = @gui.selectRegistrySubjects;   % unused below; selectFromList is answered by a timer
t = timer('StartDelay', 1.5, 'TimerFcn', @(~,~) localAnswerList(2));
start(t);
localMenu(mgr.H.mnu_reg_link_project);
localKillTimer(t);
R.reload();
assert(strcmp(R.findProject(p1).RegistryID, 'proj-2'), 'Link Project stores the chosen project');
R.updateProject(p1, struct('RegistryID', 'proj-1'));
mgr.RegistryPickerFcn = @(T, varargin) localPick(T, ["SUBJ-ID-4" "SUBJ-ID-5"]);
localMenu(mgr.H.mnu_reg_import);
assert(isfield(F.Filters{end}, 'Project') && F.Filters{end}.Project == "proj-1", ...
    'Import asks for the linked project''s animals');
R.reload();
assert(~isempty(R.findByRegistryID('SUBJ-ID-4')) && ~isempty(R.findByRegistryID('SUBJ-ID-5')), ...
    'Import adds the ticked animals');
assert(numel(R.subjectsInProject(p1)) == 5, 'Imported animals are enrolled in the project');
fprintf('PASS: link project and import\n');

% 5. Refresh and Retire Endpointed ----------------------------------------
localMenu(mgr.H.mnu_reg_refresh);
assert(~isempty(F.Refreshed) && all(ismember(["SUBJ-ID-1" "SUBJ-ID-2"], F.Refreshed{end})), ...
    'Refresh asks about every linked subject');
mgr.RegistryConfirmFcn = @(varargin) 'Cancel';
localMenu(mgr.H.mnu_reg_retire);
R.reload();
assert(R.findMembership(sA, p1).Active, 'Cancelling Retire Endpointed retires nobody');
mgr.RegistryConfirmFcn = @(varargin) 'Retire';
localMenu(mgr.H.mnu_reg_retire);
R.reload();
assert(~R.findMembership(sA, p1).Active && R.findMembership(sB, p1).Active, ...
    'Retire Endpointed retires only the endpointed member');
fprintf('PASS: refresh and retire endpointed\n');

% 6. Add to Session asks first --------------------------------------------
R.setActive(sA, p1, true);
mgr.refresh();
names = string(mgr.H.table.Data(:, 2));
asked = 0;
mgr.RegistryConfirmFcn = @(varargin) localCount('Cancel');
localTick(mgr, find(names == "G001"), true);
mgr.addToSession();
assert(contains(mgr.H.status.Text, 'Not added'), 'Cancelling the warning stops the commit');
mgr.RegistryConfirmFcn = @(varargin) 'Add Anyway';
mgr.addToSession();
assert(~contains(mgr.H.status.Text, 'Not added'), 'Going ahead reaches the commit (no session here, so it reports that)');
localTick(mgr, find(names == "G001"), false);
localTick(mgr, find(names == "SUBJ-ID-3"), true);
mgr.RegistryConfirmFcn = @(varargin) error('smoke:asked', 'should not ask about an animal with no concerns');
mgr.addToSession();
fprintf('PASS: Add to Session warns about endpoints and low weight, and only then\n');

% 7. A broken registry costs nothing --------------------------------------
F.Throw = true;
mgr.refresh();
assert(contains(mgr.H.btnRegistry.Text, 'attention'), 'A throwing registry shows as attention');
mgr.RegistryConfirmFcn = @(varargin) 'Cancel';
mgr.addToSession();   % guard must not block on a broken registry
F.Throw = false;
fprintf('PASS: a broken registry is shown, and blocks nothing\n');

% 8. Customize dialog lists (none) and the running registry ---------------
epsych.SubjectRegistry.current(Reset=true);
delete(findall(groot, 'Type', 'figure', 'Tag', 'RunExpt'));
rx = epsych.RunExpt;
rx.OpenCustomizeDialog();
dlg = findall(groot, 'Type', 'figure', 'Tag', 'RunExptCustomize');
dd = findall(dlg, 'Tag', 'Customize_SubjectRegistry');
assert(isscalar(dd) && strcmp(dd.Items{1}, '(none)') && isempty(dd.Value), ...
    'The Customize dialog offers (none), selected');
st = findall(dlg, 'Tag', 'Customize_RegistryState');
assert(contains(st.Text, 'Off'), 'The state reads Off');
delete(dlg);
assert(~ispref('EPsych', 'SubjectRegistry'), 'Opening the dialog creates no preference');
fprintf('PASS: the Customize dialog offers the registry, off by default\n');

clear cleanupDir cleanupReg cleanupFigs cleanupPrefs
fprintf('ALL SUBJECT REGISTRY GUI SMOKE TESTS PASSED\n');

    function out = localCount(answer)
        asked = asked + 1;
        out = answer;
    end
end

% -----------------------------------------------------------------------
function k = localPick(T, ids)
k = find(ismember(T.RegistryID, ids))';
end

function localMenu(item)
item.MenuSelectedFcn(item, []);
end

function localAnswerList(k)
f = findall(groot, 'Type', 'figure', 'Tag', 'SelectFromList');
if isempty(f), return, end
lb = findall(f, 'Tag', 'SelectFromList_List');
lb.Value = k;
ok = findall(f, 'Tag', 'SelectFromList_OK');
ok.ButtonPushedFcn(ok, []);
end

function mgr = localManager()
mgr = [];
f = findall(groot, 'Type', 'figure', 'Tag', 'EPsychSubjectManager');
if isempty(f), return, end
mgr = f(1).UserData;
end

function localTick(mgr, row, value)
mgr.H.table.Data{row, 1} = value;
mgr.H.table.CellEditCallback([], struct('Indices', [row 1], 'NewData', value, 'PreviousData', ~value));
end

function localKillTimer(t)
if ~isvalid(t), return, end
if strcmp(t.Running, 'on'), stop(t); end
delete(t);
end

function localCloseWindows()
delete(findall(groot, 'Type', 'figure', 'Tag', 'EPsychSubjectManager'));
delete(findall(groot, 'Type', 'figure', 'Tag', 'RunExpt'));
delete(findall(groot, 'Type', 'figure', 'Tag', 'RunExptCustomize'));
delete(findall(groot, 'Type', 'figure', 'Tag', 'SelectFromList'));
end

function saved = localSavePrefs(group)
saved = struct('existed', ispref(group), 'values', struct());
if saved.existed
    saved.values = getpref(group);
end
end

function localRestoreAll(a, b, c)
localRestorePrefs('ep_RunExpt_Subjects', a);
localRestorePrefs('epsych2_gui_SubjectManager', b);
localRestorePrefs('EPsych', c);
end

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

function localRemoveDir(root)
if isfolder(root)
    try
        rmdir(root, 's');
    catch ME
        vprintf(2, ME);
    end
end
end
