function smoke_test_calibration_captions()
% smoke_test_calibration_captions()
% Verify the LiveMonitor's title/subtitle captions, its one-panel-per-view
% mode, and the CalibrationGui's plot tabs and window-capture features.
%
% Three things are checked:
%
%   1. Every panel caption is a short title plus a smaller subtitle holding
%      the measurement's numbers, written together by LiveMonitor.caption_
%      so no view inherits the previous view's subtitle.
%   2. Given five axes, the transfer curve, the background analysis and the
%      delay probe each keep their own panel: drawing one must leave the
%      other two standing, which is what CalibrationGui's tabs rest on.
%      Given three, they still share one panel and clear each other.
%   3. The GUI has a plot tab per stimulus and per diagnostic, no longer has
%      the two view-selecting toolbar buttons or the three View-menu view
%      items, and can capture its window to a file and to the clipboard.
%
% Must run under matlab -batch, where exportapp works headless.
%
%   matlab -batch "cd('tmp'); smoke_test_calibration_captions"

thisDir = fileparts(mfilename('fullpath'));
run(fullfile(thisDir, '..', 'epsych_startup.m'));
addpath(thisDir);   % FakeSpeakerAdapter lives beside this file

cleanupObj = onCleanup(@() delete(findall(groot, 'Type', 'figure')));

%% 1. Monitor with its own figure: no-data captions on every panel.
eng = stimgen.calibration.Engine();
mon = stimgen.calibration.LiveMonitor(eng);

mon.show_engine_state(eng);
assert_caption(mon.AxSignal, 'Response  (no data)', '');
assert_caption(mon.AxSpectrum, 'Spectrum  (no data)', '');
mon.show_calibration(eng);
assert_caption(mon.AxTransfer, 'Calibration transfer curves  (no data)', '');
mon.show_background(eng);
assert_caption(mon.AxTransfer, 'Background noise  (not measured)', '');
fprintf('PASS: no-data captions\n');

%% 2. A short real sweep: live captions carry numbers in the subtitle.
eng.set_adapter(FakeSpeakerAdapter(44100));
eng.set_configuration(ShowLivePlots=true, ReferenceLevel=94, ...
    MicSensitivity=0.01, NormativeValue=80);
mon.MinInterval = 0;   % render every measurement; the test reads the last
eng.calibrate_tones([1000 2000 4000]);

tSig = char(string(mon.AxSignal.Title.String));
sSig = char(string(mon.AxSignal.Subtitle.String));
assert(startsWith(tSig, 'Response'), 'Signal title wrong: %s', tSig);
assert(contains(sSig, 'peak') && contains(sSig, 'RMS'), ...
    'Signal subtitle missing metrics: %s', sSig);

tSpec = char(string(mon.AxSpectrum.Title.String));
sSpec = char(string(mon.AxSpectrum.Subtitle.String));
assert(strcmp(tSpec, 'Spectrum'), 'Spectrum title wrong: %s', tSpec);
assert(contains(sSpec, 'floor'), 'Spectrum subtitle missing floor: %s', sSpec);

tX = char(string(mon.AxTransfer.Title.String));
sX = join_lines(mon.AxTransfer.Subtitle.String);
assert(contains(tX, 'Tone sweep'), 'Transfer title wrong: %s', tX);
assert(contains(sX, 'complete in') && contains(sX, 'dB SPL'), ...
    'Transfer subtitle missing timing/span: %s', sX);
fprintf('PASS: live sweep captions (signal/spectrum/transfer)\n');

%% 3. Committed-LUT view: short title, timestamp in the subtitle.
mon.show_calibration(eng);
tX = char(string(mon.AxTransfer.Title.String));
sX = join_lines(mon.AxTransfer.Subtitle.String);
assert(strcmp(tX, 'Calibration transfer curves'), 'LUT title wrong: %s', tX);
assert(contains(sX, 'measured'), 'LUT subtitle missing timestamp: %s', sX);
fprintf('PASS: committed-LUT caption\n');

%% 4. Latency view: reading in the title, red verdict when unreliable.
lat = fake_latency_(true);
mon.show_latency(lat);
tX = char(string(mon.AxTransfer.Title.String));
sX = join_lines(mon.AxTransfer.Subtitle.String);
assert(contains(tX, '4.170 ms'), 'Latency title missing reading: %s', tX);
assert(contains(sX, 'm of air') && contains(sX, 'searched'), ...
    'Latency subtitle wrong: %s', sX);
