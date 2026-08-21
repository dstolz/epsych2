function report = smoke_test_vlcrecorder_window_opts(options)
% report = smoke_test_vlcrecorder_window_opts()
% report = smoke_test_vlcrecorder_window_opts(LaunchVlc=true)
% Smoke test for the hw.VlcRecorder MinimalView / AlwaysOnTop window options
% and their controls in gui.VlcRecorderSetup.
%
% Verifies:
%   1) Defaults: MinimalView on, AlwaysOnTop off, and both round-trip through
%      set_parameter/get_parameter.
%   2) Parameter metadata: declared Boolean, and PersistWithPhase so a saved
%      phase restores them (hw.Parameter.isTransientControl would otherwise
%      classify a never-refreshed Boolean as a momentary button).
%   3) gui.VlcRecorderSetup seeds both checkboxes from the recorder and
%      commits them back on Apply, without opening a webcam.
%   4) (Gated, LaunchVlc=true) VLC actually accepts the composed command line:
%      trigger('Play') starts VLC with --qt-minimal-view/--video-on-top and it
%      survives argument parsing, then trigger('Stop') shuts it down.
%      Opens a real VLC window and takes the camera, so it is off by default.
%
% See also: hw.VlcRecorder, gui.VlcRecorderSetup, smoke_test_vlcrecorder_setup

arguments
    options.LaunchVlc (1,1) logical = false
end

report = struct();
report.timestamp = datetime('now');
report.steps = struct();

% Step 1: defaults and round-trip through the public parameter API
stepName = 'defaultsAndRoundTrip';
try
    rec = hw.VlcRecorder();
    c1 = onCleanup(@() delete(rec));

    assert(isequal(logical(rec.get_parameter('MinimalView')), true), ...
        'SmokeTest:MinimalViewDefault', 'MinimalView must default to true.');
    assert(isequal(logical(rec.get_parameter('AlwaysOnTop')), false), ...
        'SmokeTest:AlwaysOnTopDefault', 'AlwaysOnTop must default to false.');

    rec.set_parameter('MinimalView', false);
    rec.set_parameter('AlwaysOnTop', true);
    assert(isequal(logical(rec.get_parameter('MinimalView')), false), ...
        'SmokeTest:MinimalViewRoundTrip', 'MinimalView did not round-trip.');
    assert(isequal(logical(rec.get_parameter('AlwaysOnTop')), true), ...
        'SmokeTest:AlwaysOnTopRoundTrip', 'AlwaysOnTop did not round-trip.');

    report.steps.(stepName) = struct('passed', true, ...
        'detail', 'Defaults are MinimalView=1, AlwaysOnTop=0; both round-trip.');
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% Step 2: parameter metadata as seen by the protocol/phase machinery
stepName = 'parameterMetadata';
try
    rec = hw.VlcRecorder();
    c2 = onCleanup(@() localDisconnect_(rec));
    rec.connect();

    for name = ["MinimalView", "AlwaysOnTop"]
        P = rec.find_parameter(char(name));
        assert(~isempty(P), 'SmokeTest:ParameterMissing', ...
            'Parameter "%s" was not created by setup_interface.', name);
        assert(strcmp(P.Type, 'Boolean'), 'SmokeTest:ParameterType', ...
            'Parameter "%s" must be Boolean, got "%s".', name, P.Type);
        assert(P.PersistWithPhase, 'SmokeTest:ParameterTransient', ...
            ['Parameter "%s" must set PersistWithPhase, or a saved phase ' ...
            'will drop it as a transient control toggle.'], name);
        assert(~P.isTransientControl(P), 'SmokeTest:ParameterTransient2', ...
            'Parameter "%s" is still classified as a transient control.', name);
    end

    report.steps.(stepName) = struct('passed', true, ...
        'detail', 'Both parameters are Boolean and persist with a saved phase.');
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% Step 3: GUI seeds from the recorder and commits back, no webcam opened
stepName = 'guiSeedAndCommit';
try
    rec = hw.VlcRecorder();
    rec.set_parameter('MinimalView', false);
    rec.set_parameter('AlwaysOnTop', true);

    g = gui.VlcRecorderSetup(rec, EnablePreview=false, PersistPrefs=false);
    c3 = onCleanup(@() localDelete_(g, rec));

    cbMin = findall(g.Parent, 'Tag', 'VlcRecorderSetup_MinimalViewCheckBox');
    cbTop = findall(g.Parent, 'Tag', 'VlcRecorderSetup_AlwaysOnTopCheckBox');
    assert(isscalar(cbMin) && isscalar(cbTop), 'SmokeTest:CheckBoxMissing', ...
        'Expected one MinimalView and one AlwaysOnTop checkbox.');

    assert(cbMin.Value == false && cbTop.Value == true, 'SmokeTest:GuiSeed', ...
        'Checkboxes did not seed from the recorder (got %d / %d).', cbMin.Value, cbTop.Value);

    % Flip both and Apply; the recorder must follow.
    cbMin.Value = true;
    cbTop.Value = false;
    btnApply = findall(g.Parent, 'Tag', 'VlcRecorderSetup_ApplyButton');
    btnApply.ButtonPushedFcn(btnApply, []);

    assert(isequal(logical(rec.get_parameter('MinimalView')), true) && ...
        isequal(logical(rec.get_parameter('AlwaysOnTop')), false), ...
        'SmokeTest:GuiCommit', 'Apply did not push the checkbox values to the recorder.');

    % Apply/OK must stay reachable: the control column grew past the height of
    % a window position saved before these controls existed.
    ctrlGrid = ancestor(btnApply, 'matlab.ui.container.GridLayout');
    assert(strcmp(ctrlGrid.Scrollable, 'on'), 'SmokeTest:GridNotScrollable', ...
        'Control column must be scrollable so Apply/OK cannot be clipped.');

    report.steps.(stepName) = struct('passed', true, ...
        'detail', 'Checkboxes seed from the recorder and commit on Apply.');
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% Step 4 (gated): VLC accepts the composed command line
stepName = 'vlcAcceptsWindowOptions';
if ~options.LaunchVlc
    report.steps.(stepName) = struct('passed', true, ...
        'detail', 'Skipped (pass LaunchVlc=true to launch a real VLC window).');
