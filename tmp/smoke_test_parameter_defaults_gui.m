function smoke_test_parameter_defaults_gui()
% smoke_test_parameter_defaults_gui()
% The windows and the run path behind per-subject parameter defaults:
%   1) a roster commit links each CONFIG entry to its membership
%   2) gui.ParameterDefaultsEditor lists the protocol, flags a stale default,
%      takes and refuses edits through the real table callback, filters,
%      clears, saves (firing DefaultsSaved), and is one window per membership
%   3) Copy from Session is refused before the subject has run
%   4) a real Preview applies the defaults at Run -- including ones saved
%      AFTER the subject was added -- recompiles, reaches an Expression that
%      reads a defaulted parameter, and notes what it applied
%   5) Copy from Session after the run takes the trial-table value and a live
%      bound that differ, and leaves matching ones alone
%   6) View Trials previews with the defaults
%   7) a default removed between runs is put back to the protocol's value on
%      the next Preview
%   8) Copy from Last Data File finds the newest saved session
%   9) gui.SubjectManager: the Settings column counts defaults, the right-click
%      item opens the row under the pointer, the Subject-menu item the selected
%      row (not a stale right-click), and a save repaints the column
%
% Run headless: matlab -batch "run('tmp/smoke_test_parameter_defaults_gui.m')"
%
% See also: gui.ParameterDefaultsEditor, epsych.ParameterDefaults

here = fileparts(mfilename('fullpath'));
run(fullfile(here, '..', 'epsych_startup.m'));
addpath(here);
addpath(fullfile(here, '..', 'examples', 'detection_task'));

groups = {'ep_RunExpt_Subjects', 'ep_RunExpt_Setup'};
saved = cellfun(@(g) localSavePrefs(g), groups, 'uni', 0);
cleanupPrefs = onCleanup(@() localRestoreAll(groups, saved));

root = fullfile(tempdir, 'epsych_paramdefaults_gui');
if isfolder(root), rmdir(root, 's'); end
mkdir(root);
cleanupDir = onCleanup(@() localRemoveDir(root));
cleanupFigs = onCleanup(@() localCloseAll());

dataRoot = fullfile(root, 'data');
mkdir(dataRoot);
protoFile = fullfile(root, 'DetectionExample.eprot');
create_detection_protocol(protoFile);

rosterFile = fullfile(root, 'lab.esub');
epsych.SubjectRoster.setConfiguredFile(rosterFile);
R = epsych.SubjectRoster(rosterFile);
pid = R.addProject('PD Study', DefaultProtocol = protoFile, DefaultDataPath = dataRoot, ...
    SavingFcn = 'ep_SaveDataFcn', BehaviorGUI = epsych.SubjectRoster.BEHAVIORGUI_NONE);
s1 = R.addSubject(struct('Name', 'PDG1', 'Sex', 'Male', 'Species', 'Mouse'));
s2 = R.addSubject(struct('Name', 'PDG2', 'Sex', 'Male', 'Species', 'Mouse'));
R.assign(s1, pid);
R.assign(s2, pid);
R.rememberProtocol(s1, pid, protoFile);
R.rememberProtocol(s2, pid, protoFile);

P0 = epsych.Protocol.load(protoFile);
sw = P0.Interfaces(1);
iface = char(sw.Type);
modName = sw.find_parameter('ToneFreq').Module.Name;
mk = @(name, value, lo, hi) localRecord(iface, modName, name, value, lo, hi);

% A default the protocol does not have, to be flagged as stale.
R.setParameterDefaults(s1, pid, [mk('RewardVol', 40, NaN, NaN), mk('Gone', 5, NaN, NaN)]);

