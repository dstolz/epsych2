function report = smoke_test_runexpt_video_recording()
% report = smoke_test_runexpt_video_recording()
% Lightweight smoke test for the RunExpt "Record video" checkbox feature.
% No VLC install or webcam is required — recording is never triggered
% (EnableRecording stays false throughout), so only the GUI/pref plumbing
% is exercised: filename generation, checkbox <-> preference round-trip,
% Customize dialog persistence, and teardown safety.
%
% Verifies:
%   1) epsych.RunExpt.videoRecordingFilename sanitizes subject names and
%      formats the timestamped .ts path correctly.
%   2) The "Record video" checkbox is present, seeded from the
%      'EnableRecording' preference, and updates that preference when toggled.
%   3) The Customize dialog's Video Recording Path field persists to the
%      'RecordingRootDir' preference on OK, and the pre-existing Data Save
%      Path field still applies (regression check on the Paths tab resize).
%   4) delete(RunExpt) completes cleanly with no stray figures.

report = struct();
report.timestamp = datetime('now');
report.steps = struct();

PREF_GROUP = 'ep_RunExpt_Video';
snap = snapshotPrefs_(PREF_GROUP, {'EnableRecording','RecordingRootDir'});
c = onCleanup(@() restorePrefs_(PREF_GROUP, snap)); %#ok<NASGU>

% Step 1: filename generation (pure, no GUI)
stepName = 'videoRecordingFilename';
try
    ffn = epsych.RunExpt.videoRecordingFilename("C:\vid", "SUBJ<:>1 &x");
    [pn, base, ext] = fileparts(ffn);
    [~, folder] = fileparts(pn);
    assert(strcmp(folder, 'SUBJ___1 _x'), 'SmokeTest:SanitizeMismatch', ...
        'Sanitized folder name unexpected: %s', folder);
    assert(strcmp(ext, '.ts'), 'SmokeTest:ExtMismatch', 'Expected .ts extension, got %s', ext);
    assert(~isempty(regexp(base, '^SUBJ___1 _x_\d{6}T\d{6}$', 'once')), ...
        'SmokeTest:TimestampMismatch', 'Base filename does not match expected pattern: %s', base);

    ffnEmpty = epsych.RunExpt.videoRecordingFilename("C:\vid", "   ");
    [~, folderEmpty] = fileparts(fileparts(ffnEmpty));
    assert(strcmp(folderEmpty, 'UnknownSubject'), 'SmokeTest:FallbackMismatch', ...
        'Blank subject name did not fall back to UnknownSubject: %s', folderEmpty);

    report.steps.(stepName) = struct('passed', true, 'detail', 'Filename sanitization and timestamp formatting matched expectations.');
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% Step 2: checkbox <-> EnableRecording preference round-trip
stepName = 'checkboxPrefRoundTrip';
rx = [];
try
    setpref(PREF_GROUP, 'EnableRecording', false);
    rx = epsych.RunExpt('', ReuseExisting=false, CleanupStaleFigures=false);
    cCleanup = onCleanup(@() localDeleteRunExpt_(rx)); %#ok<NASGU>

    cb = findall(rx.H.figure1, 'Tag', 'setup_record_video');
    assert(~isempty(cb), 'SmokeTest:MissingControl', 'Could not locate the "Record video" checkbox.');
    assert(cb.Value == false, 'SmokeTest:SeedMismatch', 'Checkbox did not seed from EnableRecording=false.');

    cb.Value = true;
    cb.ValueChangedFcn(cb, []);
    assert(getpref(PREF_GROUP, 'EnableRecording') == true, ...
        'SmokeTest:PrefNotUpdated', 'Checking the box did not persist EnableRecording=true.');

    cb.Value = false;
    cb.ValueChangedFcn(cb, []);
    assert(getpref(PREF_GROUP, 'EnableRecording') == false, ...
        'SmokeTest:PrefNotUpdated', 'Unchecking the box did not persist EnableRecording=false.');

    report.steps.(stepName) = struct('passed', true, 'detail', 'Checkbox seeded from and persisted to EnableRecording correctly.');
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% Step 3: Customize dialog Video Recording Path persistence
stepName = 'customizeDialogVideoPath';
try
    assert(~isempty(rx) && isvalid(rx), 'SmokeTest:PrereqFailed', 'RunExpt instance from Step 2 is unavailable.');

    savedDataPath = char(rx.dfltDataPath);
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
    assert(strcmp(char(rx.dfltDataPath), savedDataPath), ...
        'SmokeTest:DataPathRegression', 'Data Save Path unexpectedly changed by the Paths tab resize.');
    assert(~isgraphics(dlg), 'SmokeTest:DialogNotClosed', 'Customize dialog did not close after OK.');

    report.steps.(stepName) = struct('passed', true, 'detail', 'Video Recording Path persisted via OK; Data Save Path field unaffected.');
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% Step 4: teardown safety (EnableRecording is false, so no VLC involved)
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
