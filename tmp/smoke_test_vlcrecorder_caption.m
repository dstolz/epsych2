function report = smoke_test_vlcrecorder_caption(options)
% report = smoke_test_vlcrecorder_caption()
% report = smoke_test_vlcrecorder_caption(LaunchVlc=true)
% Smoke test for the hw.VlcRecorder recording caption and frame transform
% (GitHub issue #21), and their controls in gui.VlcRecorderSetup.
%
% Verifies:
%   1) Defaults, and that every new parameter round-trips through
%      set_parameter/get_parameter.
%   2) An unknown position/colour/transform is refused and the previous value
%      kept, rather than reaching VLC as a malformed option.
%   3) hw.VlcRecorder.expandCaption fills {tokens}, drops unsupplied ones
%      rather than leaving literal braces, and joins {subjects}.
%   4) gui.VlcRecorderSetup seeds the new controls from the recorder and
%      commits them back on Apply, without opening a webcam.
%   5) (Gated, LaunchVlc=true) VLC really applies the composed filter chain:
%      records with Transform='90' and checks the recorded frame's dimensions
%      swapped. This is the regression that matters -- inside --sout, a
%      vfilter chain must be single-quoted or VLC silently drops everything
%      after the first filter, with no error and no log line. Takes the camera
%      for ~6 s, so it is off by default.
%
%   matlab -batch "run('tmp/smoke_test_vlcrecorder_caption.m')"
%
% See also: hw.VlcRecorder, gui.VlcRecorderSetup, documentation/hw/hw_VlcRecorder.md

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

    assert(isequal(logical(rec.get_parameter('EnableCaption')), false), ...
        'SmokeTest:CaptionDefault', 'EnableCaption must default to false.');
    assert(strcmp(rec.get_parameter('CaptionPosition'), 'southwest'), ...
        'SmokeTest:PositionDefault', 'CaptionPosition must default to southwest.');
    assert(strcmp(rec.get_parameter('Transform'), 'none'), ...
        'SmokeTest:TransformDefault', 'Transform must default to none.');
    assert(contains(rec.get_parameter('CaptionTemplate'), '{subject}'), ...
        'SmokeTest:TemplateDefault', 'The default template should name {subject}.');

    rec.set_parameter('EnableCaption', true);
    rec.set_parameter('CaptionTemplate', 'rat {subject} @ {time}');
    rec.set_parameter('CaptionPosition', 'northeast');
    rec.set_parameter('CaptionColor', 'white');
    rec.set_parameter('CaptionSize', 32);
    rec.set_parameter('Transform', 'hflip');
    rec.set_parameter('CaptionText', 'resolved');

    assert(isequal(logical(rec.get_parameter('EnableCaption')), true), 'EnableCaption did not round-trip.');
    assert(strcmp(rec.get_parameter('CaptionTemplate'), 'rat {subject} @ {time}'), 'CaptionTemplate did not round-trip.');
    assert(strcmp(rec.get_parameter('CaptionPosition'), 'northeast'), 'CaptionPosition did not round-trip.');
    assert(strcmp(rec.get_parameter('CaptionColor'), 'white'), 'CaptionColor did not round-trip.');
    assert(isequal(rec.get_parameter('CaptionSize'), 32), 'CaptionSize did not round-trip.');
    assert(strcmp(rec.get_parameter('Transform'), 'hflip'), 'Transform did not round-trip.');
    assert(strcmp(rec.get_parameter('CaptionText'), 'resolved'), 'CaptionText did not round-trip.');

    report.steps.(stepName) = struct('passed', true, ...
        'detail', 'Defaults are caption off / southwest / none; all new parameters round-trip.');
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% Step 2: a bad enumerated value is refused, not forwarded to VLC
stepName = 'rejectsUnknownValues';
try
    rec = hw.VlcRecorder();
    c2 = onCleanup(@() delete(rec));

    rec.set_parameter('CaptionPosition', 'southwest');
    evalc('rec.set_parameter(''CaptionPosition'', ''up-a-bit'')');
    assert(strcmp(rec.get_parameter('CaptionPosition'), 'southwest'), ...
        'SmokeTest:BadPosition', 'An unknown CaptionPosition must leave the previous value in place.');

    evalc('rec.set_parameter(''CaptionColor'', ''puce'')');
    assert(strcmp(rec.get_parameter('CaptionColor'), 'yellow'), ...
        'SmokeTest:BadColor', 'An unknown CaptionColor must leave the previous value in place.');

    evalc('rec.set_parameter(''Transform'', ''sideways'')');
    assert(strcmp(rec.get_parameter('Transform'), 'none'), ...
        'SmokeTest:BadTransform', 'An unknown Transform must leave the previous value in place.');

    % Size is clamped rather than refused: it is a number with a sane range.
    rec.set_parameter('CaptionSize', 5000);
    assert(isequal(rec.get_parameter('CaptionSize'), 200), 'CaptionSize should clamp to its Max.');
    rec.set_parameter('CaptionSize', 0);
    assert(isequal(rec.get_parameter('CaptionSize'), 6), 'CaptionSize should clamp to its Min.');

    report.steps.(stepName) = struct('passed', true, ...
        'detail', 'Unknown position/colour/transform keep the previous value; size clamps.');
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% Step 3: token expansion
stepName = 'expandCaption';
try
    when = datetime(2026, 9, 1, 15, 36, 0);
    tok = struct('Subject', "SUBJ-042", 'Subjects', ["SUBJ-042" "SUBJ-043"], ...
                 'Box', "1", 'When', when);

    txt = hw.VlcRecorder.expandCaption("{subject}  {datetime}", tok);
    assert(txt == "SUBJ-042  2026-09-01 15:36:00", 'got "%s"', txt);

    txt = hw.VlcRecorder.expandCaption("{subjects} box {box} {date} {time}", tok);
    assert(txt == "SUBJ-042, SUBJ-043 box 1 2026-09-01 15:36:00", 'got "%s"', txt);

    % An unsupplied token expands to nothing: a caption reading "{subject}"
    % over a recording is worse than one with a gap.
    txt = hw.VlcRecorder.expandCaption("{subject} {date}", struct('When', when));
    assert(~contains(txt, '{'), 'unsupplied tokens must not survive as braces: "%s"', txt);
    assert(txt == "2026-09-01", 'got "%s"', txt);

    % An unknown token is removed too, rather than reaching VLC as literal text.
    txt = hw.VlcRecorder.expandCaption("a {nonsense} b", tok);
    assert(txt == "a  b" || txt == "a b", 'got "%s"', txt);

    assert(hw.VlcRecorder.expandCaption("", tok) == "", 'an empty template should stay empty');

    % sampleCaption stands in for a session, for previewing with none open.
    % Every session token must yield something VISIBLE: a preview that expanded
    % to a bare date would misrepresent the caption's length and position.
    smp = hw.VlcRecorder.sampleCaption("{subject} box {box}  {datetime}");
    assert(contains(smp, "SUBJECT") && contains(smp, "box 1"), ...
        'sampleCaption should fill session tokens with stand-ins: "%s"', smp);
    assert(~contains(smp, '{'), 'sampleCaption left a token unexpanded: "%s"', smp);

    report.steps.(stepName) = struct('passed', true, ...
        'detail', 'Tokens fill in; unsupplied and unknown ones are dropped; sampleCaption stands in for a session.');
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% Step 4: the setup dialog seeds from, and commits to, the recorder
stepName = 'setupGuiRoundTrip';
try
    rec = hw.VlcRecorder();
    c4 = onCleanup(@() delete(rec));
    rec.set_parameter('EnableCaption', true);
    rec.set_parameter('CaptionTemplate', 'seeded {subject}');
    rec.set_parameter('CaptionPosition', 'northeast');
    rec.set_parameter('CaptionColor', 'cyan');
    rec.set_parameter('CaptionSize', 28);
    rec.set_parameter('Transform', '180');

    % EnablePreview/PersistPrefs off: no webcam, and the rig's own preferences
    % must not be rewritten by a test. The dialog's widgets are protected, so
    % they are reached by Tag exactly as the window-options smoke test does.
    g = gui.VlcRecorderSetup(rec, EnablePreview=false, PersistPrefs=false);
    c4b = onCleanup(@() delete(g));
    widget = @(tag) findall(g.Parent, 'Tag', ['VlcRecorderSetup_' tag]);

    cbCap  = widget('CaptionCheckBox');
    edTmpl = widget('CaptionTemplateField');
    ddPos  = widget('CaptionPositionDropDown');
    ddCol  = widget('CaptionColorDropDown');
    spSize = widget('CaptionSizeSpinner');
    ddXfrm = widget('TransformDropDown');
    assert(all(cellfun(@isscalar, {cbCap, edTmpl, ddPos, ddCol, spSize, ddXfrm})), ...
        'SmokeTest:WidgetMissing', 'A caption or transform control is missing from the dialog.');

    assert(cbCap.Value == true, 'checkbox did not seed');
    assert(strcmp(edTmpl.Value, 'seeded {subject}'), 'template did not seed');
    assert(strcmp(ddPos.Value, 'northeast'), 'position did not seed');
    assert(strcmp(ddCol.Value, 'cyan'), 'colour did not seed');
    assert(isequal(spSize.Value, 28), 'size did not seed');
    assert(strcmp(ddXfrm.Value, '180'), 'transform did not seed');

    % Unticking greys the caption's own controls but keeps their values.
    cbCap.Value = false;
    cbCap.ValueChangedFcn(cbCap, []);
    assert(edTmpl.Enable == "off", 'template should grey out when the caption is off');
    assert(strcmp(edTmpl.Value, 'seeded {subject}'), 'unticking must not discard the template');

    cbCap.Value = true;
    cbCap.ValueChangedFcn(cbCap, []);
    assert(edTmpl.Enable == "on", 're-ticking should re-enable the template');

    edTmpl.Value = 'edited {box}';
    ddPos.Value  = 'south';
    ddXfrm.Value = 'vflip';
    btnApply = widget('ApplyButton');
    btnApply.ButtonPushedFcn(btnApply, []);

    assert(strcmp(rec.get_parameter('CaptionTemplate'), 'edited {box}'), 'template did not commit');
    assert(strcmp(rec.get_parameter('CaptionPosition'), 'south'), 'position did not commit');
    assert(strcmp(rec.get_parameter('Transform'), 'vflip'), 'transform did not commit');

    report.steps.(stepName) = struct('passed', true, ...
        'detail', 'Dialog seeds every new control, greys them when unticked, and commits on Apply.');
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% Step 5 (gated): VLC really applies the chained filters
stepName = 'vlcAppliesTransform';
if ~options.LaunchVlc
    report.steps.(stepName) = struct('passed', true, 'detail', 'Skipped (LaunchVlc=false).');
