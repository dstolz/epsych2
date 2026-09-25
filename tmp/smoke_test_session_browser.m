function smoke_test_session_browser()
% smoke_test_session_browser()
% gui.SessionBrowser and the epsych.SessionFiles scan behind it, over a
% temporary data tree holding every file shape a rig accumulates: a session
% with a snapshot and a video, a legacy Data-only file named by date, a
% zero-trial placeholder, a damaged file, an analysis .mat that is not a
% session, a folder under the subject's former name, and crash-recovery
% copies -- one merged, one whose trials are only in its .epj journal, and one
% for a subject whose name merely starts the same way.
%
% Then the part that matters most: the browser is refused, and an open one
% greys out, while a real epsych.RunExpt is RUNNING, and comes back when it
% stops; the Subjects & Projects right-click item follows the same rule; and
% Review hands the chosen file to epsych.ReviewSession.
%
% Headless-safe: every window is closed and the user's preferences restored
% whether it passes or fails.
%
%   matlab -batch "run('C:\src\epsych2\tmp\smoke_test_session_browser.m')"
%
% See also: gui.SessionBrowser, epsych.SessionFiles,
%   documentation/gui/gui_SessionBrowser.md

here = fileparts(mfilename('fullpath'));
if exist('epsych.SessionFiles', 'class') ~= 8
    run(fullfile(here, '..', 'epsych_startup.m'));
end

fprintf('\n=== gui.SessionBrowser Smoke Test ===\n\n');

savedSubjects = localSavePrefs('ep_RunExpt_Subjects');
savedBrowser  = localSavePrefs('epsych2_gui_SessionBrowser');
savedManager  = localSavePrefs('epsych2_gui_SubjectManager');
restorePrefs = onCleanup(@() localRestoreAll(savedSubjects, savedBrowser, savedManager));
closeAll = onCleanup(@localCloseWindows);

root = fullfile(tempdir, sprintf('epsych_session_browser_smoke_%d', feature('getpid')));
if isfolder(root), rmdir(root, 's'); end
mkdir(root);
removeRoot = onCleanup(@() localRemoveDir(root));

epsych.SessionFiles.clearCache();
localCloseWindows();

results = {};

NAME = "ZZSMK01";
FORMER = "ZZOLD01";
dataRoot = fullfile(root, 'data');
recoveryDir = fullfile(root, 'recovery');

% --- Fixtures ------------------------------------------------------------
% The roster first: renaming a subject is refused once its data folder
% exists, so the rename has to happen before any folder is made.
rosterFile = fullfile(root, 'smoke.esub');
R = epsych.SubjectRoster(rosterFile);
projectId = R.addProject('Smoke Project', DefaultDataPath = dataRoot);
subjectId = R.addSubject(struct('Name', char(FORMER), 'Sex', 'Male', ...
    'Species', 'Gerbil', 'Weight', 60));
R.assign(subjectId, projectId);
R.updateSubject(subjectId, struct('Name', char(NAME)));

F = localMakeFixtures(dataRoot, recoveryDir, NAME, FORMER);

