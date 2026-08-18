function smoke_test_calibration_stimulus_tabs()
% smoke_test_calibration_stimulus_tabs()
% Verify the CalibrationGui's per-stimulus plot tabs and the LiveMonitor
% panels behind them.
%
% What this covers, and why each part is worth a test:
%
%   1. The Axes struct form. A panel per stimulus is what the tabs rest on,
%      and the shared form has to keep working -- the monitor's own window
%      and every three-axes host still overlay the tables on one panel.
%   2. Routing. A run's live updates must land on its own stimulus's panel,
%      and a table's verification on the panel of the table it verifies. Get
%      this wrong and the operator watches an empty panel while the curve
%      fills in behind another tab.
%   3. Isolation. Committing one stimulus's table must not disturb another's
%      panel, which is the whole reason for the split.
%   4. The detail axes: drawn from the committed table, captioned as not
%      measured until there is one, and never claiming a figure the table
%      does not carry (a click sweep has no per-harmonic numbers).
%
% Run under the MATLAB MCP server or matlab -batch:
%
%   matlab -batch "cd('tmp'); smoke_test_calibration_stimulus_tabs"

thisDir = fileparts(mfilename('fullpath'));
run(fullfile(thisDir, '..', 'epsych_startup.m'));
addpath(thisDir);   % FakeSpeakerAdapter lives beside this file

cleanupObj = onCleanup(@() delete(findall(groot, 'Type', 'figure')));

%% 1. Panel wiring: a struct gives each stimulus its own axes.
fig = figure(Visible='off');
ax = gobjects(1, 13);
for k = 1:numel(ax)
    ax(k) = axes(fig, Position=[0.05 0.05 0.9 0.9]);
end
eng = stimgen.calibration.Engine();
mon = stimgen.calibration.LiveMonitor(eng, Axes=struct( ...
    'signal', ax(1), 'spectrum', ax(2), ...
    'tone', ax(3), 'tone_detail', ax(4), ...
    'click', ax(5), 'click_detail', ax(6), ...
    'swept_sine', ax(7), 'swept_detail', ax(8), 'swept_impulse', ax(9), ...
    'filter_test', ax(10), 'filter_detail', ax(11), ...
    'background', ax(12), 'latency', ax(13)));

assert(~isequal(mon.AxTone, mon.AxClick), 'Tone and click share an axes');
assert(~isequal(mon.AxTone, mon.AxSweptSine), 'Tone and swept sine share an axes');
assert(~isequal(mon.AxTone, mon.AxFilterTest), 'Tone and filter test share an axes');
assert(isequal(mon.AxToneDetail, ax(4)), 'Tone detail axes not taken from the struct');
assert(isequal(mon.AxFilterDetail, ax(11)), 'Filter detail axes not taken from the struct');
fprintf('PASS: struct axes give each stimulus its own panel\n');

% The shared forms still share, which is what show_calibration branches on.
% The filter test shares with them, which is what its own panel is a
% departure from -- a host that names no panel for it must still be able to
% run one.
shared = stimgen.calibration.LiveMonitor(eng, Axes=ax(1:3));
assert(isequal(shared.AxTone, shared.AxClick) && ...
    isequal(shared.AxTone, shared.AxSweptSine) && ...
    isequal(shared.AxTone, shared.AxFilterTest), ...
    'Three-axes form no longer shares one sweep panel');
delete(shared);

% ... and so does the monitor's own window, which is the form a headless
% caller gets and the one most likely to be forgotten when a panel is added.
own = stimgen.calibration.LiveMonitor();
assert(~isempty(own.AxFilterTest) && isequal(own.AxFilterTest, own.AxTransfer), ...
    'The monitor own-figure form has no filter test panel');
delete(own);
fprintf('PASS: three-axes form still shares one sweep panel\n');

%% 2. Empty panels say so, one per stimulus.
mon.show_calibration(eng);
assert_title(mon.AxTone,       'Tone calibration  (not measured)');
assert_title(mon.AxClick,      'Click calibration  (not measured)');
assert_title(mon.AxSweptSine,  'Swept sine calibration  (not measured)');
assert_title(mon.AxToneDetail, 'Tone distortion & SNR  (not measured)');
assert_title(mon.AxSweptImpulse, 'Impulse response  (not measured)');
fprintf('PASS: unmeasured stimulus panels carry their own placeholder\n');