else
    try
        outDir = fullfile(tempdir, 'epsych_smoke_vlc_caption');
        if isfolder(outDir), rmdir(outDir, 's'); end
        mkdir(outDir);
        cleanupOut = onCleanup(@() rmdir(outDir, 's'));
        outFile = fullfile(outDir, 'rotated.ts');

        rec = hw.VlcRecorder();
        c5 = onCleanup(@() localStop_(rec));
        rec.connect();
        % The class default names a laptop's built-in camera; use whatever
        % device this rig was actually configured with, or VLC opens nothing
        % and records an empty file.
        rec.set_parameter('DeviceName', ...
            getpref('ep_RunExpt_Video', 'DeviceName', char(rec.get_parameter('DeviceName'))));
        rec.set_parameter('Resolution', [640 480]);
        rec.set_parameter('CropBottom', 40);
        rec.set_parameter('Transform', '90');
        rec.set_parameter('EnableCaption', true);
        rec.set_parameter('CaptionText', 'SMOKE TEST CAPTION');
        rec.set_parameter('RecordingFile', outFile);

        assert(rec.trigger('Play'), 'SmokeTest:PlayFailed', 'VLC did not start.');
        pause(6);
        rec.trigger('Stop');
        pause(2);

        d = dir(outFile);
        assert(~isempty(d) && d.bytes > 0, 'SmokeTest:NoRecording', ...
            'No recording was produced at "%s".', outFile);

        % Both filters must have applied. Crop alone leaves 640 wide; the
        % rotation is what the sout quoting decides, so a still-640-wide frame
        % is exactly the silent-drop regression.
        sz = localFrameSize_(rec.get_parameter('VlcExePath'), outFile, outDir);
        assert(sz(2) > sz(1), 'SmokeTest:TransformDropped', ...
            ['Recorded frame is %dx%d: the transform did not apply. Inside --sout a ' ...
             'vfilter chain must be single-quoted or VLC keeps only the first filter.'], ...
            sz(1), sz(2));

        report.steps.(stepName) = struct('passed', true, ...
            'detail', sprintf('Recorded %d bytes; frame %dx%d, so crop and transform both applied.', ...
            d.bytes, sz(1), sz(2)));
    catch ME
        report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
    end
