function smoke_test_click_verification
% Headless smoke test for Engine.test_clicks and the CalibrationGui
% Test Clicks button, against the FakeSpeakerAdapter simulated rig.
% Also pins the verification section's labels: the filter button reads
% "Test Filter", not "Test Calibration".
%
%   matlab -batch "run('tmp/smoke_test_click_verification.m')"

repoRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(repoRoot, 'obj', 'stimgen'));
addpath(fileparts(mfilename('fullpath')));

global GVerbosity %#ok<GVMIS>
GVerbosity = 1;

%% 1. Lint the touched files
sg = fullfile(repoRoot, 'obj', 'stimgen', '+stimgen');
files = { ...
    fullfile(sg, '+calibration', '@Engine', 'test_clicks.m'), ...
    fullfile(sg, '+calibration', '@Engine', 'Engine.m'), ...
    fullfile(sg, '+calibration', '@LiveMonitor', 'LiveMonitor.m'), ...
    fullfile(sg, '@StimCalibration', 'StimCalibration.m'), ...
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

%% 2. Guards: no adapter, no click calibration
engOffline = stimgen.calibration.Engine();
try
    engOffline.test_clicks();
    error('smoke:noAdapterGuard', 'test_clicks did not refuse without an adapter');
catch ME
    assert(strcmp(ME.identifier, 'stimgen:calibration:Engine:noAdapter'), ...
        'unexpected error: %s / %s', ME.identifier, ME.message);
end

adapter = FakeSpeakerAdapter(44100);
eng = stimgen.calibration.Engine(adapter);
eng.set_configuration(MicSensitivity=0.01, ExcitationVoltage=1);
try
    eng.test_clicks();
    error('smoke:noClickGuard', 'test_clicks did not refuse without a click table');
catch ME
    assert(strcmp(ME.identifier, 'stimgen:calibration:Engine:missingTypeCalibration'), ...
        'unexpected error: %s / %s', ME.identifier, ME.message);
end
fprintf('PASS guards\n');

%% 3. Engine.test_clicks end-to-end against a simulated speaker
durs = [20 40 80 160 320] .* 1e-6;
eng.calibrate_clicks(durs, 1);
assert(~isempty(eng.CalibrationData.click), 'click calibration produced no table');

r = eng.test_clicks([], [], RepeatCount=1);

fprintf('durations %s us | worst %.2f dB | bias %+.2f dB | rms %.2f dB | passed=%d\n', ...
    mat2str(round(r.duration(:).' * 1e6, 1)), r.max_abs_error_db, r.bias_db, ...
    r.rms_error_db, r.passed);

% Defaults probe between the calibrated points, never on them.
assert(numel(r.duration) == numel(durs) - 1, ...
    'expected %d midpoints, got %d', numel(durs)-1, numel(r.duration));
assert(~any(ismembertol(r.duration(:).', durs, 1e-9)), ...
    'default test durations landed on the LUT knots');
assert(isequal(size(r.error_db), [numel(r.duration) numel(r.level_db)]), ...
    'error_db is not duration-by-level');
assert(any(r.reliable(:)), 'no point survived the SNR floor on a simulated rig');
assert(isfield(eng.CalibrationData, 'clickTest'), 'clickTest not stored');
assert(r.passed == (r.max_abs_error_db <= r.tolerance_db));
fprintf('PASS engine test_clicks\n');

%% 3b. On the LUT's own durations the level model must be near-exact
% The midpoint run above measures interpolation error, which is real and
% duration-dependent even on a linear rig. Re-testing the calibrated
% durations takes the interpolant out of it: what is left is the drive
% voltage model alone, and on this rig that has to be tight.
rk = eng.test_clicks(durs, eng.NormativeValue, RepeatCount=1);
assert(all(rk.reliable), 'a calibrated duration failed the SNR floor at the normative level');
assert(rk.max_abs_error_db < 0.5, ...
    'level model off by %.2f dB at the LUT''s own durations', rk.max_abs_error_db);
fprintf('PASS level model at LUT knots (worst %.3f dB)\n', rk.max_abs_error_db);

%% 4. Explicit grid, unreachable points, and unresolvable durations
% A level far above what the 10 V ceiling can drive must be reported as
% skipped rather than silently dropped, and a sub-sample duration dropped
% with a message rather than an error.
r2 = eng.test_clicks([0.1e-6 40e-6 120e-6], [eng.NormativeValue 200], RepeatCount=1);
assert(~any(abs(r2.duration - 0.1e-6) < 1e-12), ...
    'sub-sample duration was not dropped at 44.1 kHz');
assert(numel(r2.skipped.duration) > 0, '200 dB SPL was not reported as unreachable');
assert(all(r2.skipped.level_db == 200), 'a reachable point was skipped');
assert(all(r2.tested(:, 1)), 'the reachable level was not measured');
fprintf('PASS grid handling\n');

%% 4b. Live rendering of the "click_test" stage
% A monitor that cannot render the new stage suspends live plotting and says
% so in the log rather than throwing, so the log is what has to be checked.
captured = strings(0);
stimgen.util.logSink(stimgen.FcnLogSink(@(~,~,msg,~) collect(msg)));
mon = stimgen.calibration.LiveMonitor(eng);
cleanupMon = onCleanup(@() delete(mon));
eng.set_configuration(ShowLivePlots=true);
eng.test_clicks(durs(2:3), eng.NormativeValue, RepeatCount=1);
eng.set_configuration(ShowLivePlots=false);
stimgen.util.logSink([]);

bad = captured(contains(captured, ["render failed", "listener failed"], IgnoreCase=true));
assert(isempty(bad), 'live plotting failed on the click_test stage: %s', strjoin(bad, ' | '));
assert(isvalid(mon), 'monitor did not survive the run');
clear cleanupMon
fprintf('PASS live plotting\n');

%% 5. StimCalibration proxies test_clicks
sc = stimgen.StimCalibration(adapter);
sc.Engine.restore(struct( ...
    'CalibrationData',      eng.CalibrationData, ...
    'MicSensitivity',       eng.MicSensitivity, ...
    'NormativeValue',       eng.NormativeValue, ...
    'ReferenceLevel',       eng.ReferenceLevel, ...
    'ReferenceFrequency',   eng.ReferenceFrequency, ...
    'ExcitationVoltage',    eng.ExcitationVoltage, ...
    'CalibrationTimestamp', eng.CalibrationTimestamp));

r3 = sc.test_clicks([], [], RepeatCount=1);
assert(isstruct(r3) && isfield(r3, 'passed'), 'proxy did not return a result');
assert(isfield(sc.Engine.CalibrationData, 'clickTest'), 'proxy run did not store clickTest');
delete(sc);
fprintf('PASS StimCalibration proxy\n');

%% 6. CalibrationGui: labels and enable rules
% Offline: no adapter, no click table -> Test Clicks must be disabled.
cg1 = stimgen.calibration.CalibrationGui();
assert(isvalid(cg1));
b = find_btn('Test Clicks');
assert(strcmp(b.Enable, 'off'), 'Test Clicks enabled with no click table/adapter');
assert(isempty(findall(groot, 'Type', 'uibutton', 'Text', 'Test Calibration')), ...
    'the old "Test Calibration" label is still on screen');
f = find_btn('Test Filter');
assert(strcmp(f.Enable, 'off'), 'Test Filter enabled with no filter/adapter');
assert(~isempty(b.Tooltip), 'Test Clicks has no tooltip');
delete(ancestor(b, 'figure'));

% Click table plus adapter -> enabled. The button itself opens a modal
% parameter dialog, so what can be checked headlessly is that it is offered.
cg2 = stimgen.calibration.CalibrationGui(eng);
assert(isvalid(cg2));
b = find_btn('Test Clicks');
assert(strcmp(b.Enable, 'on'), 'Test Clicks not enabled despite click table + adapter');
delete(ancestor(b, 'figure'));
fprintf('PASS CalibrationGui labels and enable rules\n');

fprintf('ALL PASS\n');

    function collect(msg)
        % Nested so the sink writes into this function's captured list.
        % vprintf accepts an MException as the whole message, so the sink has
        % to as well.
        if isa(msg, 'MException')
            captured(end+1) = string(msg.message);
        else
            captured(end+1) = string(msg);
        end
    end
end

function b = find_btn(labelText)
b = findall(groot, 'Type', 'uibutton', 'Text', labelText);
assert(isscalar(b), 'expected exactly one "%s" button, found %d', labelText, numel(b));
end
