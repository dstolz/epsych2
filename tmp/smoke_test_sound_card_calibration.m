function report = smoke_test_sound_card_calibration()
% report = smoke_test_sound_card_calibration()
% Smoke-test suite for Windows sound card calibration support.
%
% Tests the following without hardware (mock adapter) and optionally with
% a real audio device when MATLAB Audio Toolbox can open the default device.
%
% Sections:
%   1)  SweptSine signal generation (log-sine chirp)
%   2)  SweptSine signal generation (linear chirp)
%   3)  SweptSine: f1 >= f2 error path
%   4)  Engine construction (offline, no adapter)
%   5)  Engine construction (with mock adapter)
%   6)  Engine.calibrate_swept_sine with mock adapter
%   7)  Engine.calibrate_tones with mock adapter
%   8)  Engine.calibrate_reference with mock adapter
%   9)  Engine: compute_adjusted_voltage (tone, offline)
%  10)  Engine: compute_adjusted_voltage (swept_sine, offline)
%  11)  apply_calibration routes swept_sine via geometric mean value
%  12)  WindowsSoundCardAdapter construction (hardware — skipped if unavailable)
%  13)  WindowsSoundCardAdapter.sample_rate consistency (hardware)
%  14)  WindowsSoundCardAdapter.play_and_record length contract (hardware)
%
% Returns:
%   report - struct with .allPassed, .timestamp, .steps fields

report = struct();
report.timestamp = datetime('now');
report.allPassed = false;
report.steps = struct();

fprintf('=== smoke_test_sound_card_calibration ===\n');

% ------------------------------------------------------------------ %
% Helper
% ------------------------------------------------------------------ %
function record(stepName, passed, detail)
    status = 'PASS';
    if ~passed, status = 'FAIL'; end
    fprintf('  [%s] %s\n', status, stepName);
    if ~passed, fprintf('       %s\n', detail); end
    report.steps.(stepName) = struct('passed', passed, 'detail', detail);
end

% ------------------------------------------------------------------ %
% 1) SweptSine: log-sine signal generation
% ------------------------------------------------------------------ %
stepName = 'sweptSineLogSineGeneration';
try
    ss = stimgen.SweptSine();
    ss.Fs = 48000;
    ss.Duration = 0.5;
    ss.StartFrequency = 100;
    ss.StopFrequency = 20000;
    ss.ChirpType = "log-sine";
    ss.ApplyCalibration = false;
    ss.ApplyWindow = false;
    ss.update_signal();

    expectedN = round(ss.Fs * ss.Duration);
    assert(numel(ss.Signal) == expectedN, ...
        'Signal length mismatch: got %d, expected %d.', numel(ss.Signal), expectedN);
    assert(all(isfinite(ss.Signal)), 'Signal contains non-finite values.');
    assert(max(abs(ss.Signal)) > 0, 'Signal is all zeros.');

    record(stepName, true, sprintf('Signal length=%d, peak=%.4f', numel(ss.Signal), max(abs(ss.Signal))));
catch ME
    record(stepName, false, getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% ------------------------------------------------------------------ %
% 2) SweptSine: linear chirp generation
% ------------------------------------------------------------------ %
stepName = 'sweptSineLinearGeneration';
try
    ss = stimgen.SweptSine();
    ss.Fs = 48000;
    ss.Duration = 0.25;
    ss.StartFrequency = 200;
    ss.StopFrequency = 8000;
    ss.ChirpType = "linear";
    ss.ApplyCalibration = false;
    ss.ApplyWindow = false;
    ss.update_signal();

    assert(numel(ss.Signal) == round(ss.Fs * ss.Duration), 'Linear chirp length mismatch.');
    assert(all(isfinite(ss.Signal)), 'Linear chirp contains non-finite values.');

    record(stepName, true, sprintf('Linear chirp length=%d', numel(ss.Signal)));
catch ME
    record(stepName, false, getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% ------------------------------------------------------------------ %
% 3) SweptSine: f1 >= f2 error path
% ------------------------------------------------------------------ %
stepName = 'sweptSineBadFreqRange';
try
    ss = stimgen.SweptSine();
    ss.Fs = 48000;
    ss.Duration = 0.5;
    ss.StartFrequency = 8000;
    ss.StopFrequency = 1000;
    ss.ApplyCalibration = false;
    ss.ApplyWindow = false;

    threwExpected = false;
    try
        ss.update_signal();
    catch ME2
        threwExpected = strcmp(ME2.identifier, 'stimgen:SweptSine:badFreqRange');
    end
    assert(threwExpected, 'Expected stimgen:SweptSine:badFreqRange but no error thrown.');
    record(stepName, true, 'Correctly threw stimgen:SweptSine:badFreqRange.');
catch ME
    record(stepName, false, getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% ------------------------------------------------------------------ %
% 4) Engine: offline construction (no adapter)
% ------------------------------------------------------------------ %
stepName = 'engineOfflineConstruction';
try
    eng = stimgen.calibration.Engine();
    assert(isempty(eng.Adapter), 'Expected Adapter to be empty.');
    assert(eng.Fs == 0, 'Expected Fs==0 with no adapter.');
    assert(~eng.IsCalibrated, 'Expected IsCalibrated==false.');
    record(stepName, true, 'Engine constructed offline; Fs=0, IsCalibrated=false.');