% 1. The commit links CONFIG to the membership ----------------------------
delete(findall(groot, 'Type', 'figure', 'Tag', 'RunExpt'));
rx = epsych.RunExpt("PD Study", Subjects = "PDG1", ReuseExisting = false);
L = rx.CONFIG(1).ROSTER;
assert(isstruct(L) && strcmp(L.SubjectID, s1) && strcmp(L.ProjectID, pid) ...
    && strcmpi(L.File, rosterFile) && numel(L.ParameterDefaults) == 2, ...
    'the commit must link the CONFIG entry to its membership and copy its defaults');
fprintf('PASS: a roster commit links CONFIG to the membership\n');

% 2. The editor ------------------------------------------------------------
E = gui.ParameterDefaultsEditor.open(R, 'PDG1', 'PD Study', RunExpt = rx);
fig = E.H.figure;
names = {E.Rows.Name};
assert(all(ismember({'ToneFreq','ToneDur','RewardVol','ITI','ToneLevel','TrialType'}, names)), ...
    'the editor must list the protocol''s eligible parameters');
assert(~any(ismember({'RespWinDelay','RespCode','x_NewTrial_1','Reward'}, names)), ...
    'expressions, read-only parameters and triggers must not be listed');
gone = E.Rows(strcmp(names, 'Gone'));
assert(isscalar(gone) && gone.Stale && contains(gone.Problem, 'not in this protocol'), ...
    'a default the protocol lacks must be listed as stale');
iti = E.Rows(strcmp(names, 'ITI'));
assert(~iti.Eligibility.CanSetValue && iti.Eligibility.CanSetBounds, 'ITI is randomized: bounds only');

k = localTableRow(E, 'RewardVol');
assert(strcmp(E.H.table.Data{k, 5}, '40'), 'the stored default must show in the Default column');
assert(~isempty(E.H.table.StyleConfigurations), 'defaults and greyed cells must be styled');

% An edit through the table's own callback.
k = localTableRow(E, 'ToneFreq');
E.H.table.CellEditCallback(E.H.table, struct('Indices', [k 5], 'NewData', '8000'));
assert(isequal(E.Rows(strcmp(names, 'ToneFreq')).Value, 8000) && E.IsModified, ...
    'a typed default must land in the row');
assert(endsWith(fig.Name, '*'), 'unsaved edits must mark the title');
assert(strcmp(E.H.table.Data{k, 5}, '8000'), 'the table must show the new default');

% A refused edit is put back and explained.
E.H.table.CellEditCallback(E.H.table, struct('Indices', [k 5], 'NewData', 'eight'));
assert(isequal(E.Rows(strcmp(names, 'ToneFreq')).Value, 8000) && strcmp(E.H.table.Data{k, 5}, '8000'), ...
    'a refused edit must leave the row and the cell as they were');
assert(contains(E.H.status.Text, 'not a number'), 'a refused edit must say why');

% The public methods redraw too, so a script sees what the table shows.
[ok, msg] = E.setDefault('ToneDur', '250');
assert(ok, msg);
assert(strcmp(E.H.table.Data{localTableRow(E, 'ToneDur'), 5}, '250') && logical(E.H.btnSave.Enable), ...
    'a default set through setDefault must show in the table and enable Save');

% Bounds: a Max below the row's own value is refused; ITI bounds are fine.
[ok, msg] = E.setBound('ToneDur', 'Max', '100');
assert(~ok && contains(msg, 'outside'), 'a bound that strands the value must be refused');
kI = localTableRow(E, 'ITI');
E.H.table.CellEditCallback(E.H.table, struct('Indices', [kI 6], 'NewData', '2500'));
E.H.table.CellEditCallback(E.H.table, struct('Indices', [kI 7], 'NewData', '3500'));
iti = E.Rows(strcmp(names, 'ITI'));
assert(iti.Min == 2500 && iti.Max == 3500, 'randomized bounds must take edits');
[ok, ~] = E.setDefault('ITI', '3000');
assert(~ok, 'a randomized parameter must refuse a value');