%% 1. summarize: one file, one row
try
    s = epsych.SessionFiles.summarize(F.snapshot);
    results(end+1,:) = check('A snapshot session is a Saved session', ...
        s.IsSession && s.Source == "Saved" && s.Error == "");
    results(end+1,:) = check('Trials counted from Data', s.Trials == 5);
    results(end+1,:) = check('Start is the snapshot''s session start', ...
        s.StartTime == datetime(2026,9,1,9,0,0));
    results(end+1,:) = check('Duration runs to the last trial', ...
        abs(s.Duration - minutes(5)) < seconds(1));
    results(end+1,:) = check('Box, paradigm, protocol version and notes come from Info', ...
        s.BoxID == 3 && s.Paradigm == "smoke_trialFunc" ...
        && s.ProtocolVersion == "v7.260901" && contains(s.NotesText, "smoke note"));
    results(end+1,:) = check('EPsych version is tag and short commit', ...
        s.EPsychVersion == "v9.9.9 (abcdef1)");
    results(end+1,:) = check('A file carrying its protocol is fully reviewable', s.HasSnapshot);

    s = epsych.SessionFiles.summarize(F.legacy);
    results(end+1,:) = check('A legacy Data-only file starts at its first trial', ...
        s.StartTime == datetime(2026,8,5,10,0,0) && abs(s.Duration - minutes(4)) < seconds(1));
    results(end+1,:) = check('A legacy file carries no protocol and no box', ...
        ~s.HasSnapshot && isnan(s.BoxID));

    s = epsych.SessionFiles.summarize(F.placeholder);
    results(end+1,:) = check('An all-empty placeholder record is zero trials', ...
        s.IsSession && s.Trials == 0 && s.StartTime == datetime(2026,9,2,9,0,0));

    s = epsych.SessionFiles.summarize(F.corrupt);
    results(end+1,:) = check('A damaged file is reported, not dropped', ...
        s.IsSession && s.Error ~= "");

    s = epsych.SessionFiles.summarize(F.analysis);
    results(end+1,:) = check('A .mat without Data or info is not a session', ~s.IsSession);

    s = epsych.SessionFiles.summarize(fullfile(root, 'nope.mat'));
    results(end+1,:) = check('A missing file comes back with Error, not a throw', ...
        ~s.IsSession && s.Error ~= "");

    snap = epsych.SessionSnapshot.fromInfo(struct('Version', '2', 'Checksum', 'abc'), Quiet = true);
    results(end+1,:) = check('fromInfo(Quiet=true) still normalizes a legacy Info', ...
        isfield(snap.EPsychMeta, 'Checksum'));
catch ME
    results(end+1,:) = check(['summarize: ' ME.message], false);
end

%% 2. scan: the subject's folders, newest first
try
    [T, rep] = epsych.SessionFiles.scan([NAME FORMER], Roots = dataRoot);
    results(end+1,:) = check('Five sessions across the current and former name', height(T) == 5);
    results(end+1,:) = check('The analysis file is skipped and counted', rep.NumSkipped == 1);
    results(end+1,:) = check('Newest first', issorted(T.StartTime, 'descend', 'MissingPlacement', 'last'));
    results(end+1,:) = check('The former name''s folder is searched', ...
        any(startsWith(T.FileName, FORMER)));
    k = find(T.File == string(F.snapshot));
    results(end+1,:) = check('The recording beside the data file is found', ...
        ~isempty(k) && endsWith(T.VideoFile(k), ".ts"));
    results(end+1,:) = check('Recovery copies stay out unless asked for', ...
        ~any(T.Source == "Recovery"));

    % Upper case is the same folder only on Windows; elsewhere it is a root
    % that does not exist, and the count must come out the same either way.
    [T2, rep2] = epsych.SessionFiles.scan(NAME, ...
        Roots = [string(dataRoot), string(dataRoot) + filesep, upper(string(dataRoot))]);
    results(end+1,:) = check('One root spelled three ways is scanned once', ...
        height(T2) == 4 && isscalar(rep2.Folders));

    [~, rep3] = epsych.SessionFiles.scan(NAME, Roots = [string(dataRoot), string(fullfile(root, 'unmounted'))]);
    results(end+1,:) = check('A root that does not exist is reported missing', ...
        isscalar(rep3.Missing) && endsWith(rep3.Missing, "unmounted"));

    [T4, rep4] = epsych.SessionFiles.scan([NAME FORMER], Roots = dataRoot, ...
        Progress = @(k, n) k < 2);
    results(end+1,:) = check('Progress returning false stops the scan', ...
        rep4.Cancelled && height(T4) <= 1);
catch ME
    results(end+1,:) = check(['scan: ' ME.message], false);
end