assert(isequal(mon.AxTransfer.Title.Color(:).', [0 0 0]), ...
    'Valid latency title should be black');

mon.show_latency(fake_latency_(false));
tX = char(string(mon.AxTransfer.Title.String));
assert(contains(tX, 'UNRELIABLE'), 'Invalid latency title lacks verdict: %s', tX);
assert(mon.AxTransfer.Title.Color(1) > 0.5 && mon.AxTransfer.Title.Color(2) == 0, ...
    'Invalid latency title should be red');
fprintf('PASS: latency captions and verdict color\n');

%% 5. Swapping views clears the two-line subtitle it would otherwise inherit.
mon.show_calibration(stimgen.calibration.Engine());   % fresh engine: no data
assert_caption(mon.AxTransfer, 'Calibration transfer curves  (no data)', '');
fprintf('PASS: subtitle cleared on view swap\n');

delete(mon);

%% 5b. Five axes: each view keeps its own panel.
% The property the tabs rest on. Drawn in turn, all three must still be on
% screen together at the end -- with three axes the same sequence leaves
% only the last one.
fig = figure(Visible='off');
axes5 = gobjects(1, 5);
for k = 1:5
    axes5(k) = axes(fig, Position=[0.05 0.05 0.9 0.9]);
end
sep = stimgen.calibration.LiveMonitor(eng, Axes=axes5);
assert(~isequal(sep.AxBackground, sep.AxTransfer), 'Background axes not separate');
assert(~isequal(sep.AxLatency, sep.AxTransfer), 'Latency axes not separate');

eng.measure_background(0.25, 1);
sep.show_calibration(eng);
sep.show_background(eng);
sep.show_latency(fake_latency_(true));

assert(nlines(sep.AxTransfer) > 0, 'Transfer panel lost its curves');
assert(nlines(sep.AxBackground) > 0, 'Background panel lost its curves');
assert(nlines(sep.AxLatency) > 0, 'Latency panel lost its curves');
assert(contains(char(string(sep.AxTransfer.Title.String)), 'transfer curves'), ...
    'Transfer panel caption was overwritten');
assert(contains(char(string(sep.AxBackground.Title.String)), 'Background'), ...
    'Background panel caption was overwritten');
assert(contains(char(string(sep.AxLatency.Title.String)), 'Conduction delay'), ...
    'Latency panel caption was overwritten');
fprintf('PASS: five axes keep three measurements on screen at once\n');

% An unmeasured probe says so rather than sitting blank.
sep.show_latency([]);
assert(contains(char(string(sep.AxLatency.Title.String)), '(not measured)'), ...
    'Empty latency panel lacks its placeholder');
assert(nlines(sep.AxTransfer) > 0, 'Latency placeholder cleared the transfer panel');
fprintf('PASS: latency placeholder, and it clears only its own panel\n');
delete(sep);

% Three axes: still the shared panel, each view clearing the last.
shared = stimgen.calibration.LiveMonitor(eng, Axes=axes5(1:3));
shared.show_calibration(eng);
nAfterCal = nlines(shared.AxTransfer);
shared.show_background(eng);
assert(nAfterCal > 0, 'Shared transfer panel drew nothing to begin with');
assert(contains(char(string(shared.AxTransfer.Title.String)), 'Background'), ...
    'Shared panel did not switch to the background view');
fprintf('PASS: three axes still share one panel\n');
delete(shared);
delete(fig);

%% 5c. Waveform decimation: on by default, off on request.
% The envelope must keep every block's peak -- that is what lets a clipped or
% transient record still read correctly at a fraction of the points. Driven
% with a payload built by hand rather than a measurement, so the record has a
% known one-sample spike in it.
mon2 = stimgen.calibration.LiveMonitor();
assert(mon2.DecimateWaveforms, 'Waveform decimation should default to on');
mon2.MaxPoints = 500;

fsL = 44100;
yL = 0.1 * sin(2*pi*300*(0:fsL-1)/fsL);
yL(12345) = 0.97;                       % the peak the envelope must keep
payload = stimgen.calibration.LiveUpdate("manual", "done", Fs=fsL, ...
    Response=yL, Excitation=yL);

mon2.update(payload);
hResp = findobj(mon2.AxSignal, 'Type', 'line', 'DisplayName', 'response');
nDec = numel(hResp.XData);
assert(nDec <= 2 * mon2.MaxPoints + 4, ...
    'Decimated trace has %d points, expected <= %d', nDec, 2*mon2.MaxPoints+4);
assert(abs(max(hResp.YData) - 0.97) < 1e-9, ...
    'Envelope lost the record peak (max %.4f)', max(hResp.YData));

mon2.DecimateWaveforms = false;
mon2.update(payload);
hResp = findobj(mon2.AxSignal, 'Type', 'line', 'DisplayName', 'response');
assert(numel(hResp.XData) == numel(yL), ...
    'Full-resolution trace has %d points, expected %d', numel(hResp.XData), numel(yL));
fprintf('PASS: decimation defaults on (%d pts, peak kept), off gives all %d\n', ...
    nDec, numel(yL));
delete(mon2);

%% 5d. The GUI exposes it and the menu drives the monitor.
% The window is deleted rather than closed, so nothing here writes the
% StimCalibrationGui preferences -- which is also why the default is only
% asserted on a machine that has not stored a choice.
storedRes = ispref('StimCalibrationGui', 'decimateWaveforms');
guiD = stimgen.calibration.CalibrationGui(stimgen.calibration.Engine());
figD = findall(groot, 'Type', 'figure', 'Name', 'Stim Calibration');
mRes = findall(figD, 'Type', 'uimenu', 'Text', 'Full-Resolution Waveforms');
assert(isscalar(mRes), 'Full-Resolution Waveforms menu item missing');
if ~storedRes
    assert(guiD.Monitor.DecimateWaveforms, 'GUI should start decimated');
    assert(strcmp(mRes.Checked, 'off'), 'Menu item should start unchecked');
end

was = guiD.Monitor.DecimateWaveforms;
mRes.MenuSelectedFcn([], []);
assert(guiD.Monitor.DecimateWaveforms == ~was, 'Menu did not reach the monitor');
assert(strcmp(mRes.Checked, 'on') == ~guiD.Monitor.DecimateWaveforms, ...
    'Menu check state disagrees with the monitor');
mRes.MenuSelectedFcn([], []);
assert(guiD.Monitor.DecimateWaveforms == was, 'Menu did not toggle back');
fprintf('PASS: GUI waveform-resolution menu item\n');
delete(guiD);
delete(figD);

%% 6. Camera toolbar icon renders.
icon = stimgen.util.toolbar_icon('camera');
assert(isequal(size(icon), [24 24 3]) && any(~isnan(icon(:))), ...
    'camera icon empty or wrong size');
fprintf('PASS: camera toolbar icon\n');

%% 7. CalibrationGui: capture menu items and toolbar button exist.
gui = stimgen.calibration.CalibrationGui(eng);
fig = findall(groot, 'Type', 'figure', 'Name', 'Stim Calibration');
assert(isscalar(fig), 'Expected exactly one Stim Calibration window');

mShot = findall(fig, 'Type', 'uimenu', 'Text', 'Save Screenshot...');
mCopy = findall(fig, 'Type', 'uimenu', 'Text', 'Copy Window to Clipboard');
assert(isscalar(mShot), 'Save Screenshot... menu item missing');
assert(isscalar(mCopy), 'Copy Window to Clipboard menu item missing');

tools = findall(fig, 'Type', 'uipushtool');
tips = arrayfun(@(h) string(h.Tooltip), tools);
assert(any(contains(tips, 'Copy the entire window')), ...
    'camera toolbar button missing (by tooltip)');
fprintf('PASS: capture menu items and toolbar button present\n');

%% 7b. The plot tabs, and the controls they made obsolete.
tg = findall(fig, 'Type', 'uitabgroup');
assert(isscalar(tg), 'Expected exactly one plots tab group');
titles = arrayfun(@(t) string(t.Title), tg.Children);
assert(isequal(titles(:).', ["Tones", "Clicks", "Swept Sine", "Filter Test", ...
    "Background Noise", "Conduction Delay"]), ...
    'Unexpected tab set: %s', strjoin(titles, ', '));