% A paired list keeps its length.
[ok, ~] = E.setDefault('ToneLevel', '30');
assert(~ok, 'a paired parameter must refuse a different level count');
[ok, msg] = E.setDefault('ToneLevel', '25, 35, 45, 55, 65, 0');
assert(ok, msg);

% The stale row can only be cleared.
[ok, ~] = E.setDefault('Gone', '6');
assert(~ok, 'a stale default must refuse a new value');
[ok, msg] = E.setDefault('Gone', '');
assert(ok, msg);

% Filter as typed, then committed empty.
E.H.filter.ValueChangingFcn(E.H.filter, struct('Value', 'tone'));
shown = E.H.table.Data(:, 1);
assert(~isempty(shown) && all(contains(lower(shown), 'tone')), 'typing must narrow the list');
E.H.filter.Value = '';
E.H.filter.ValueChangedFcn(E.H.filter, []);
assert(size(E.H.table.Data, 1) >= numel(E.Rows) - 1, 'clearing the filter must bring every row back');

% Only rows with defaults.
E.H.chkOnlySet.Value = true;
E.H.chkOnlySet.ValueChangedFcn(E.H.chkOnlySet, []);
shownNames = regexprep(E.H.table.Data(:, 1), '^.*\.', '');
assert(isempty(setxor(shownNames, {'ToneFreq','ToneDur','RewardVol','ITI','ToneLevel','Gone'})), ...
    'Only parameters with defaults must show exactly those (the cleared stale row stays until saved)');
E.H.chkOnlySet.Value = false;
E.H.chkOnlySet.ValueChangedFcn(E.H.chkOnlySet, []);

% Clear Selected on two rows at once.
E.setDefault('ToneFreq', '8000');
E.H.table.Selection = [localTableRow(E, 'ToneDur'), localTableRow(E, 'RewardVol')];
E.H.btnClear.ButtonPushedFcn(E.H.btnClear, []);
assert(isempty(E.Rows(strcmp(names, 'ToneDur')).Value) && isempty(E.Rows(strcmp(names, 'RewardVol')).Value), ...
    'Clear Selected must clear every selected row');
E.setDefault('ToneDur', '250');
E.setDefault('RewardVol', '40');

% Save, and the event.
setappdata(groot, 'PDGSaved', 0);
lh = listener(E, 'DefaultsSaved', @(~, ~) setappdata(groot, 'PDGSaved', getappdata(groot, 'PDGSaved') + 1));
assert(E.save(), 'save must succeed');
assert(getappdata(groot, 'PDGSaved') == 1 && ~E.IsModified && ~endsWith(fig.Name, '*'), ...
    'save must fire DefaultsSaved once and clear the modified mark');
D = epsych.SubjectRoster(rosterFile).parameterDefaults(s1, pid);
assert(isempty(setxor({D.Name}, {'ToneFreq','ToneDur','RewardVol','ITI','ToneLevel'})), ...
    'the roster must hold exactly the rows left set (the stale one cleared)');
delete(lh);

% One window per membership.
E2 = gui.ParameterDefaultsEditor.open(R, s1, pid, RunExpt = rx);
assert(E2 == E && numel(findall(groot, 'Type', 'figure', 'Tag', 'EPsychParameterDefaultsEditor')) == 1, ...
    'opening again must raise the same window');
fprintf('PASS: the editor lists, edits, refuses, filters, clears, and saves\n');

% 3. Copy from Session before any run --------------------------------------
rep = E.copyFromSession();
assert(isempty(rep.Copied) && contains(rep.Message, 'has not run'), ...
    'Copy from Session must refuse before the subject has run');
fprintf('PASS: Copy from Session waits for a run\n');

% 4. A real Preview applies the defaults saved after the commit -------------
rx.H.ctrl_preview.ButtonPushedFcn(rx.H.ctrl_preview, []);
assert(localWaitFor(@() rx.STATE == PRGMSTATE.RUNNING, 30), ...
    'the preview never reached RUNNING (got %s)', char(string(rx.STATE)));