catch ME
    record(stepName, false, getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% ------------------------------------------------------------------ %
% 5) Engine: construction with mock adapter
% ------------------------------------------------------------------ %
mockFs = 48000;
stepName = 'engineMockAdapterConstruction';
try
    mockAdapter = create_mock_adapter_(mockFs);
    eng = stimgen.calibration.Engine(mockAdapter);
    assert(eng.Fs == mockFs, 'Engine.Fs did not match mock adapter sample rate.');
    record(stepName, true, sprintf('Engine.Fs=%g Hz from mock adapter.', eng.Fs));
catch ME
    record(stepName, false, getReport(ME, 'basic', 'hyperlinks', 'off'));
    mockAdapter = [];
end

% ------------------------------------------------------------------ %
% 6) Engine.calibrate_swept_sine with mock adapter
% ------------------------------------------------------------------ %
stepName = 'calibrateSweptSineMock';
try
    assert(~isempty(mockAdapter), 'Mock adapter not available; skipping.');

    eng = stimgen.calibration.Engine(mockAdapter);
    eng.ReferenceLevel = 94;
    eng.MicSensitivity = 0.01;
    eng.ExcitationVoltage = 1;
    eng.NormativeValue = 80;
    eng.calibrate_swept_sine(0.1, [1000 2000 4000 8000]);

    assert(eng.IsCalibrated, 'Engine not calibrated after calibrate_swept_sine.');
    C = eng.CalibrationData;
    assert(isfield(C, 'swept_sine'), 'CalibrationData missing swept_sine field.');
    assert(numel(C.swept_sine.frequency) == 4, 'Expected 4 frequency points.');
    assert(all(isfinite(C.swept_sine.spl_db)), 'SPL values contain non-finite entries.');

    record(stepName, true, sprintf('swept_sine LUT: %d frequencies, SPL range [%.1f, %.1f] dB', ...
        numel(C.swept_sine.frequency), min(C.swept_sine.spl_db), max(C.swept_sine.spl_db)));
catch ME
    record(stepName, false, getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% ------------------------------------------------------------------ %
% 7) Engine.calibrate_tones with mock adapter
% ------------------------------------------------------------------ %
stepName = 'calibrateTonesMock';
try
    assert(~isempty(mockAdapter), 'Mock adapter not available; skipping.');

    eng = stimgen.calibration.Engine(mockAdapter);
    eng.MicSensitivity = 0.01;
    eng.ExcitationVoltage = 1;
    eng.NormativeValue = 80;
    eng.calibrate_tones([1000 2000 4000]);

    C = eng.CalibrationData;
    assert(isfield(C, 'tone'), 'CalibrationData missing tone field.');
    assert(numel(C.tone.frequency) == 3, 'Expected 3 tone frequencies.');

    record(stepName, true, sprintf('tone LUT: %d frequencies.', numel(C.tone.frequency)));
catch ME
    record(stepName, false, getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% ------------------------------------------------------------------ %
% 8) Engine.calibrate_reference with mock adapter
% ------------------------------------------------------------------ %
stepName = 'calibrateReferenceMock';
try
    assert(~isempty(mockAdapter), 'Mock adapter not available; skipping.');

    eng = stimgen.calibration.Engine(mockAdapter);
    eng.ExcitationVoltage = 1;
    eng.ReferenceLevel = 94;
    prevSens = eng.MicSensitivity;

    eng.calibrate_reference();
    newSens = eng.MicSensitivity;

    assert(isfinite(newSens) && newSens > 0, 'MicSensitivity not updated to positive value.');
    record(stepName, true, sprintf('MicSensitivity updated: %.4f → %.4f V/Pa', prevSens, newSens));
catch ME
    record(stepName, false, getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% ------------------------------------------------------------------ %
% 9) compute_adjusted_voltage: tone type
% ------------------------------------------------------------------ %
stepName = 'computeVoltTone';
try
    assert(~isempty(mockAdapter), 'Mock adapter not available; skipping.');

    eng = stimgen.calibration.Engine(mockAdapter);
    eng.MicSensitivity = 0.01;
    eng.ExcitationVoltage = 1;
    eng.NormativeValue = 80;
    eng.calibrate_tones([1000 2000 4000]);

    v = eng.compute_adjusted_voltage("tone", 2000, 80);
    assert(isfinite(v) && v > 0, 'compute_adjusted_voltage returned non-positive value.');
    record(stepName, true, sprintf('v(2kHz, 80dB) = %.4f V', v));
catch ME
    record(stepName, false, getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% ------------------------------------------------------------------ %
% 10) compute_adjusted_voltage: swept_sine type
% ------------------------------------------------------------------ %
stepName = 'computeVoltSweptSine';
try
    assert(~isempty(mockAdapter), 'Mock adapter not available; skipping.');

    eng = stimgen.calibration.Engine(mockAdapter);
    eng.MicSensitivity = 0.01;
    eng.ExcitationVoltage = 1;
    eng.NormativeValue = 80;
    eng.calibrate_swept_sine(0.1, [1000 2000 4000 8000]);

    v = eng.compute_adjusted_voltage("swept_sine", 2000, 80);
    assert(isfinite(v) && v > 0, 'compute_adjusted_voltage (swept_sine) returned non-positive value.');
    record(stepName, true, sprintf('v(2kHz, 80dB) = %.4f V', v));
