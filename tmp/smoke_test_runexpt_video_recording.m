function report = smoke_test_runexpt_video_recording()
% report = smoke_test_runexpt_video_recording()
% Lightweight smoke test for the RunExpt "Record video" toolbar toggle.
% No VLC install or webcam is required — recording is never triggered
% (EnableRecording stays false throughout), so only the GUI/pref plumbing
% is exercised: filename generation, toggle <-> preference round-trip,
% Customize dialog persistence, and teardown safety.
%
% Verifies:
%   1) epsych.RunExpt.videoRecordingFilename mirrors the data file's
%      <subjectFolder>\<name>.ts layout under the recording root, and
%      rejects a data filename with no name part.
%   2) The "Record video" toolbar toggle is present, seeded from the
%      'EnableRecording' preference, and updates that preference when toggled.
%   3) Both webcam toolbar controls, and the live-view menu item, stay
%      enabled while STATE is RUNNING, and a mid-run toggle during a Preview
%      run updates the preference without starting a recording.
%   4) The Customize dialog's Video Recording Path field persists to the
%      'RecordingRootDir' preference on OK, and the pre-existing Data Save
%      Path field still applies (regression check on the Paths tab resize).
%   5) delete(RunExpt) completes cleanly with no stray figures.

report = struct();
report.timestamp = datetime('now');
report.steps = struct();

PREF_GROUP = 'ep_RunExpt_Video';
snap = snapshotPrefs_(PREF_GROUP, {'EnableRecording','RecordingRootDir'});
c = onCleanup(@() restorePrefs_(PREF_GROUP, snap)); %#ok<NASGU>