pause(0.5);
PP = rx.CONFIG(1).PROTOCOL;
q = @(n) PP.Interfaces(1).find_parameter(n);
assert(isequal(q('ToneFreq').Values, {8000}) && isequal(q('RewardVol').Values, {40}), ...
    'Run must apply the defaults saved after the subject was added');
assert(q('ITI').Min == 2500 && q('ITI').Max == 3500 && q('ITI').Value >= 2500 && q('ITI').Value <= 3500, ...
    'the randomized ITI must draw inside the subject''s bounds');
cols = {PP.COMPILED.parameters.Name};
tf = PP.COMPILED.trials(:, strcmp(cols, 'ToneFreq'));
tl = cell2mat(PP.COMPILED.trials(:, strcmp(cols, 'ToneLevel')));
assert(all(cellfun(@(v) v == 8000, tf)) && isempty(setxor(tl, [25 35 45 55 65 0])), ...
    'the trial table must be recompiled from the defaults');
assert(q('RespWinDelay').Value == 250 + 250, ...
    'an Expression reading a defaulted parameter must see the default (ToneDur + 250)');
recs = rx.RUNTIME.NOTES.Records;
hit = recs(contains({recs.Text}, 'Subject parameter defaults applied'));
assert(isscalar(hit) && contains(hit.Text, 'ToneFreq = 8000') && hit.Subject == 1 && hit.Trial == 0, ...
    'what was applied must be one session note, tagged with the subject and stamped trial 0');
assert(contains(strjoin(rx.RUNTIME.NOTES.render(Subject = 1), newline), 'ToneFreq = 8000'), ...
    'the note must be in the subject''s rendered log');
rx.halt;
assert(localWaitFor(@() rx.STATE == PRGMSTATE.STOP, 30), 'halt never reached STOP');
fprintf('PASS: Preview applies the current defaults, recompiles, and notes them\n');

% 5. Copy from Session after the run ---------------------------------------
T = rx.RUNTIME.TRIALS;
col = T(1).writeParamIdx.ToneFreq;
T(1).trials(:, col) = {6000};
rx.RUNTIME.TRIALS = T;
pITI = q('ITI');
pITI.Max = 3900;
rep = E.copyFromSession();
assert(isempty(setxor(rep.Copied, {[modName '.ToneFreq'], [modName '.ITI']})), ...
    'Copy from Session must take exactly what differs (got %s)', strjoin(rep.Copied, ', '));
assert(isequal(E.Rows(strcmp(names, 'ToneFreq')).Value, 6000), 'the committed trial-table value must win');
assert(E.Rows(strcmp(names, 'ITI')).Max == 3900, 'a live bound must be copied');
assert(isequal(E.Rows(strcmp(names, 'RewardVol')).Value, 40), 'a matching default must be left alone');
assert(E.save(), 'save after copy');
fprintf('PASS: Copy from Session takes the differences\n');

% 6. View Trials previews with the defaults --------------------------------
before = findall(groot, 'Type', 'figure');
rx.H.subject_list.Selection = [1 1];   % cell selection: row 1
rx.ViewTrials();
vt = setdiff(findall(groot, 'Type', 'figure'), before);
assert(isscalar(vt) && startsWith(vt.Name, 'Compiled Trials'), 'View Trials must open its window');
lbl = findall(vt, 'Type', 'uilabel');
assert(any(contains({lbl.Text}, 'subject default')), 'View Trials must say it applied the defaults');
tb = findall(vt, 'Type', 'uitable');
assert(all(cellfun(@(v) v == 6000, tb.Data(:, strcmp(tb.ColumnName, 'ToneFreq')))), ...
    'View Trials must show the subject''s values');
delete(vt);
fprintf('PASS: View Trials previews with the defaults\n');