catch ME
    record(stepName, false, getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% ------------------------------------------------------------------ %
% 11) Engine.save / Engine.load round-trip for swept_sine data
% ------------------------------------------------------------------ %
stepName = 'engineSaveLoadRoundTrip';
try
    assert(~isempty(mockAdapter), 'Mock adapter not available; skipping.');

    eng = stimgen.calibration.Engine(mockAdapter);
    eng.MicSensitivity = 0.01;
    eng.ExcitationVoltage = 1;
    eng.NormativeValue = 80;
    eng.calibrate_swept_sine(0.1, [500 1000 2000 4000 8000]);
    eng.calibrate_tones([1000 2000 4000]);

    tmpFile = fullfile(tempdir, 'smoke_test_cal.esgc');
    eng.save(tmpFile);
    assert(isfile(tmpFile), 'Saved .esgc file not found on disk.');

    engLoaded = stimgen.calibration.Engine.load(tmpFile);
    assert(engLoaded.IsCalibrated, 'Loaded engine not calibrated.');
    assert(isfield(engLoaded.CalibrationData, 'swept_sine'), 'swept_sine field missing after load.');
    assert(isfield(engLoaded.CalibrationData, 'tone'), 'tone field missing after load.');

    % Verify voltage lookup works on loaded data
    vTone = engLoaded.compute_adjusted_voltage("tone", 2000, 80);
    vSS   = engLoaded.compute_adjusted_voltage("swept_sine", 2000, 80);
    assert(isfinite(vTone) && vTone > 0, 'Loaded tone voltage not positive.');
    assert(isfinite(vSS) && vSS > 0, 'Loaded swept_sine voltage not positive.');

    delete(tmpFile);
    record(stepName, true, sprintf('Round-trip OK: v_tone=%.4f V, v_swept_sine=%.4f V', vTone, vSS));
catch ME
    record(stepName, false, getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% ------------------------------------------------------------------ %
% 12-14) Hardware sections — require audio device
% ------------------------------------------------------------------ %
fprintf('  --- Hardware sections (may be skipped without audio device) ---\n');

hwAdapter = [];
stepName = 'windowsSoundCardConstruction';
try
    hwAdapter = stimgen.calibration.WindowsSoundCardAdapter(SampleRate=48000);
    record(stepName, true, 'WindowsSoundCardAdapter constructed with default device.');
catch ME
    record(stepName, false, sprintf('No audio device available: %s', ME.message));
end

stepName = 'windowsSoundCardSampleRate';
try
    assert(~isempty(hwAdapter), 'Skipped — adapter not available.');
    Fs = hwAdapter.sample_rate();
    assert(Fs == 48000, 'Expected Fs=48000, got %g.', Fs);
    assert(Fs == hwAdapter.sample_rate(), 'sample_rate not idempotent.');
    record(stepName, true, sprintf('sample_rate() = %g Hz (consistent).', Fs));
catch ME
    record(stepName, false, getReport(ME, 'basic', 'hyperlinks', 'off'));
end

stepName = 'windowsSoundCardPlayRecord';
try
    assert(~isempty(hwAdapter), 'Skipped — adapter not available.');
    Fs = hwAdapter.sample_rate();

    % Short 1 kHz tone, 50 ms
    t = (0 : round(Fs * 0.05) - 1) / Fs;
    sig = 0.1 * sin(2 * pi * 1000 * t);

    response = hwAdapter.play_and_record(sig);

    assert(numel(response) == numel(sig), ...
        'Response length %d != signal length %d.', numel(response), numel(sig));
    assert(all(isfinite(response)), 'Response contains non-finite values.');
    record(stepName, true, sprintf('play_and_record: %d samples in, %d samples out.', ...
        numel(sig), numel(response)));
catch ME
    record(stepName, false, getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% ------------------------------------------------------------------ %
% Summary
% ------------------------------------------------------------------ %
stepNames = fieldnames(report.steps);
nPassed   = sum(cellfun(@(f) report.steps.(f).passed, stepNames));
nTotal    = numel(stepNames);
report.allPassed = (nPassed == nTotal);

fprintf('\n=== SUMMARY: %d / %d passed ===\n', nPassed, nTotal);
if report.allPassed
    fprintf('All sections PASSED.\n');
else
    fprintf('Some sections FAILED. See report.steps for details.\n');
end

end  % smoke_test_sound_card_calibration


% ------------------------------------------------------------------ %
% Local helper: create a simple mock HwAdapter
% ------------------------------------------------------------------ %
function adapter = create_mock_adapter_(Fs)
% create_mock_adapter_(Fs)
% Returns a MockCalibrationAdapter instance.
% See tmp/MockCalibrationAdapter.m for implementation.
adapter = MockCalibrationAdapter(Fs);
end