%% 3. A real tone sweep fills the tone panel and leaves the others alone.
eng.set_adapter(FakeSpeakerAdapter(44100));
eng.set_configuration(ShowLivePlots=true, ReferenceLevel=94, ...
    MicSensitivity=0.01, NormativeValue=80);
mon.MinInterval = 0;

eng.calibrate_tones([1000 2000 4000]);
assert(nlines(mon.AxTone) > 0, 'Tone sweep drew nothing on the tone panel');
assert(nlines(mon.AxClick) == 0, 'Tone sweep drew on the click panel');
assert(nlines(mon.AxSweptSine) == 0, 'Tone sweep drew on the swept sine panel');
fprintf('PASS: a tone sweep draws only on the tone panel\n');

mon.show_calibration(eng);
assert(contains(title_(mon.AxTone), 'Tone calibration'), ...
    'Committed tone table missing from the tone panel');
assert(nlines(mon.AxToneDetail) > 0, 'Tone detail axes stayed empty');
assert(contains(title_(mon.AxToneDetail), 'distortion'), ...
    'Tone detail caption wrong: %s', title_(mon.AxToneDetail));
% The click panel still says it has no table, rather than inheriting the
% tone panel's caption -- the failure the shared panel used to have.
assert(contains(title_(mon.AxClick), '(not measured)'), ...
    'Click panel changed when the tone table was committed');
fprintf('PASS: committing a tone table leaves the other stimulus panels alone\n');

%% 4. A click sweep goes to the click panel, tone table still standing.
nToneBefore = nlines(mon.AxTone);
eng.calibrate_clicks([1e-4 2e-4 4e-4]);
assert(nlines(mon.AxClick) > 0, 'Click sweep drew nothing on the click panel');
assert(nlines(mon.AxTone) == nToneBefore, ...
    'Click sweep disturbed the tone panel');

mon.show_calibration(eng);
assert(nlines(mon.AxClick) > 0 && nlines(mon.AxTone) > 0, ...
    'Both tables should be on screen at once');
% A click sweep measures no per-harmonic figures; the detail panel must draw
% what it has rather than flat zeros standing in for them.
names = line_names(mon.AxClickDetail);
assert(any(names == "SNR"), 'Click detail axes lost the SNR trace');
assert(~any(names == "2nd harmonic"), ...
    'Click detail axes invented a harmonic trace: %s', strjoin(names, ', '));
fprintf('PASS: click sweep panel and its detail axes\n');

%% 4b. The filter test draws on its own panel, not over the tone table.
% The reason the panel exists: the test measures the rig twice and the
% verdict is the difference, which cannot be read off a panel that already
% holds a lookup table -- and used to be read off the tone panel, where one
% of the two curves was always about to be overwritten.
mon.show_filter_test(eng);
assert(contains(title_(mon.AxFilterTest), '(not run)'), ...
    'Untested filter panel should say so: %s', title_(mon.AxFilterTest));

nToneBefore = nlines(mon.AxTone);
eng.design_filter("tone", ShowResponse=false);
r = eng.test_filter(Duration=0.2, TailDuration=0.05, RepeatCount=1, ...
    NumPoints=8, RippleToleranceDb=60);
assert(nlines(mon.AxFilterTest) > 0, 'Filter test drew nothing on its own panel');
assert(nlines(mon.AxTone) == nToneBefore, 'Filter test disturbed the tone panel');
assert(contains(title_(mon.AxTone), 'Tone calibration'), ...
    'Filter test overwrote the tone panel caption: %s', title_(mon.AxTone));
fprintf('PASS: a filter test draws only on the filter test panel\n');

% Both conditions survive the run, which is what the live sweep alone could
% not do -- it draws one table and then the other over it.
mon.show_filter_test(eng);
names = line_names(mon.AxFilterTest);
assert(any(names == "speaker alone") && any(names == "through filter"), ...
    'Filter test panel is missing a condition: %s', strjoin(names, ', '));
assert(contains(title_(mon.AxFilterTest), 'Filter test'), ...
    'Filter test caption wrong: %s', title_(mon.AxFilterTest));
devNames = line_names(mon.AxFilterDetail);
assert(any(devNames == "speaker alone") && any(devNames == "through filter"), ...
    'Filter detail axes is missing a condition: %s', strjoin(devNames, ', '));