% 7. A default removed between runs is put back ----------------------------
D = epsych.SubjectRoster(rosterFile).parameterDefaults(s1, pid);
R.setParameterDefaults(s1, pid, D(~strcmp({D.Name}, 'RewardVol')));
rx.H.ctrl_preview.ButtonPushedFcn(rx.H.ctrl_preview, []);
assert(localWaitFor(@() rx.STATE == PRGMSTATE.RUNNING, 30), 'the second preview never reached RUNNING');
pause(0.5);
assert(isequal(q('RewardVol').Values, {25}) && q('RewardVol').Value == 25, ...
    'a removed default must return the protocol''s value');
assert(isequal(q('ToneFreq').Values, {6000}) && q('ITI').Max == 3900, 'the rest must still apply');
rx.halt;
assert(localWaitFor(@() rx.STATE == PRGMSTATE.STOP, 30), 'halt never reached STOP');
fprintf('PASS: the next Run restores a removed default\n');

% 8. Copy from Last Data File ----------------------------------------------
subjDir = fullfile(dataRoot, 'PDG1');
if ~isfolder(subjDir), mkdir(subjDir); end
localWriteSession(fullfile(subjDir, 'PDG1_260901T100000.mat'), 7000, 31);
localWriteSession(fullfile(subjDir, 'PDG1_260928T100000.mat'), 6000, 33);
E = gui.ParameterDefaultsEditor.open(R, s1, pid, RunExpt = rx);
rep = E.copyFromDataFile();
assert(endsWith(rep.File, 'PDG1_260928T100000.mat'), 'the newest saved session must be read');
assert(isequal(rep.Copied, {[modName '.RewardVol']}) && isequal(E.Rows(strcmp(names, 'RewardVol')).Value, 33), ...
    'only the value that differs must be copied (got %s)', strjoin(rep.Copied, ', '));
assert(E.IsModified, 'a copy is an unsaved edit');
% Escape asks before discarding on screen; a hidden window just closes.
fig = E.H.figure;
fig.Visible = 'off';
fig.WindowKeyPressFcn(fig, struct('Key', 'escape', 'Modifier', {{}}));
assert(~isvalid(E), 'Escape must close the window');
fprintf('PASS: Copy from Last Data File reads the newest session\n');

% 9. The Subjects & Projects window ----------------------------------------
gui.SubjectManager(rx);
mgr = findall(groot, 'Type', 'figure', 'Tag', 'EPsychSubjectManager').UserData;
mgr.H.projectList.Value = pid;
mgr.refresh();
r1 = find(strcmp(mgr.H.table.Data(:, 2), 'PDG1'));
r2 = find(strcmp(mgr.H.table.Data(:, 2), 'PDG2'));
assert(contains(mgr.H.table.Data{r1, 6}, '+ 4 defaults') && ~contains(mgr.H.table.Data{r2, 6}, 'default'), ...
    'the Settings column must count a membership''s defaults (got "%s")', mgr.H.table.Data{r1, 6});

cm = mgr.H.table.ContextMenu;
item = findall(cm, 'Text', 'Parameter Defaults for This Row...');
cm.ContextMenuOpeningFcn(cm, struct('InteractionInformation', struct('Row', r1)));
item.MenuSelectedFcn(item, []);
E1 = localEditorFor('PDG1');
assert(~isempty(E1), 'the right-click item must open the row under the pointer');
delete(E1);

% A stale right-click on PDG1 must not hijack the Subject menu on PDG2.
cm.ContextMenuOpeningFcn(cm, struct('InteractionInformation', struct('Row', r1)));
mgr.H.table.Selection = r2;
mgr.H.table.SelectionChangedFcn([], []);
mgr.H.mnu_parameter_defaults.MenuSelectedFcn(mgr.H.mnu_parameter_defaults, []);
E2 = localEditorFor('PDG2');
assert(~isempty(E2) && isempty(localEditorFor('PDG1')), ...
    'the Subject-menu item must open the selected row, not the last right-click');