%% 3. scan: crash-recovery copies
try
    T = epsych.SessionFiles.scan(NAME, Roots = dataRoot, ...
        IncludeRecovery = true, RecoveryDir = recoveryDir);
    rec = T(T.Source == "Recovery", :);
    results(end+1,:) = check('Both of this subject''s recovery copies are listed', height(rec) == 2);
    results(end+1,:) = check('A subject whose name only starts the same is not', ...
        ~any(contains(T.FileName, "ZZSMK010")));
    k = find(endsWith(rec.FileName, ".epj"));
    results(end+1,:) = check('An unmerged seed is replaced by its journal', ...
        isscalar(k) && rec.Trials(k) == 3);
    k = find(rec.BoxID == 2);
    results(end+1,:) = check('A merged seed counts its data_NNNN trials and knows its Preview', ...
        isscalar(k) && rec.Trials(k) == 2 && rec.IsTest(k));
catch ME
    results(end+1,:) = check(['recovery: ' ME.message], false);
end

%% 4. the cache re-reads only what changed
try
    before = epsych.SessionFiles.summarize(F.former);
    Data = [localRecord(datetime(2026,8,1,9,1,0), 1), localRecord(datetime(2026,8,1,9,2,0), 2), ...
        localRecord(datetime(2026,8,1,9,3,0), 3)];
    save(F.former, 'Data');
    after = epsych.SessionFiles.summarize(F.former);
    results(end+1,:) = check('A rewritten file is read again', ...
        before.Trials == 2 && after.Trials == 3);
catch ME
    results(end+1,:) = check(['cache: ' ME.message], false);
end

%% 5. locations: where the roster says to look
try
    L = epsych.SessionFiles.locations(NAME, Roster = R);
    results(end+1,:) = check('Former names are searched too', ...
        any(L.Names == NAME) && any(L.Names == FORMER));
    results(end+1,:) = check('The project''s data path is a root', ...
        any(strcmpi(L.Roots, string(dataRoot))));
catch ME
    results(end+1,:) = check(['locations: ' ME.message], false);
end

%% 6. the window
try
    B = gui.SessionBrowser(NAME, Roster = R, Visible = false);
    tbl = B.H.table;
    D = tbl.Data;
    results(end+1,:) = check('One row per session file', height(B.Sessions) == 5 && height(D) == 5);
    results(end+1,:) = check('Date and Trials are typed, so a header sort is by value', ...
        isdatetime(D.Date) && isnumeric(D.Trials));
    k = find(B.Sessions.File == string(F.placeholder));
    j = find(B.Sessions.File == string(F.legacy));
    results(end+1,:) = check('An unknown duration or box is blank, not NaN', ...
        D.Duration(k) == "" && D.Box(j) == "");
    results(end+1,:) = check('Fixed-width text sorts as its value (box 2 before box 10)', ...
        isequal(sort(["10"; compose("%2d", 2); ""]), [""; " 2"; "10"]) ...
        && D.Duration(j) == "00:04:00");
    results(end+1,:) = check('Columns are sortable', logical(tbl.ColumnSortable(1)));
    results(end+1,:) = check('The Review column says what a review will give', ...
        all(ismember(["Full" "Data only" "No trials" "Unreadable"], D.Review)));
    results(end+1,:) = check('The newest row starts selected', isequal(tbl.Selection, 1));

    k = find(B.Sessions.File == string(F.legacy));
    localSelect(B, k);
    results(end+1,:) = check('A reviewable row enables Review', strcmp(B.H.btnReview.Enable, 'on'));
    results(end+1,:) = check('The details pane names the file and what review gives', ...
        any(contains(string(B.H.details.Value), string(F.legacy))) ...
        && any(contains(string(B.H.details.Value), "without the parameter controls")));

    k = find(B.Sessions.File == string(F.placeholder));
    localSelect(B, k);
    results(end+1,:) = check('A zero-trial row disables Review', strcmp(B.H.btnReview.Enable, 'off'));
    nBefore = numel(localReviews());
    B.review(k);
    results(end+1,:) = check('Reviewing a zero-trial row is refused', numel(localReviews()) == nBefore);

    B2 = gui.SessionBrowser(NAME, Roster = R, Visible = false);
    figs = findall(groot, 'Type', 'figure', 'Tag', 'EPsychSessionBrowser');
    results(end+1,:) = check('Asking again for the same subject replaces the window', ...
        ~isvalid(B) && isscalar(figs) && isvalid(B2));
    delete(B2);
