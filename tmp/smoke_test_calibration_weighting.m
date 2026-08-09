function smoke_test_calibration_weighting
% Headless smoke test for the frequency-weighting overlay on the calibration
% transfer panel: the weighting math itself, the three views that can carry
% the overlay (live sweep, committed LUTs, background analysis), and the
% CalibrationGui menu that drives it.
%
%   matlab -batch "run('tmp/smoke_test_calibration_weighting.m')"

repoRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(repoRoot, 'obj', 'stimgen'));
addpath(fileparts(mfilename('fullpath')));

global GVerbosity %#ok<GVMIS>
GVerbosity = 1;

cleanupObj = onCleanup(@() delete(findall(groot, 'Type', 'figure'))); %#ok<NASGU>

%% 1. Lint the touched files
sg = fullfile(repoRoot, 'obj', 'stimgen', '+stimgen');
files = { ...
    fullfile(sg, '+util', 'weighting_db.m'), ...
    fullfile(sg, '+calibration', '@LiveMonitor', 'LiveMonitor.m'), ...
    fullfile(sg, '+calibration', '@LiveMonitor', 'render_weighting_.m'), ...
    fullfile(sg, '+calibration', '@LiveMonitor', 'render_transfer_.m'), ...
    fullfile(sg, '+calibration', '@LiveMonitor', 'show_calibration.m'), ...
    fullfile(sg, '+calibration', '@LiveMonitor', 'show_background.m'), ...
    fullfile(sg, '+calibration', '@Engine', 'analyze_background_.m'), ...
    fullfile(sg, '+calibration', 'CalibrationGui.m')};
for k = 1:numel(files)
    msgs = checkcode(files{k}, '-severity');
    err = msgs([msgs.severity] >= 2);
    if ~isempty(err)
        for m = err(:)'
            fprintf(2, '%s:%d %s\n', files{k}, m.line, m.message);
        end
        error('smoke:lint', 'checkcode errors in %s', files{k});
    end
end
fprintf('PASS lint\n');

%% 2. Weighting values against the published tables
% IEC 61672-1 (A, C) and IEC 60651 (B, D), at nominal octave frequencies.
% Evaluating at nominal rather than exact base-10 frequencies costs ~0.15 dB,
% which is the tolerance below.
f = [10 20 31.5 63 125 250 500 1000 2000 4000 8000 16000];
expected = struct( ...
    'A', [-70.4 -50.4 -39.4 -26.2 -16.1  -8.6 -3.2 0  1.2  1.0 -1.1 -6.6], ...
    'B', [-38.2 -24.2 -17.1  -9.3  -4.2  -1.3 -0.3 0 -0.1 -0.7 -2.9 -8.4], ...
    'C', [-14.3  -6.2  -3.0  -0.8  -0.2   0.0  0.0 0 -0.2 -0.8 -3.0 -8.5], ...
    'D', [-26.6 -20.6 -16.6 -10.9  -5.5  -1.6 -0.3 0  7.9 11.1  5.5 -0.8]);
for t = ["A" "B" "C" "D"]
    err = max(abs(stimgen.util.weighting_db(f, t) - expected.(char(t))));
    assert(err < 0.15, '%s-weighting departs from the standard by %.2f dB', t, err);
    assert(stimgen.util.weighting_db(1000, t) == 0, ...
        '%s-weighting is not exactly 0 dB at 1 kHz', t);
end
assert(all(stimgen.util.weighting_db(f, "Z") == 0), 'Z-weighting is not flat');
assert(isequal(size(stimgen.util.weighting_db(rand(3, 4), "A")), [3 4]), ...
    'weighting_db did not preserve the shape of f');
assert(isfinite(stimgen.util.weighting_db(0, "A")), 'weighting_db returned -Inf at DC');
fprintf('PASS weighting values (A, B, C, D, Z)\n');

%% 3. Live sweep: overlay follows the measured curve as it fills in
adapter = MockCalibrationAdapter(48000);
eng = stimgen.calibration.Engine(adapter);
eng.set_configuration(MicSensitivity=0.01, ExcitationVoltage=1, ShowLivePlots=true);

fig = figure(Visible='off');
axs = [subplot(3,1,1) subplot(3,1,2) subplot(3,1,3)];
mon = stimgen.calibration.LiveMonitor(eng, Axes=axs);
mon.MinInterval = 0;          % every payload renders, so the last one is not skipped
mon.Weightings = ["A" "C"];

eng.calibrate_tones(logspace(log10(500), log10(16000), 8), 1, BurstDuration=0.02);
h = weighting_lines_(axs(3));
assert(numel(h) == 2, 'live sweep drew %d weighting curves, expected 2', numel(h));
fprintf('PASS live sweep overlay (%s)\n', strjoin(sort(string({h.DisplayName})), ', '));

%% 4. Committed LUTs, and the anchor the curve is placed by
mon.show_calibration(eng);
h = weighting_lines_(axs(3));
assert(numel(h) == 2, 'LUT view drew %d weighting curves, expected 2', numel(h));