[ok, msg] = E2.setDefault('ToneDur', '300');
assert(ok, msg);
E2.save();
r2 = find(strcmp(mgr.H.table.Data(:, 2), 'PDG2'));
assert(contains(mgr.H.table.Data{r2, 6}, '+ 1 default') && ~contains(mgr.H.table.Data{r2, 6}, 'defaults'), ...
    'saving in the editor must repaint the manager (got "%s")', mgr.H.table.Data{r2, 6});
delete(E2);
fprintf('PASS: the Subjects window opens the right editor and repaints on save\n');

delete(rx);
fprintf('\nALL PASS: smoke_test_parameter_defaults_gui\n');
clear cleanupFigs cleanupDir cleanupPrefs
end

% -----------------------------------------------------------------------
function k = localTableRow(E, name)
k = find(endsWith(E.H.table.Data(:, 1), ['.' name]) | strcmp(E.H.table.Data(:, 1), name), 1);
assert(~isempty(k), 'no table row for %s', name);
end

% -----------------------------------------------------------------------
function E = localEditorFor(subjectName)
E = [];
figs = findall(groot, 'Type', 'figure', 'Tag', 'EPsychParameterDefaultsEditor');
for i = 1:numel(figs)
    u = figs(i).UserData;
    if isa(u, 'gui.ParameterDefaultsEditor') && isvalid(u) && strcmp(u.SubjectName, subjectName)
        E = u;
        return
    end
end
end

% -----------------------------------------------------------------------
function d = localRecord(iface, moduleName, name, value, lo, hi)
d = epsych.ParameterDefaults.blank();
d.Interface = iface;
d.Module = moduleName;
d.Name = name;
d.Value = value;
d.Min = lo;
d.Max = hi;
end

% -----------------------------------------------------------------------
function localWriteSession(file, toneFreq, vol)
Data = struct('ToneFreq', {toneFreq, toneFreq}, 'RewardVol', vol, 'TrialIndex', {1, 2}, ...
    'isTest', false);
save(file, 'Data');
end

% -----------------------------------------------------------------------
function tf = localWaitFor(cond, timeoutSec)
% Poll a condition during pause() -- timers fire while paused.
t0 = tic;
tf = false;
while toc(t0) < timeoutSec
    if cond(), tf = true; return, end
    pause(0.2);
end
end

% -----------------------------------------------------------------------
function localCloseAll()
% Halt a session a failed assertion left running before its window goes, or
% the PsychTimer fires into a deleted RunExpt.
tags = {'EPsychParameterDefaultsEditor', 'EPsychSubjectManager', 'RunExpt'};
for i = 1:numel(tags)
    figs = findall(groot, 'Type', 'figure', 'Tag', tags{i});
    for f = figs(:)'
        try
            u = f.UserData;
            if isa(u, 'epsych.RunExpt') && isvalid(u)
                u.halt;
                localWaitFor(@() u.STATE < PRGMSTATE.RUNNING || u.STATE == PRGMSTATE.STOP, 15);
            end
            f.CloseRequestFcn = '';
            if isobject(u) && isvalid(u), delete(u); end
            if isgraphics(f), delete(f); end
        catch ME
            vprintf(2, ME);
        end
    end
end
end

% -----------------------------------------------------------------------
function saved = localSavePrefs(group)
saved = struct('existed', ispref(group), 'values', struct());
if saved.existed
    saved.values = getpref(group);
end
end

% -----------------------------------------------------------------------
function localRestoreAll(groups, saved)
for i = 1:numel(groups)
    if ispref(groups{i}), rmpref(groups{i}); end
    if saved{i}.existed
        fn = fieldnames(saved{i}.values);
        for k = 1:numel(fn)
            setpref(groups{i}, fn{k}, saved{i}.values.(fn{k}));
        end
    end
end
end

% -----------------------------------------------------------------------
function localRemoveDir(root)
try
    if isfolder(root), rmdir(root, 's'); end
catch
    % A file handle the OS has not released yet; the temp folder is fine.
end
end