catch ME
    results(end+1,:) = check(['window: ' ME.message], false);
end

%% 7. only between sessions
try
    delete(findall(groot, 'Type', 'figure', 'Tag', 'RunExpt'));
    rx = epsych.RunExpt;
    rx.RUNTIME.TempDataDir = string(recoveryDir);

    mp = findprop(rx, 'STATE');
    results(end+1,:) = check('RunExpt.STATE is observable', mp.SetObservable);

    B = gui.SessionBrowser(NAME, Roster = R, RunExpt = rx, Visible = false);
    results(end+1,:) = check('Recovery copies are looked for where the session puts them', ...
        B.Locations.RecoveryDir == string(recoveryDir));

    B.H.chkRecovery.Value = true;
    B.H.chkRecovery.ValueChangedFcn(B.H.chkRecovery, []);
    results(end+1,:) = check('Ticking Include crash-recovery files rescans with them', ...
        height(B.Sessions) == 7);

    k = find(B.Sessions.File == string(F.legacy));
    localSelect(B, k);

    rx.STATE = PRGMSTATE.RUNNING;
    results(end+1,:) = check('A session starting greys Review and Rescan', ...
        strcmp(B.H.btnReview.Enable, 'off') && strcmp(B.H.btnRescan.Enable, 'off') ...
        && strcmp(B.H.chkRecovery.Enable, 'off'));
    results(end+1,:) = check('...and shows the banner', ...
        strcmp(B.H.banner.Visible, 'on') && B.H.root.RowHeight{2} > 0);

    nBefore = numel(localReviews());
    B.review(k);
    results(end+1,:) = check('Review refuses while running, even when called directly', ...
        numel(localReviews()) == nBefore);

    results(end+1,:) = check('Opening a browser while running is refused', ...
        throwsWith(@() gui.SessionBrowser(NAME, Roster = R, RunExpt = rx, Visible = false), ...
        'gui:SessionBrowser:SessionRunning'));
    results(end+1,:) = check('sessionIsRunning([]) finds the open session window', ...
        gui.SessionBrowser.sessionIsRunning([]));

    rx.STATE = PRGMSTATE.POSTRUN;
    results(end+1,:) = check('Finishing (POSTRUN) still counts as running', ...
        strcmp(B.H.btnReview.Enable, 'off'));

    rx.STATE = PRGMSTATE.STOP;
    results(end+1,:) = check('Stopping brings the controls back', ...
        strcmp(B.H.btnReview.Enable, 'on') && strcmp(B.H.btnRescan.Enable, 'on') ...
        && strcmp(B.H.banner.Visible, 'off'));

    % The hand-off itself: the file lands in epsych.ReviewSession.
    B.review(k);
    V = localReviews();
    opened = ~isempty(V) && any(arrayfun(@(v) strcmp(v.DataFile, F.legacy), V));
    results(end+1,:) = check('Review opens the selected file in epsych.ReviewSession', opened);
    for v = V, delete(v); end
    delete(B);
catch ME
    results(end+1,:) = check(['session gate: ' ME.message], false);
end

%% 8. the Subjects & Projects right-click item
try
    epsych.SubjectRoster.setConfiguredFile(rosterFile);
    gui.SubjectManager(rx);
    mgrFig = findall(groot, 'Type', 'figure', 'Tag', 'EPsychSubjectManager');
    mgr = mgrFig(1).UserData;
    cm = mgr.H.table.ContextMenu;
    evt = struct('InteractionInformation', struct('Row', 1));

    rx.STATE = PRGMSTATE.RUNNING;
    cm.ContextMenuOpeningFcn(cm, evt);
    results(end+1,:) = check('View Data Files... is off while a session runs, and says why', ...
        strcmp(mgr.H.cmnu_data_files.Enable, 'off') ...
        && contains(mgr.H.cmnu_data_files.Text, 'not while'));

    rx.STATE = PRGMSTATE.STOP;
    cm.ContextMenuOpeningFcn(cm, evt);
    results(end+1,:) = check('View Data Files... is on once it stops', ...
        strcmp(mgr.H.cmnu_data_files.Enable, 'on') ...
        && strcmp(mgr.H.cmnu_data_files.Text, 'View Data Files...'));

    mgr.H.cmnu_data_files.MenuSelectedFcn(mgr.H.cmnu_data_files, []);
    figs = findall(groot, 'Type', 'figure', 'Tag', 'EPsychSessionBrowser');
    opened = ~isempty(figs) && strcmp(figs(1).UserData.SubjectName, NAME);
    results(end+1,:) = check('It opens the browser on the right-clicked subject', opened);