% Every tab owns its own axes, and the monitor was handed all of them.
assert(numel(unique([gui.Monitor.AxTone, gui.Monitor.AxClick, ...
    gui.Monitor.AxSweptSine, gui.Monitor.AxFilterTest, ...
    gui.Monitor.AxBackground, gui.Monitor.AxLatency])) == 6, ...
    'Tabs are not on separate axes');

% The two view-selecting toolbar buttons are gone; the three overlay
% toggles remain.
toggles = findall(fig, 'Type', 'uitoggletool');
assert(numel(toggles) == 3, 'Expected 3 toggle tools, found %d', numel(toggles));
ttips = arrayfun(@(h) string(h.Tooltip), toggles);
assert(~any(contains(ttips, 'lookup tables overlaid')), ...
    'Transfer-view toolbar button still present');
assert(~any(contains(ttips, 'Show background noise')), ...
    'Background-view toolbar button still present');

% ... and so are the three View-menu items they mirrored.
for txt = ["Calibration Transfer Curves", "Background Noise Analysis", ...
        "Conduction Delay Probe"]
    assert(isempty(findall(fig, 'Type', 'uimenu', 'Text', char(txt))), ...
        'Obsolete View menu item still present: %s', txt);
end
fprintf('PASS: plot tabs; obsolete view buttons and menu items removed\n');

