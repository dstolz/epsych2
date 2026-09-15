function report = smoke_test_vlcrecorder_audio(options)
% report = smoke_test_vlcrecorder_audio()
% report = smoke_test_vlcrecorder_audio(LaunchVlc=true)
% Smoke test for hw.VlcRecorder's optional audio track (issue #26) and its
% controls in gui.VlcRecorderSetup.
%
% Verifies:
%   1) Defaults: RecordAudio on, AudioDevice '' (VLC's default device), and
%      both round-trip through set_parameter/get_parameter.
%   2) Parameter metadata: RecordAudio is a Boolean that persists with a
%      saved phase; AudioDevice is a String.
%   3) listAudioDevices returns a cell array (content depends on the machine).
%   4) gui.VlcRecorderSetup seeds the checkbox and device dropdown from the
%      recorder and commits them back on Apply, with '(default audio device)'
%      standing for ''. No webcam is opened.
%   5) (Gated, LaunchVlc=true) VLC records a file that carries an audio
%      stream, checked with ffmpeg when it can be found. Opens a real VLC
%      window and takes the camera and microphone, so it is off by default.
%
% See also: hw.VlcRecorder, gui.VlcRecorderSetup, smoke_test_vlcrecorder_window_opts

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

    assert(isequal(logical(rec.get_parameter('RecordAudio')), true), ...
        'SmokeTest:RecordAudioDefault', 'RecordAudio must default to true.');
    assert(isempty(rec.get_parameter('AudioDevice')), ...
        'SmokeTest:AudioDeviceDefault', 'AudioDevice must default to '''' (VLC''s default).');

    rec.set_parameter('RecordAudio', false);
    rec.set_parameter('AudioDevice', 'Microphone (Some WebCam)');
    assert(isequal(logical(rec.get_parameter('RecordAudio')), false), ...
        'SmokeTest:RecordAudioRoundTrip', 'RecordAudio did not round-trip.');
    assert(strcmp(rec.get_parameter('AudioDevice'), 'Microphone (Some WebCam)'), ...
        'SmokeTest:AudioDeviceRoundTrip', 'AudioDevice did not round-trip.');

    report.steps.(stepName) = struct('passed', true, ...
        'detail', 'Defaults are RecordAudio=1, AudioDevice=''''; both round-trip.');
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% Step 2: parameter metadata as seen by the protocol/phase machinery
stepName = 'parameterMetadata';
try
    rec = hw.VlcRecorder();
    c2 = onCleanup(@() localDisconnect_(rec));
    rec.connect();

    P = rec.find_parameter('RecordAudio');
    assert(~isempty(P), 'SmokeTest:ParameterMissing', 'RecordAudio was not created by setup_interface.');
    assert(strcmp(P.Type, 'Boolean'), 'SmokeTest:ParameterType', 'RecordAudio must be Boolean, got "%s".', P.Type);
    assert(P.PersistWithPhase && ~P.isTransientControl(P), 'SmokeTest:ParameterTransient', ...
        'RecordAudio must persist with a saved phase, not be treated as a button press.');

    P = rec.find_parameter('AudioDevice');
    assert(~isempty(P), 'SmokeTest:ParameterMissing', 'AudioDevice was not created by setup_interface.');
    assert(strcmp(P.Type, 'String'), 'SmokeTest:ParameterType', 'AudioDevice must be String, got "%s".', P.Type);

    report.steps.(stepName) = struct('passed', true, ...
        'detail', 'RecordAudio is a phase-persisted Boolean; AudioDevice is a String.');
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% Step 3: audio device enumeration
stepName = 'listAudioDevices';
try
    devs = hw.VlcRecorder.listAudioDevices();
    assert(iscell(devs), 'SmokeTest:ListType', 'listAudioDevices must return a cell array.');
    report.steps.(stepName) = struct('passed', true, ...
        'detail', sprintf('%d capture device(s): %s', numel(devs), strjoin(string(devs), ' | ')));
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% Step 4: GUI seeds from the recorder and commits back, no webcam opened
stepName = 'guiSeedAndCommit';
try
    rec = hw.VlcRecorder();
    rec.set_parameter('RecordAudio', false);
    rec.set_parameter('AudioDevice', 'Microphone (Unplugged WebCam)');

    g = gui.VlcRecorderSetup(rec, EnablePreview=false, PersistPrefs=false);
    c4 = onCleanup(@() localDelete_(g, rec));
    widget = @(tag) findall(g.Parent, 'Tag', ['VlcRecorderSetup_' tag]);

    cbAud = widget('RecordAudioCheckBox');
    ddDev = widget('AudioDeviceDropDown');
    assert(isscalar(cbAud) && isscalar(ddDev), 'SmokeTest:WidgetMissing', ...
        'Expected one RecordAudio checkbox and one AudioDevice dropdown.');

    assert(cbAud.Value == false, 'SmokeTest:GuiSeed', 'Record audio checkbox did not seed.');
    assert(strcmp(ddDev.Value, 'Microphone (Unplugged WebCam)'), 'SmokeTest:GuiSeed', ...
        'A saved device that is not present must stay selected, got "%s".', ddDev.Value);
    assert(ddDev.Enable == "off", 'SmokeTest:GuiEnable', 'Device dropdown should grey out while audio is off.');

    cbAud.Value = true;
    cbAud.ValueChangedFcn(cbAud, []);
    assert(ddDev.Enable == "on", 'SmokeTest:GuiEnable', 'Device dropdown should enable with audio on.');

    ddDev.Value = ddDev.Items{1};   % the default-device label
    btnApply = widget('ApplyButton');
    btnApply.ButtonPushedFcn(btnApply, []);

    assert(isequal(logical(rec.get_parameter('RecordAudio')), true), ...
        'SmokeTest:GuiCommit', 'Apply did not push RecordAudio.');
    assert(isempty(rec.get_parameter('AudioDevice')), 'SmokeTest:GuiCommit', ...
        'The default-device label must commit AudioDevice = '''', got "%s".', rec.get_parameter('AudioDevice'));

    report.steps.(stepName) = struct('passed', true, ...
        'detail', 'Audio controls seed from the recorder, grey with the checkbox, and commit on Apply.');
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% Step 5 (gated): the recording actually carries an audio stream
stepName = 'vlcRecordsAudio';
if ~options.LaunchVlc
    report.steps.(stepName) = struct('passed', true, ...
        'detail', 'Skipped (pass LaunchVlc=true to record with a real VLC).');
else
    try
        outDir = fullfile(tempdir, 'epsych_smoke_vlc_audio');
        if isfolder(outDir), rmdir(outDir, 's'); end
        mkdir(outDir);
        cleanupOut = onCleanup(@() rmdir(outDir, 's'));
        outFile = fullfile(outDir, 'audio.ts');

        rec = hw.VlcRecorder();
        c5 = onCleanup(@() localDisconnect_(rec));
        rec.connect();
        % The class default names a laptop's built-in camera; use this rig's.
        rec.set_parameter('DeviceName', ...
            getpref('ep_RunExpt_Video', 'DeviceName', char(rec.get_parameter('DeviceName'))));
        rec.set_parameter('AudioDevice', ...
            getpref('ep_RunExpt_Video', 'AudioDevice', ''));
        rec.set_parameter('RecordingFile', outFile);

        assert(rec.trigger('Play') == 1, 'SmokeTest:PlayFailed', ...
            'VLC did not survive launch with audio recording enabled.');
        pause(6);
        rec.trigger('Stop');
        pause(2);

        d = dir(outFile);
        assert(~isempty(d) && d.bytes > 0, 'SmokeTest:NoRecording', ...
            'No recording was produced at "%s".', outFile);

        ff = util.VideoConverter.findFfmpegExe();
        if strlength(ff) == 0
            detail = sprintf('Recorded %d bytes; ffmpeg not found, so the audio stream was not probed.', d.bytes);
        else
            [~, out] = system(sprintf('"%s" -hide_banner -i "%s"', ff, outFile));
            assert(contains(out, 'Audio:'), 'SmokeTest:NoAudioStream', ...
                'The recording has no audio stream. ffmpeg reports:\n%s', out);
            detail = sprintf('Recorded %d bytes with an audio stream.', d.bytes);
        end
        report.steps.(stepName) = struct('passed', true, 'detail', detail);
    catch ME
        report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
    end
end

% Summary
names = fieldnames(report.steps);
passed = cellfun(@(n) report.steps.(n).passed, names);
report.allPassed = all(passed);
fprintf('\nsmoke_test_vlcrecorder_audio: %d/%d steps passed\n', sum(passed), numel(passed));
for i = 1:numel(names)
    if passed(i)
        mark = 'PASS';
    else
        mark = 'FAIL';
    end
    fprintf('  [%s] %-22s %s\n', mark, names{i}, report.steps.(names{i}).detail);
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
    vprintf(1, 'smoke_test_vlcrecorder_audio: cleanup failed (%s).', ME.message);
end
end


function localDelete_(g, rec)
try
    if ~isempty(g) && isvalid(g)
        delete(g);
    end
catch ME
    vprintf(1, 'smoke_test_vlcrecorder_audio: GUI cleanup failed (%s).', ME.message);
end
try
    if ~isempty(rec) && isvalid(rec)
        delete(rec);
    end
catch ME
    vprintf(1, 'smoke_test_vlcrecorder_audio: recorder cleanup failed (%s).', ME.message);
end
end