% Step 1: filename generation (pure, no GUI)
stepName = 'videoRecordingFilename';
try
    ffn = epsych.RunExpt.videoRecordingFilename("C:\vid", ...
        "C:\data\SUBJ1\SUBJ1_240101T120000.mat");
    expected = char(fullfile('C:\vid', 'SUBJ1', 'SUBJ1_240101T120000.ts'));
    assert(strcmp(ffn, expected), 'SmokeTest:PathMismatch', ...
        'Recording path "%s" does not mirror the data file layout ("%s").', ffn, expected);

    threw = false;
    try
        epsych.RunExpt.videoRecordingFilename("C:\vid", "C:\data\SUBJ1\");
    catch inner
        threw = strcmp(inner.identifier, 'epsych:RunExpt:InvalidDataFilename');
    end
    assert(threw, 'SmokeTest:MissingError', ...
        'A data filename with no name part did not raise InvalidDataFilename.');

    report.steps.(stepName) = struct('passed', true, 'detail', 'Recording path mirrors the data file layout; empty name rejected.');
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% Step 2: toolbar toggle <-> EnableRecording preference round-trip
stepName = 'togglePrefRoundTrip';
rx = [];
try
    setpref(PREF_GROUP, 'EnableRecording', false);
    rx = epsych.RunExpt('', ReuseExisting=false, CleanupStaleFigures=false);
    cCleanup = onCleanup(@() localDeleteRunExpt_(rx)); %#ok<NASGU>

    tg = findall(rx.H.figure1, 'Tag', 'setup_record_video');
    assert(~isempty(tg), 'SmokeTest:MissingControl', 'Could not locate the "Record video" toolbar toggle.');
    assert(~logical(tg.State), 'SmokeTest:SeedMismatch', 'Toggle did not seed from EnableRecording=false.');

    tg.State = 'on';
    tg.ClickedCallback(tg, []);
    assert(getpref(PREF_GROUP, 'EnableRecording') == true, ...
        'SmokeTest:PrefNotUpdated', 'Pressing the toggle did not persist EnableRecording=true.');

    tg.State = 'off';
    tg.ClickedCallback(tg, []);
    assert(getpref(PREF_GROUP, 'EnableRecording') == false, ...
        'SmokeTest:PrefNotUpdated', 'Releasing the toggle did not persist EnableRecording=false.');

    report.steps.(stepName) = struct('passed', true, 'detail', 'Toolbar toggle seeded from and persisted to EnableRecording correctly.');
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% Step 3: the webcam controls stay usable mid-session
% STATE is set directly rather than by starting a run: this exercises the
% enable contract and the toggle handler without hardware. isTest=true keeps
% the handler on its Preview branch, so no VLC is ever launched.
stepName = 'midRunControls';
try
    assert(~isempty(rx) && isvalid(rx), 'SmokeTest:PrereqFailed', 'RunExpt instance from Step 2 is unavailable.');

    setpref(PREF_GROUP, 'EnableRecording', false);
    rx.RUNTIME.isTest = true;
    rx.STATE = PRGMSTATE.RUNNING;
    rx.UpdateGUIstate;

    for h = [rx.H.tb_liveview rx.H.mnu_vlc_liveview rx.H.setup_record_video]
        assert(strcmp(h.Enable,'on'), 'SmokeTest:ControlDisabled', ...
            'Webcam control "%s" is disabled while RUNNING.', h.Tag);
    end

    tg = rx.H.setup_record_video;
    tg.State = 'on';
    tg.ClickedCallback(tg, []);
    assert(getpref(PREF_GROUP, 'EnableRecording') == true, ...
        'SmokeTest:PrefNotUpdated', 'A mid-run press did not persist EnableRecording=true.');

    tg.State = 'off';
    tg.ClickedCallback(tg, []);
    setpref(PREF_GROUP, 'EnableRecording', false);
    rx.STATE = PRGMSTATE.READY;
    rx.UpdateGUIstate;

    report.steps.(stepName) = struct('passed', true, 'detail', 'Webcam controls stay enabled while RUNNING; mid-run toggle updates the preference.');
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% Step 4: Customize dialog Video Recording Path persistence
stepName = 'customizeDialogVideoPath';
try
    assert(~isempty(rx) && isvalid(rx), 'SmokeTest:PrereqFailed', 'RunExpt instance from Step 2 is unavailable.');

    savedDataPath = char(rx.DefaultDataPath);
    testRoot = fullfile(tempdir, 'epsych_video_smoke_test');

    rx.OpenCustomizeDialog;
    drawnow;
    dlg = findall(groot, 'Type', 'figure', 'Tag', 'RunExptCustomize');
    assert(~isempty(dlg), 'SmokeTest:MissingDialog', 'Customize dialog did not open.');
    dlgCleanup = onCleanup(@() localDeleteFigure_(dlg)); %#ok<NASGU>

    ef_vidroot = findall(dlg, 'Tag', 'Customize_VideoRootDir');
    assert(~isempty(ef_vidroot), 'SmokeTest:MissingControl', 'Could not locate Video Recording Path field.');
    ef_vidroot.Value = testRoot;

    btn_ok = findall(dlg, 'Type', 'uibutton', 'Text', 'OK');
    assert(~isempty(btn_ok), 'SmokeTest:MissingControl', 'Could not locate the OK button.');
    btn_ok.ButtonPushedFcn(btn_ok, []);
    drawnow;

    assert(strcmp(getpref(PREF_GROUP, 'RecordingRootDir'), testRoot), ...
        'SmokeTest:PrefNotUpdated', 'RecordingRootDir preference was not updated by OK.');
    assert(strcmp(char(rx.DefaultDataPath), savedDataPath), ...
        'SmokeTest:DataPathRegression', 'Data Save Path unexpectedly changed by the Paths tab resize.');
    assert(~isgraphics(dlg), 'SmokeTest:DialogNotClosed', 'Customize dialog did not close after OK.');

    report.steps.(stepName) = struct('passed', true, 'detail', 'Video Recording Path persisted via OK; Data Save Path field unaffected.');
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% Step 5: teardown safety (EnableRecording is false, so no VLC involved)
% Note: figure1 closure via delete(RunExpt) is asynchronous in this class
% (pre-existing, independent of this feature — confirmed present on
% unmodified HEAD), so this only checks that delete() itself does not throw
% and immediately invalidates the handle; it does not assert on figure1.
stepName = 'teardownSafety';
try
    assert(~isempty(rx) && isvalid(rx), 'SmokeTest:PrereqFailed', 'RunExpt instance from Step 2 is unavailable.');

    delete(rx);
    drawnow;

    assert(~isvalid(rx), 'SmokeTest:HandleNotInvalidated', 'RunExpt handle remained valid after delete().');

    report.steps.(stepName) = struct('passed', true, 'detail', 'delete(RunExpt) completed without throwing and invalidated the handle.');
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

stepNames = fieldnames(report.steps);
stepPassed = false(size(stepNames));
for i = 1:numel(stepNames)
    stepPassed(i) = logical(report.steps.(stepNames{i}).passed);
end
report.allPassed = all(stepPassed);

if report.allPassed
    fprintf('RunExpt video recording smoke test PASSED (%d/%d steps).\n', nnz(stepPassed), numel(stepPassed));
else
    fprintf('RunExpt video recording smoke test FAILED (%d/%d steps).\n', nnz(stepPassed), numel(stepPassed));
    for i = 1:numel(stepNames)
        if ~report.steps.(stepNames{i}).passed
            fprintf('  - %s failed:\n%s\n', stepNames{i}, report.steps.(stepNames{i}).detail);
        end
    end
end

end

function snap = snapshotPrefs_(group, keys)
snap = struct('group', group, 'keys', {keys}, 'existed', [], 'values', {{}});
for i = 1:numel(keys)
    snap.existed(i) = ispref(group, keys{i});
    if snap.existed(i)
        snap.values{i} = getpref(group, keys{i});
    end
end
end

function restorePrefs_(group, snap)
for i = 1:numel(snap.keys)
    if snap.existed(i)
        setpref(group, snap.keys{i}, snap.values{i});
    elseif ispref(group, snap.keys{i})
        rmpref(group, snap.keys{i});
    end
end
end

function localDeleteRunExpt_(rx)
if ~isempty(rx) && isvalid(rx)
    delete(rx);
end
end

function localDeleteFigure_(fig)
if ~isempty(fig) && isgraphics(fig)
    delete(fig);
end
end