L = eng.CalibrationData.tone;
hA = h(startsWith({h.DisplayName}, 'A-'));
fAnchor = min(max(1000, min(L.frequency)), max(L.frequency));
assert(abs(interp1(hA.XData, hA.YData, fAnchor) - interp1(L.frequency, L.spl_db, fAnchor)) < 1e-6, ...
    'A-weighting is not anchored to the measured level at %.0f Hz', fAnchor);

% The overlay must not rescale an axis the measurement owns: A-weighting runs
% to -50 dB at 20 Hz and would otherwise flatten the curve it annotates.
yl = ylim(axs(3));
assert(yl(1) > min(L.spl_db) - 15, ...
    'overlay stretched the y-axis to %.1f dB below the data', min(L.spl_db) - yl(1));

% Named in the legend, which is built with AutoUpdate off and so has to be
% rebuilt whenever the selection changes.
assert(nnz(contains(string(axs(3).Legend.String), 'weighting')) == 2, ...
    'legend does not name both weighting curves: %s', strjoin(string(axs(3).Legend.String), ' | '));
fprintf('PASS LUT view overlay, anchor, y-scale and legend\n');

%% 5. Selection changes take effect, including mid-run
mon.Weightings = "D";
mon.show_calibration(eng);
h = weighting_lines_(axs(3));
assert(numel(h) == 1 && startsWith(h.DisplayName, 'D-'), ...
    'narrowing the selection left %d curves', numel(h));
assert(nnz(contains(string(axs(3).Legend.String), 'weighting')) == 1, ...
    'legend still names a dropped weighting curve');

mon.Weightings = string.empty;
mon.show_calibration(eng);
assert(isempty(weighting_lines_(axs(3))), 'clearing the selection left a curve behind');

mon.Weightings = ["A" "A" "C"];
assert(isequal(mon.Weightings, ["A" "C"]), 'duplicate weightings were not collapsed');
try
    mon.Weightings = "Q";
    error('smoke:validation', 'an unknown weighting was accepted');
catch ME
    assert(strcmp(ME.identifier, 'MATLAB:validators:mustBeMember'), ...
        'unexpected identifier for a bad weighting: %s', ME.identifier);
end
fprintf('PASS selection add/remove/clear/validate\n');

%% 6. A duration axis carries no weighting
eng2 = stimgen.calibration.Engine();
eng2.restore(struct('CalibrationData', struct('click', struct( ...
    'duration', (10:10:200) * 1e-6, 'spl_db', 90 - (1:20), ...
    'voltage', 0.5 * ones(1, 20)))));
mon.Weightings = "A";
mon.show_calibration(eng2);
assert(isempty(weighting_lines_(axs(3))), ...
    'a click-only LUT drew a weighting curve against duration');
fprintf('PASS click-only LUT suppresses the overlay\n');

%% 7. Background analysis carries it too, and dB(A) still agrees
% No calibrate_reference: the mock records noise, not a calibrator tone, and
% measure_background reads levels on whatever MicSensitivity is already set.
eng.measure_background(0.2, 2);
mon.Weightings = "A";
mon.show_background(eng);
assert(numel(weighting_lines_(axs(3))) == 1, 'background view drew no weighting curve');

B = eng.CalibrationData.background;
assert(max(abs(B.bands.level_dba - (B.bands.level_db + ...
    stimgen.util.weighting_db(B.bands.frequency, "A")))) < 1e-9, ...
    'band dB(A) no longer matches the shared weighting function');
fprintf('PASS background overlay and dB(A) agreement\n');

delete(mon);
delete(fig);

%% 8. The GUI menu drives it
gui = stimgen.calibration.CalibrationGui(eng);
menus = findall(groot, 'Type', 'uimenu', '-regexp', 'Text', '-weighting$');
assert(numel(menus) == 4, 'expected 4 weighting menu items, found %d', numel(menus));

aMenu = menus(strcmp({menus.Text}, 'A-weighting'));
aMenu.MenuSelectedFcn(aMenu, []);
assert(isequal(gui.Monitor.Weightings, "A"), ...
    'checking A-weighting did not reach the monitor (%s)', strjoin(gui.Monitor.Weightings, ','));
assert(strcmp(aMenu.Checked, 'on'), 'the menu item did not check itself');

aMenu.MenuSelectedFcn(aMenu, []);
assert(isempty(gui.Monitor.Weightings), 'unchecking A-weighting did not reach the monitor');
assert(strcmp(aMenu.Checked, 'off'), 'the menu item did not uncheck itself');
fprintf('PASS CalibrationGui weighting menu\n');

delete(gui);
fprintf('\nAll calibration weighting smoke tests passed\n');
end

% ------------------------------------------------------------------------ %
function h = weighting_lines_(ax)
% Every overlay curve on an axes, identified the way a reader would: by the
% legend entry it carries.
h = findobj(ax, 'Type', 'line', '-regexp', 'DisplayName', '-weighting');
end