catch ME
    results(end+1,:) = check(['subject manager: ' ME.message], false);
end

% --- Report --------------------------------------------------------------
labels = results(:,1);
passed = [results{:,2}];
for i = 1:numel(labels)
    if passed(i)
        fprintf('  PASS  %s\n', labels{i});
    else
        fprintf('  FAIL  %s\n', labels{i});
    end
end
fprintf('\n%d passed, %d failed, %d total\n\n', sum(passed), sum(~passed), numel(passed));

if any(~passed)
    error('smoke_test_session_browser:Failed', '%d smoke test(s) failed.', sum(~passed));
end

end




function F = localMakeFixtures(dataRoot, recoveryDir, NAME, FORMER)
% Every file shape the scan has to tell apart. Returns their paths.

subj = fullfile(dataRoot, char(NAME));
old  = fullfile(dataRoot, char(FORMER));
mkdir(subj); mkdir(old); mkdir(recoveryDir);

% A session saved with a snapshot, and its recording.
t0 = datetime(2026,9,1,9,0,0);
Data = arrayfun(@(k) localRecord(t0 + minutes(k), k), 1:5);
Info = localInfo(t0, 3, false);
F.snapshot = fullfile(subj, sprintf('%s_260901T090000.mat', NAME));
save(F.snapshot, 'Data', 'Info');
fclose(fopen(fullfile(subj, sprintf('%s_260901T090000.ts', NAME)), 'w'));

% A legacy file: Data only, the old timestamp field, a date-only name.
t1 = datetime(2026,8,5,10,0,0);
Data = arrayfun(@(k) localRecord(t1 + minutes(2*(k-1)), k, 'inaccurateTimestamp'), 1:3);
F.legacy = fullfile(subj, sprintf('%s_05-Aug-2026.mat', NAME));
save(F.legacy, 'Data');

% A session that completed nothing: one record, every field empty.
Data = struct('TrialIndex', [], 'RespCode', [], 'computerTimestamp', []);
F.placeholder = fullfile(subj, sprintf('%s_260902T090000.mat', NAME));
save(F.placeholder, 'Data');

% Not a MAT file at all, as a save interrupted by a crash can leave.
F.corrupt = fullfile(subj, sprintf('%s_260903T090000.mat', NAME));
fid = fopen(F.corrupt, 'w'); fwrite(fid, 'not a mat file'); fclose(fid);

% Somebody's analysis, in the same folder.
x = magic(4);
F.analysis = fullfile(subj, 'analysis.mat');
save(F.analysis, 'x');

% A session run under the subject's former name.
t2 = datetime(2026,8,1,9,0,0);
Data = [localRecord(t2 + minutes(1), 1), localRecord(t2 + minutes(2), 2)];
F.former = fullfile(old, sprintf('%s_260801T090000.mat', FORMER));
save(F.former, 'Data');

% A merged recovery seed, from a Preview run in box 2.
info = localInfo(datetime(2026,9,4,9,0,0), 2, true);
data_0001 = localRecord(datetime(2026,9,4,9,1,0), 1);
data_0002 = localRecord(datetime(2026,9,4,9,2,0), 2);
save(fullfile(recoveryDir, sprintf('RUNTIME_DATA_%s_Box_02_260904090012.mat', NAME)), ...
    'info', 'data_0001', 'data_0002');