%% 7c. Every measurement coexists in the GUI, and the tabs switch between them.
gui.Monitor.show_calibration(eng);
gui.Monitor.show_background(eng);
gui.Monitor.show_latency(fake_latency_(true));
assert(nlines(gui.Monitor.AxTone) > 0 && nlines(gui.Monitor.AxBackground) > 0 ...
    && nlines(gui.Monitor.AxLatency) > 0, ...
    'A GUI panel was cleared by another panel being drawn');

tg.SelectedTab = tg.Children(5);
assert(isequal(tg.SelectedTab.Title, 'Background Noise'), 'Tab selection failed');
assert(nlines(gui.Monitor.AxTone) > 0, 'Switching tabs disturbed another panel');
tg.SelectedTab = tg.Children(1);
fprintf('PASS: GUI keeps every measurement across tab switches\n');

%% 8. The screenshot capture itself (exportapp path, minus the dialog).
shot = fullfile(tempdir, 'smoke_calibration_captions.png');
if isfile(shot), delete(shot); end
exportapp(fig, shot);
assert(isfile(shot), 'exportapp produced no file');
d = dir(shot);
assert(d.bytes > 10e3, 'Screenshot suspiciously small: %d bytes', d.bytes);
fprintf('PASS: exportapp screenshot (%d KB) at %s\n', round(d.bytes/1024), shot);

%% 9. Copy Window to Clipboard, end to end (overwrites the clipboard).
mCopy.MenuSelectedFcn([], []);
labels = findall(fig, 'Type', 'uilabel');
texts = arrayfun(@(h) string(h.Text), labels);
assert(any(contains(texts, 'copied to the clipboard')), ...
    'Status line does not report the clipboard copy: %s', ...
    strjoin(texts, ' | '));
fprintf('PASS: Copy Window to Clipboard\n');

delete(gui);
fprintf('\nAll calibration caption/capture smoke tests passed\n');
end

% ------------------------------------------------------------------------ %
function assert_caption(ax, wantTitle, wantSubtitle)
t = char(string(ax.Title.String));
s = join_lines(ax.Subtitle.String);
assert(strcmp(t, wantTitle), 'Title "%s", expected "%s"', t, wantTitle);
assert(strcmp(s, wantSubtitle), 'Subtitle "%s", expected "%s"', s, wantSubtitle);
end

% ------------------------------------------------------------------------ %
function n = nlines(ax)
% Lines currently drawn on an axes -- the cheap proxy for "this panel still
% holds its measurement".
n = numel(findobj(ax, 'Type', 'line'));
end

% ------------------------------------------------------------------------ %
function s = join_lines(v)
% Title/Subtitle String may be char, string, or cellstr (two-line captions).
if iscell(v)
    s = char(strjoin(string(v), '  //  '));
else
    s = char(string(v));
end
end

% ------------------------------------------------------------------------ %
function lat = fake_latency_(valid)
% Minimal diagnostics struct render_latency_ consumes; shaped like the
% payload click_latency_ builds.
fs = 44100;
lagMs = linspace(-2, 50, 800);
corr = exp(-((lagMs - 4.17) / 0.3).^2);
lat = struct( ...
    'valid', valid, ...
    'at_bound', ~valid, ...
    'delay_ms', 4.170, ...
    'bound_ms', 50, ...
    'lag_ms', lagMs, ...
    'corr', corr, ...
    'probe_v', 0.01 .* randn(1, 512), ...
    'fs', fs, ...
    'probe_lag0_ms', -2, ...
    'peak_v', 0.05, ...
    'noise_v', 2e-4, ...
    'path_m', 1.43, ...
    'speed_of_sound_ms', 343.2, ...
    'temperature_c', 22.2);
if ~valid
    lat.delay_ms = NaN;
end
end
