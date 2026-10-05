function smoke_test_subject_record_video()
% smoke_test_subject_record_video()
% Exercise the per-membership automatic webcam recording setting end to end:
% epsych.SubjectRoster.recordVideoSetting/setRecordVideo, how assignToSession
% combines a batch onto RunExpt.RecordVideo and its toolbar toggle (never the
% rig preference), the toggle's own path, copyProject/exportTable, a roster
% written before the field existed, and the Subjects & Projects window's Video
% column and menus.
%
% No VLC is launched: nothing here starts a run. Preferences are restored on
% exit whether it passes or fails.
%
%   matlab -batch "run('<repo>/tmp/smoke_test_subject_record_video.m')"
%
% See also: epsych.SubjectRoster.setRecordVideo, gui.SubjectManager

epsych_startup

savedSubjectPrefs = localSavePrefs('ep_RunExpt_Subjects');
savedGuiPrefs     = localSavePrefs('epsych2_gui_SubjectManager');
savedVideoPrefs   = localSavePrefs('ep_RunExpt_Video');
savedRunExptPrefs = localSavePrefs('RunExpt');
savedSubjectPrefs = localDropTempRoster(savedSubjectPrefs);
cleanupPrefs = onCleanup(@() localRestoreAll(savedSubjectPrefs, savedGuiPrefs, ...
    savedVideoPrefs, savedRunExptPrefs));
cleanupFigs  = onCleanup(@localCloseWindows);

root = fullfile(tempdir, 'epsych_recordvideo_smoke');
if isfolder(root), rmdir(root, 's'); end
mkdir(root);
cleanupDir = onCleanup(@() localRemoveDir(root));

repoRoot = fileparts(fileparts(mfilename('fullpath')));
proto = fullfile(repoRoot, 'tmp', 'TEST_NEW_PROTOCOL2.eprot');
assert(isfile(proto), 'Test protocol fixture is missing: %s', proto);

setpref('RunExpt', 'DataPath', fullfile(root, 'data'));
setpref('ep_RunExpt_Video', 'EnableRecording', false);

% 1. The value mapping -----------------------------------------------------
f = @epsych.SubjectRoster.recordVideoSetting;
assert(f(true) == 1 && f(1) == 1 && f("on") == 1 && f('Record') == 1, 'on forms');
assert(f(false) == 0 && f(0) == 0 && f("off") == 0, 'off forms');
assert(isnan(f(NaN)) && isnan(f([])) && isnan(f("")) && isnan(f("rig")), 'inherit forms');
[v, ok] = f("maybe");
assert(isnan(v) && ~ok, 'An unrecognized word must come back NaN and not ok');
[v, ok] = f(2);
assert(isnan(v) && ~ok, 'A number other than 0/1 must not be ok');
[~, ok] = f([1 0]);
assert(~ok, 'A vector must not be ok');
fprintf('PASS: recordVideoSetting maps every accepted form and refuses the rest\n');

% 2. Roster: default, set, unchanged, skipped, invalid ---------------------
rosterFile = fullfile(root, 'subjects.esub');
R = epsych.SubjectRoster(rosterFile);
p1 = R.addProject('Tone', DefaultProtocol = proto);
p2 = R.addProject('Gap');
ids = cell(1, 4);
for k = 1:4
    ids{k} = R.addSubject(struct('Name', sprintf('V%03d', k), 'Sex','Male', 'Species','Gerbil'));
    R.assign(ids{k}, p1);
    R.rememberProtocol(ids{k}, p1, proto);
end
R.assign(ids{1}, p2);
R.setActive(ids{4}, p1, false);
outsider = R.addSubject(struct('Name','V_OUT', 'Sex','Male', 'Species','Gerbil'));

m = R.findMembership(ids{1}, p1);
assert(isnan(m.RecordVideo), 'A new membership must follow the rig toggle (NaN)');

rep = R.setRecordVideo(ids(1:2), p1, true);
assert(rep.ok && numel(rep.updated) == 2 && rep.unchanged == 0, ...
    'Two memberships should have changed: %s', rep.message);