assert(r.passed == contains(title_(mon.AxFilterTest), 'passed'), ...
    'Panel verdict disagrees with the result');
fprintf('PASS: both filter test conditions are drawn, with the verdict\n');

% Redrawing the tables must leave it standing -- the failure a shared panel
% had in the other direction.
mon.show_calibration(eng);
assert(nlines(mon.AxFilterTest) > 0, ...
    'Redrawing the lookup tables wiped the filter test panel');
fprintf('PASS: the filter test survives a redraw of the lookup tables\n');

%% 5. The GUI: one tab per stimulus, each run focusing its own.
gui = stimgen.calibration.CalibrationGui(eng);
guiFig = findall(groot, 'Type', 'figure', 'Name', 'Stim Calibration');
tg = findall(guiFig, 'Type', 'uitabgroup');
titles = arrayfun(@(t) string(t.Title), tg.Children);
assert(isequal(titles(:).', ["Tones", "Clicks", "Swept Sine", "Filter Test", ...
    "Background Noise", "Conduction Delay"]), ...
    'Unexpected tab set: %s', strjoin(titles, ', '));

% The swept sine tab carries three plots, the other two carry two: the whole
% point of a panel per stimulus is that each shows what its own measurement
% produces.
assert(numel(findall(tg.Children(1), 'Type', 'axes')) == 2, 'Tones tab: expected 2 axes');
assert(numel(findall(tg.Children(2), 'Type', 'axes')) == 2, 'Clicks tab: expected 2 axes');
assert(numel(findall(tg.Children(3), 'Type', 'axes')) == 3, 'Swept Sine tab: expected 3 axes');
assert(numel(findall(tg.Children(4), 'Type', 'axes')) == 2, 'Filter Test tab: expected 2 axes');
fprintf('PASS: GUI tab set and per-tab axes counts\n');

% Every stimulus panel is drawn and stays drawn, whichever tab is on top:
% that is what the tabs buy and what a shared panel could not do.
gui.Monitor.show_calibration(eng);
for t = 1:3
    tg.SelectedTab = tg.Children(t);
    tg.SelectionChangedFcn(tg, struct('NewValue', tg.Children(t)));
end
assert(nlines(gui.Monitor.AxTone) > 0 && nlines(gui.Monitor.AxClick) > 0, ...
    'A stimulus panel lost its table when another tab was selected');
assert(contains(title_(gui.Monitor.AxSweptSine), '(not measured)'), ...
    'Swept sine panel should still say it has no table');
fprintf('PASS: tab switching leaves every stimulus panel standing\n');

%% 6. Stage routing agrees with what the GUI focuses.
% A tone LUT test belongs on the tone tab, a click LUT test on the click tab,
% and the filter test -- which verifies no table and draws two curves of one
% quantity -- on its own. If these ever disagree with focus_sweep_panel_'s
% arguments, a run is watched on the wrong tab.
want = { 'tone', 'tone'; 'tone_test', 'tone'; 'filter_test', 'filter_test'; ...
         'click', 'click'; 'click_test', 'click'; 'swept_sine', 'swept_sine' };
for i = 1:size(want, 1)
    got = stimgen.calibration.LiveMonitor.stage_panel(string(want{i,1}));
    assert(got == string(want{i,2}), ...
        'Stage %s routed to %s, expected %s', want{i,1}, got, want{i,2});
end
fprintf('PASS: every run stage routes to its stimulus panel\n');

delete(gui);
delete(guiFig);
delete(mon);
delete(fig);
fprintf('\nAll calibration stimulus-tab smoke tests passed\n');
end

% ------------------------------------------------------------------------ %
function assert_title(ax, want)
got = title_(ax);
assert(strcmp(got, want), 'Title "%s", expected "%s"', got, want);
end

% ------------------------------------------------------------------------ %
function s = title_(ax)
s = char(string(ax.Title.String));
end

% ------------------------------------------------------------------------ %
function n = nlines(ax)
n = numel(findobj(ax, 'Type', 'line'));
end

% ------------------------------------------------------------------------ %
function names = line_names(ax)
h = findobj(ax, 'Type', 'line');
if isempty(h)
    names = string.empty(1, 0);
    return
end
names = arrayfun(@(x) string(x.DisplayName), h(:)).';
end