else
    try
        exe = hw.VlcRecorder.findVlcExe();
        assert(strlength(exe) > 0, 'SmokeTest:NoVlc', 'vlc.exe could not be located.');

        rec = hw.VlcRecorder();
        c4 = onCleanup(@() localDisconnect_(rec));
        rec.connect();
        rec.set_parameter('MinimalView', true);
        rec.set_parameter('AlwaysOnTop', true);

        ok = rec.trigger('Play');
        assert(ok == 1, 'SmokeTest:PlayFailed', ...
            ['VLC did not survive launch with --qt-minimal-view/--video-on-top. ' ...
            'VLC rejects an unknown option and exits immediately, so this is ' ...
            'how a bad flag shows up.']);
        pause(4);
        rec.trigger('Stop');

        report.steps.(stepName) = struct('passed', true, ...
            'detail', sprintf('VLC launched and stopped cleanly with both window options (%s).', exe));
    catch ME
        report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
    end
end

% Summary
names = fieldnames(report.steps);
passed = cellfun(@(n) report.steps.(n).passed, names);
report.allPassed = all(passed);
fprintf('\nsmoke_test_vlcrecorder_window_opts: %d/%d steps passed\n', sum(passed), numel(passed));
for i = 1:numel(names)
    if passed(i)
        mark = 'PASS';
    else
        mark = 'FAIL';
    end
    fprintf('  [%s] %-28s %s\n', mark, names{i}, report.steps.(names{i}).detail);
end
fprintf('\n');
end


function localDisconnect_(rec)
try
    if ~isempty(rec) && isvalid(rec)
        rec.disconnect();
        delete(rec);
    end
catch ME
    vprintf(1, 'smoke_test_vlcrecorder_window_opts: cleanup failed (%s).', ME.message);
end
end


function localDelete_(g, rec)
try
    if ~isempty(g) && isvalid(g)
        delete(g);
    end
catch ME
    vprintf(1, 'smoke_test_vlcrecorder_window_opts: GUI cleanup failed (%s).', ME.message);
end
try
    if ~isempty(rec) && isvalid(rec)
        delete(rec);
    end
catch ME
    vprintf(1, 'smoke_test_vlcrecorder_window_opts: recorder cleanup failed (%s).', ME.message);
end
end