assert(R.findMembership(ids{1}, p1).RecordVideo == 1, 'V001 should record in Tone');
assert(isnan(R.findMembership(ids{1}, p2).RecordVideo), ...
    'Setting one project must not touch the subject''s other membership');

stamp = R.findMembership(ids{1}, p1).Modified;
pause(0.05);
rep = R.setRecordVideo(ids(1), p1, "on");
assert(rep.ok && isempty(rep.updated) && rep.unchanged == 1, ...
    'Re-applying the same value should be reported unchanged');
assert(R.findMembership(ids{1}, p1).Modified == stamp, ...
    'An unchanged value must not move the Modified stamp');

rep = R.setRecordVideo({outsider, 'NOBODY'}, p1, false);
assert(numel(rep.skipped) == 2 && isempty(rep.updated), ...
    'A non-member and an unknown subject should both be skipped');

threw = '';
try
    R.setRecordVideo(ids(1), p1, "sometimes");
catch ME
    threw = ME.identifier;
end
assert(strcmp(threw, 'epsych:SubjectRoster:InvalidRecordVideo'), 'Invalid value must throw');
threw = '';
try
    R.setRecordVideo(ids(1), 'NoSuchProject', true);
catch ME
    threw = ME.identifier;
end
assert(strcmp(threw, 'epsych:SubjectRoster:NoSuchProject'), 'Unknown project must throw');

R2 = epsych.SubjectRoster(rosterFile);
assert(R2.findMembership(ids{2}, p1).RecordVideo == 1, 'The setting must survive a reload');
fprintf('PASS: setRecordVideo writes, counts unchanged, skips, refuses, and persists\n');

% 3. AllMembers covers retired members too ---------------------------------
rep = R.setRecordVideo([], p1, false, AllMembers = true);
assert(rep.ok && numel(rep.updated) + rep.unchanged == 4, ...
    'AllMembers should reach all four members of Tone: %s', rep.message);
assert(R.findMembership(ids{4}, p1).RecordVideo == 0, 'The retired member must be included');
assert(isnan(R.findMembership(ids{1}, p2).RecordVideo), 'Gap must be untouched');
R.setRecordVideo([], p1, NaN, AllMembers = true);
assert(all(arrayfun(@(k) isnan(R.findMembership(ids{k}, p1).RecordVideo), 1:4)), ...
    'All Tone members should be back on the rig toggle');
fprintf('PASS: AllMembers sets every member of one project, retired included\n');

% 4. A roster written before the field existed -----------------------------
S = load(rosterFile, '-mat');
S.memberships = rmfield(S.memberships, 'RecordVideo');
oldFile = fullfile(root, 'old.esub');
save(oldFile, '-struct', 'S', '-mat');
Rold = epsych.SubjectRoster(oldFile);
assert(all(isnan([Rold.Memberships.RecordVideo])), ...
    'A pre-field roster must read as "follow the rig toggle"');
fprintf('PASS: a roster written before the field reads as NaN (rig toggle)\n');

% 5. assignToSession combines the batch onto the session -------------------
delete(findall(groot, 'Type','figure', 'Tag','RunExpt'));
rx = epsych.RunExpt;
tg = rx.H.setup_record_video;
assert(~rx.RecordVideo && ~logical(tg.State), 'Session should seed off from the preference');

% all inherit -> the preference (false)
rep = R.assignToSession(rx, ids(1:2), ProjectID = p1, ReplaceExisting = true);
assert(rep.ok, rep.message);
assert(~rx.RecordVideo, 'All-inherit batch should follow the preference (off)');

% one subject asks -> on; the preference is not written
R.setRecordVideo(ids(2), p1, true);
rep = R.assignToSession(rx, ids(1:2), ProjectID = p1, ReplaceExisting = true);
assert(rep.ok, rep.message);
assert(rx.RecordVideo && logical(tg.State), 'A subject set to record must turn the toggle on');
assert(~getpref('ep_RunExpt_Video', 'EnableRecording'), ...
    'A subject setting must never be written into the rig preference');
assert(contains(rep.message, 'Webcam recording on'), 'The report should say why: %s', rep.message);