% A seed whose journal was never merged: info alone, trials in the .epj.
info = localInfo(datetime(2026,9,5,9,0,0), 1, false);
seed = fullfile(recoveryDir, sprintf('RUNTIME_DATA_%s_Box_01_260905090034.mat', NAME));
save(seed, 'info');
J = epsych.TrialJournal(regexprep(seed, '\.mat$', '.epj'));
J.append('info', info);
for k = 1:3
    J.append(sprintf('data_%04d', k), localRecord(datetime(2026,9,5,9,k,0), k));
end
delete(J);

% Another subject whose name begins with this one's.
info = localInfo(datetime(2026,9,6,9,0,0), 1, false);
data_0001 = localRecord(datetime(2026,9,6,9,1,0), 1);
save(fullfile(recoveryDir, sprintf('RUNTIME_DATA_%s0_Box_01_260906090000.mat', NAME)), ...
    'info', 'data_0001');
end


function rec = localRecord(t, k, stampField)
if nargin < 3, stampField = 'computerTimestamp'; end
rec = struct('TrialIndex', k, 'RespCode', 1, stampField, t, 'isTest', false);
end


function info = localInfo(t0, box, isTest)
% Enough of an epsych.SessionSnapshot for a summary: FormatVersion makes it a
% snapshot, and a non-empty Protocol makes it a full one.
info = struct( ...
    'FormatVersion', epsych.SessionSnapshot.FORMAT_VERSION, ...
    'EPsychMeta',    struct('LatestTag', 'v9.9.9', 'Checksum', 'abcdef1234567890'), ...
    'Subject',       [], ...
    'BoxID',         box, ...
    'isTest',        isTest, ...
    'DataFilename',  '', ...
    'StartTime',     t0, ...
    'SelectorClass', '', ...
    'Protocol',      struct('Options', struct('trialFunc', 'smoke_trialFunc'), ...
                            'protocolVersion', 'v7.260901'), ...
    'TrialTable',    {{}}, ...
    'WriteParams',   {{}}, ...
    'WriteParamIdx', struct(), ...
    'Notes',         epsych.SessionNotes.emptyRecords(), ...
    'NotesText',     '[T001 00:00:10] smoke note', ...
    'NotesEdited',   false);
end


function localSelect(B, row)
% Select a row the way a click does: set it, then fire the callback.
B.H.table.Selection = row;
B.H.table.SelectionChangedFcn(B.H.table, []);
end


function V = localReviews()
% Every open epsych.ReviewSession, found through the anchor its windows carry.
V = epsych.ReviewSession.empty(1, 0);
for f = reshape(findall(groot, 'Type', 'figure'), 1, [])
    if isappdata(f, 'epsych_ReviewSession')
        r = getappdata(f, 'epsych_ReviewSession');
        if isa(r, 'epsych.ReviewSession') && isvalid(r) && ~any(V == r)
            V(end+1) = r;
        end
    end
end
end


function row = check(label, tf)
row = {char(label), logical(tf)};
end


function tf = throwsWith(fcn, identifier)
tf = false;
try
    fcn();
catch ME
    tf = strcmp(ME.identifier, identifier);
end
end


function localCloseWindows()
for v = localReviews()
    delete(v);
end
delete(findall(groot, 'Type', 'figure', 'Tag', 'EPsychSessionBrowser'));
delete(findall(groot, 'Type', 'figure', 'Tag', 'EPsychSubjectManager'));
delete(findall(groot, 'Type', 'figure', 'Tag', 'RunExpt'));
end


function saved = localSavePrefs(group)
saved = struct('group', group, 'existed', ispref(group), 'values', struct());
if saved.existed
    saved.values = getpref(group);
end
end


function localRestoreAll(varargin)
for i = 1:numel(varargin)
    saved = varargin{i};
    if ispref(saved.group)
        rmpref(saved.group);
    end
    if ~saved.existed, continue, end
    names = fieldnames(saved.values);
    for j = 1:numel(names)
        setpref(saved.group, names{j}, saved.values.(names{j}));
    end
end
end


function localRemoveDir(root)
epsych.SessionFiles.clearCache();
if isfolder(root)
    try
        rmdir(root, 's');
    catch ME
        vprintf(2, ME);
    end
end
end