end

% Step 6 (gated): the preview branch accepts the caption options
stepName = 'vlcPreviewCaption';
if ~options.LaunchVlc
    report.steps.(stepName) = struct('passed', true, 'detail', 'Skipped (LaunchVlc=false).');
else
    try
        rec = hw.VlcRecorder();
        c6 = onCleanup(@() localStop_(rec));
        rec.connect();
        rec.set_parameter('DeviceName', ...
            getpref('ep_RunExpt_Video', 'DeviceName', char(rec.get_parameter('DeviceName'))));
        rec.set_parameter('RecordingFile', '');   % display-only branch
        rec.set_parameter('DisplayBanner', '');   % empty, so the caption wins
        rec.set_parameter('EnableCaption', true);
        rec.set_parameter('CaptionText', hw.VlcRecorder.sampleCaption("{subject}  {datetime}"));
        rec.set_parameter('CaptionPosition', 'southwest');
        rec.set_parameter('CaptionSize', 24);

        % VLC rejects an unknown option and exits immediately, so surviving the
        % launch is how a malformed --marq-* shows up. The overlay itself is a
        % sub-source drawn at the vout and cannot be captured by VLC's scene
        % filter, so it is verified by eye rather than asserted here (see
        % documentation/hw/hw_VlcRecorder.md).
        assert(rec.trigger('Play') == 1, 'SmokeTest:PreviewFailed', ...
            'VLC did not survive launch with the preview caption options.');
        pause(4);
        rec.trigger('Stop');

        report.steps.(stepName) = struct('passed', true, ...
            'detail', 'Display-only launch accepts the caption options and runs.');
    catch ME
        report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
    end