% mixed on/off -> on
R.setRecordVideo(ids(1), p1, false);
rep = R.assignToSession(rx, ids(1:2), ProjectID = p1, ReplaceExisting = true);
assert(rep.ok && rx.RecordVideo, 'Any subject asking to record must win over one refusing');

% replaced by an inherit-only batch -> back to the preference
rep = R.assignToSession(rx, ids(3), ProjectID = p1, ReplaceExisting = true);
assert(rep.ok, rep.message);
assert(~rx.RecordVideo && ~logical(tg.State), ...
    'A batch that says nothing must return to the rig preference, not keep the last batch''s');
assert(contains(rep.message, 'rig setting'), 'The report should say it went back: %s', rep.message);

% refusing with the rig preference on -> off
setpref('ep_RunExpt_Video', 'EnableRecording', true);
R.setRecordVideo(ids(3), p1, false);
rep = R.assignToSession(rx, ids(3), ProjectID = p1, ReplaceExisting = true);
assert(rep.ok && ~rx.RecordVideo, 'A subject set to off must override the rig preference');
assert(getpref('ep_RunExpt_Video', 'EnableRecording'), 'The preference must be left alone');

% inherit with the rig preference on -> on
R.setRecordVideo(ids(3), p1, NaN);
rep = R.assignToSession(rx, ids(3), ProjectID = p1, ReplaceExisting = true);
assert(rep.ok && rx.RecordVideo, 'Inherit should pick up the rig preference (on)');
setpref('ep_RunExpt_Video', 'EnableRecording', false);

% no project context -> session left alone
before = rx.RecordVideo;
rep = R.assignToSession(rx, ids(1), ReplaceExisting = true, Protocols = {proto});
assert(rep.ok && rx.RecordVideo == before, 'With no project context nothing is applied');
fprintf('PASS: assignToSession combines a batch onto the session, never the preference\n');

% 6. The toolbar toggle still drives the session and the preference --------
tg.State = false;
tg.ClickedCallback(tg, []);
assert(~rx.RecordVideo && ~getpref('ep_RunExpt_Video', 'EnableRecording'), 'Toggle off');
tg.State = true;
tg.ClickedCallback(tg, []);
assert(rx.RecordVideo && getpref('ep_RunExpt_Video', 'EnableRecording'), 'Toggle on');
tg.State = false;
tg.ClickedCallback(tg, []);
threw = false;
try
    rx.RecordVideo = true;
catch
    threw = true;
end
assert(threw, 'RecordVideo must not be settable from outside RunExpt');
fprintf('PASS: the toggle sets the session and the preference; the property is guarded\n');

% 7. copyProject and exportTable --------------------------------------------
R.setRecordVideo(ids(1), p1, true);
R.setRecordVideo(ids(2), p1, false);
pc = R.copyProject(p1, 'Tone copy', IncludeSubjects = true);
assert(R.findMembership(ids{1}, pc).RecordVideo == 1 && ...
    R.findMembership(ids{2}, pc).RecordVideo == 0, 'A copy should carry the setting');
pn = R.copyProject(p1, 'Tone copy 2', IncludeSubjects = true, CopyRecordVideo = false);
assert(isnan(R.findMembership(ids{1}, pn).RecordVideo), 'CopyRecordVideo=false should not');

T = R.exportTable();
row = T(strcmp(T.Subject, 'V001') & strcmp(T.Project, 'Tone'), :);
assert(strcmp(row.RecordVideo{1}, 'on'), 'Export should word the setting');
row = T(strcmp(T.Subject, 'V_OUT'), :);
assert(isempty(row.RecordVideo{1}), 'A subject with no project exports a blank setting');
fprintf('PASS: copyProject carries the setting and exportTable words it\n');

% 8. The Subjects & Projects window -----------------------------------------
epsych.SubjectRoster.setConfiguredFile(rosterFile);
gui.SubjectManager(rx);
mgr = localManager();
assert(~isempty(mgr), 'The manager window should exist');

mgr.H.projectList.Value = p1;
mgr.H.projectList.ValueChangedFcn(mgr.H.projectList, []);
mgr.refresh();