end

% ===== Summary ===========================================================
names = fieldnames(report.steps);
nPass = 0;
fprintf('\nsmoke_test_vlcrecorder_caption\n');
for i = 1:numel(names)
    s = report.steps.(names{i});
    if s.passed
        nPass = nPass + 1;
        fprintf('  PASS  %-24s %s\n', names{i}, s.detail);
    else
        fprintf('  FAIL  %-24s %s\n', names{i}, s.detail);
    end
end
report.allPassed = (nPass == numel(names));
if report.allPassed
    fprintf('ALL PASS (%d/%d)\n', nPass, numel(names));
else
    fprintf('FAILURES: %d of %d steps failed\n', numel(names) - nPass, numel(names));
end

end


function localStop_(rec)
% Stop VLC and release the interface, ignoring a recorder already torn down.
try
    rec.trigger('Stop');
catch
end
try
    delete(rec);
catch
end
end


function sz = localFrameSize_(vlcExe, mediaFile, workDir)
% sz = localFrameSize_(vlcExe, mediaFile, workDir)
% [width height] of a frame decoded out of mediaFile, via VLC's scene filter.
% Reading the recording back is the only way to see what the filter chain
% actually produced -- the composed command line says only what was asked for.
frameDir = fullfile(workDir, 'frames');
if ~isfolder(frameDir), mkdir(frameDir); end

cmd = sprintf(['"%s" -I dummy --no-audio --quiet "%s" --video-filter=scene ' ...
    '--scene-format=png --scene-ratio=30 --scene-prefix=sm --scene-path="%s" ' ...
    '--stop-time=3 vlc://quit'], char(vlcExe), mediaFile, frameDir);
[~, ~] = system(cmd);

f = dir(fullfile(frameDir, 'sm*.png'));
assert(~isempty(f), 'SmokeTest:NoFrame', 'Could not decode a frame from the recording.');
info = imfinfo(fullfile(f(1).folder, f(1).name));
sz = [info.Width info.Height];
end