col = find(strcmp(mgr.H.table.ColumnName, 'Video'));
assert(isscalar(col) && col == 7, 'The Video column should be column 7');
assert(mgr.H.table.ColumnEditable(col), 'Video should be editable in a project view');
r1 = find(strcmp(mgr.H.table.Data(:,2), 'V001'));
r3 = find(strcmp(mgr.H.table.Data(:,2), 'V003'));
assert(strcmp(mgr.H.table.Data{r1, col}, 'Record'), 'V001 should show Record');
assert(strcmp(mgr.H.table.Data{r3, col}, 'Rig toggle'), 'V003 should show Rig toggle');
sp = find(strcmp(mgr.H.table.ColumnName, 'Species'));
assert(strcmp(mgr.H.table.Data{r1, sp}, 'Gerbil'), 'Columns after Video must not have shifted wrongly');
st = find(strcmp(mgr.H.table.ColumnName, 'Status'));
assert(strcmp(mgr.H.table.Data{r1, st}, 'Active'), 'Status should still be the last column');

% a choice made in the cell is written to the roster at once
mgr.H.table.Data{r3, col} = 'Off';
mgr.H.table.CellEditCallback([], struct('Indices', [r3 col], ...
    'NewData', 'Off', 'PreviousData', 'Rig toggle'));
Rchk = epsych.SubjectRoster(rosterFile);
assert(Rchk.findMembership(ids{3}, p1).RecordVideo == 0, 'The Video cell should write the roster');
r3 = find(strcmp(mgr.H.table.Data(:,2), 'V003'));
assert(strcmp(mgr.H.table.Data{r3, col}, 'Off'), 'The repaint should show the new value');

% menus are gated on ticks and project
assert(strcmp(mgr.H.mnu_video_checked.Enable, 'off'), 'Checked submenu needs ticks');
assert(strcmp(mgr.H.mnu_video_project.Enable, 'on'), 'Project submenu needs only a project');
localTick(mgr, r1, true);
localTick(mgr, r3, true);
assert(strcmp(mgr.H.mnu_video_checked.Enable, 'on'), 'Ticking should enable the checked submenu');

item = findall(mgr.H.mnu_video_checked, 'Type','uimenu', 'Text','Checked Subjects &Follow the Rig Toggle');
assert(isscalar(item), 'Expected the follow-the-rig item');
item.MenuSelectedFcn(item, []);
Rchk = epsych.SubjectRoster(rosterFile);
assert(isnan(Rchk.findMembership(ids{1}, p1).RecordVideo) && ...
    isnan(Rchk.findMembership(ids{3}, p1).RecordVideo), 'The checked submenu should write both');
assert(Rchk.findMembership(ids{2}, p1).RecordVideo == 0, 'An unticked subject must be untouched');

% the All Projects view has nothing to write
mgr.H.projectList.Value = '';
mgr.H.projectList.ValueChangedFcn(mgr.H.projectList, []);
mgr.refresh();
assert(~mgr.H.table.ColumnEditable(col), 'Video must not be editable in All Projects');
assert(all(cellfun(@isempty, mgr.H.table.Data(:, col))), 'Video cells are blank in All Projects');
assert(strcmp(mgr.H.mnu_video_project.Enable, 'off'), 'Project submenu needs a project');
fprintf('PASS: the Video column, its edits, and both menus behave\n');

fprintf('\nALL PASSED: smoke_test_subject_record_video\n');
end

% -----------------------------------------------------------------------
function mgr = localManager()
mgr = [];
f = findall(groot, 'Type','figure', 'Tag','EPsychSubjectManager');
if isempty(f), return, end
mgr = f(1).UserData;
end

% -----------------------------------------------------------------------
function localTick(mgr, row, value)
mgr.H.table.Data{row,1} = value;
mgr.H.table.CellEditCallback([], struct( ...
    'Indices', [row 1], 'NewData', value, 'PreviousData', ~value));
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
function localRestoreAll(varargin)
groups = {'ep_RunExpt_Subjects', 'epsych2_gui_SubjectManager', 'ep_RunExpt_Video', 'RunExpt'};
for i = 1:numel(groups)
    localRestorePrefs(groups{i}, varargin{i});
end
end

% -----------------------------------------------------------------------
function saved = localDropTempRoster(saved)
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
