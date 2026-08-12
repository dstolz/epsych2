function smoke_test_noninteger_fs
% Headless smoke test: the whole calibration chain -- acquisition, analysis,
% filter design, save/load, and application to a stimulus -- at a non-integer
% TDT sample rate (24414.0625 Hz). TDT converters never run at round numbers,
% so any code that treats Fs (or Fs-derived sample counts) as an integer
% breaks on real hardware while passing every 44100/48000-based test.
%
%   matlab -batch "run('tmp/smoke_test_noninteger_fs.m')"

repoRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(repoRoot, 'obj', 'stimgen'));
addpath(fileparts(mfilename('fullpath')));

global GVerbosity %#ok<GVMIS>
GVerbosity = 1;

FS = 24414.0625;                 % RX6/RZ6 base rate; deliberately non-integer
assert(FS ~= round(FS), 'test precondition: FS must be non-integer');

%% 1. Reference measurement (record-only path)
MIC_SENS = 0.01;                 % V/Pa the fake calibrator rig is built with
refAdapter = CalibratorAdapter(FS, 1000, MIC_SENS);
eng = stimgen.calibration.Engine(refAdapter);
eng.set_configuration(ReferenceFrequency=1000, ReferenceLevel=94, ExcitationVoltage=1);
eng.calibrate_reference();
assert(abs(eng.MicSensitivity - MIC_SENS) < 0.05 * MIC_SENS, ...
    'reference measured %.4g V/Pa, expected %.4g', eng.MicSensitivity, MIC_SENS);
fprintf('PASS calibrate_reference at Fs=%.4f Hz (%.4g V/Pa)\n', FS, eng.MicSensitivity);

%% 2. Acquisition sweeps through a simulated speaker
eng.set_adapter(FakeSpeakerAdapter(FS));
assert(eng.Fs == FS, 'Engine.Fs was altered on the way in: %.10g', eng.Fs);

bg = eng.measure_background(0.5, 2);
assert(isfinite(bg.spl_db), 'background level did not come out finite');
fprintf('PASS measure_background (%.1f dB SPL broadband)\n', bg.spl_db);

freqs = 500 .* 2 .^ (0:0.5:4);   % 500 Hz .. 8 kHz, comfortably below Nyquist
eng.calibrate_tones(freqs, 2);
t = eng.CalibrationData.tone;
assert(all(isfinite(t.voltage) & t.voltage > 0), 'tone LUT has bad voltages');
fprintf('PASS calibrate_tones (%d points)\n', numel(t.frequency));

% At 24414.0625 Hz the ClickTrain class default (20 us) is below one sample,
% so this also proves the sweep configures its stimulus without tripping the
% update-signal listener along the way.
lastwarn('');
eng.calibrate_clicks([0.1 0.2 0.4 0.8] * 1e-3, 2);
[warnMsg, warnId] = lastwarn();
assert(~contains(warnId, 'ClickDuration') && ~contains(warnMsg, 'less than 1 sample'), ...
    'calibrate_clicks warned about an unrenderable click at this rate: %s', warnMsg);
c = eng.CalibrationData.click;
assert(all(isfinite(c.voltage) & c.voltage > 0), 'click LUT has bad voltages');
fprintf('PASS calibrate_clicks (%d points, no listener warnings)\n', numel(c.duration));

eng.calibrate_swept_sine(0.5, [], 2);
s = eng.CalibrationData.swept_sine;
assert(all(isfinite(s.voltage) & s.voltage > 0), 'swept sine LUT has bad voltages');
irFs = s.metrics.impulse_response_fs;
assert(isfinite(irFs) && irFs > 0 && irFs <= FS + 1e-9, ...
    'stored impulse response rate is wrong: %.10g', irFs);
fprintf('PASS calibrate_swept_sine (%d points, IR stored at %.4f Hz)\n', ...
    numel(s.frequency), irFs);

%% 3. Filter design and verification at the non-integer rate
eng.design_filter("swept_sine", ShowResponse=false, SmoothingOctaves=1/6);
D = eng.CalibrationData.filterDesign;
assert(D.sampleRate == FS, 'design rate was rounded: %.10g', D.sampleRate);
assert(eng.CalibrationData.filter.SampleRate == FS, ...
    'digitalFilter carries a rounded rate: %.10g', eng.CalibrationData.filter.SampleRate);
fprintf('PASS design_filter (%d taps at Fs=%.4f Hz)\n', D.numCoefficients, D.sampleRate);

r = eng.test_filter(Duration=0.25, RepeatCount=1);
assert(isstruct(r) && isfield(r, 'passed'), 'test_filter did not return a verdict');
fprintf('PASS test_filter ran at the design rate (verdict: %d, ripple %.1f -> %.1f dB)\n', ...
    r.passed, r.unfiltered.ripple_db, r.filtered.ripple_db);

tt = eng.test_tones(freqs([1 4 7]), [60 70], RepeatCount=1);
assert(isstruct(tt) && isfield(tt, 'passed'), 'test_tones did not return a verdict');
fprintf('PASS test_tones ran (verdict: %d)\n', tt.passed);

%% 4. The rate survives a save/load round trip exactly
esgcFile = fullfile(tempdir, 'smoke_test_noninteger_fs.esgc');
cleanupEsgc = onCleanup(@() delete(esgcFile)); %#ok<NASGU>
eng.save(esgcFile);

reloaded = stimgen.calibration.Engine.load(esgcFile);
assert(reloaded.CalibrationData.filterDesign.sampleRate == FS, ...
    'save/load rounded the design rate: %.10g', ...
    reloaded.CalibrationData.filterDesign.sampleRate);
fprintf('PASS .esgc round trip preserves Fs=%.10g Hz exactly\n', ...
    reloaded.CalibrationData.filterDesign.sampleRate);

%% 5. Application: LUT scaling and filter equalization at the stimulus end
cal = stimgen.StimCalibration();
cal.load_calibration(esgcFile);

tone = stimgen.Tone;             % CalibrationType "tone" -> scalar LUT path
tone.Fs = FS;
tone.Frequency = 2000;
tone.SoundLevel = 65;
tone.Calibration = cal;
tone.ApplyCalibration = true;
tone.update_signal();
expectedV = cal.compute_adjusted_voltage("tone", 2000, 65);
assert(abs(max(abs(tone.Signal)) - expectedV) < 1e-6 * expectedV, ...
    'tone not scaled to its LUT voltage (%g vs %g)', max(abs(tone.Signal)), expectedV);
fprintf('PASS tone LUT application at Fs=%.4f Hz (%.3f V)\n', FS, expectedV);

% Band and rate at construction: the class-default 20 kHz LowPass exceeds
% this rate's 12207.03 Hz Nyquist, and Fs alone would trip the listener.
noise = stimgen.Noise('Fs', FS, 'HighPass', 500, 'LowPass', 8000);
noise.SoundLevel = 65;
noise.Calibration = cal;
noise.ApplyCalibration = true;
noise.update_signal();           % assert_filter_rate must accept FS == FS here
assert(any(noise.Signal ~= 0), 'equalized noise came out empty at the design rate');
fprintf('PASS filter application passes the rate guard at Fs=%.4f Hz\n', FS);

% Duration and rate together: the 20 us default is below one sample at FS.
click = stimgen.ClickTrain('Fs', FS, 'ClickDuration', 0.2e-3);
click.SoundLevel = 65;
click.Calibration = cal;
click.ApplyCalibration = true;
click.update_signal();
assert(any(click.Signal ~= 0), 'calibrated click train came out empty');
fprintf('PASS click LUT application at Fs=%.4f Hz\n', FS);

%% 6. Sound-card preview of a TDT-rate stimulus (informational)
% StimType.play hands Fs straight to audioplayer. This is preview only --
% hardware playback goes through the interface buffers -- but it should not
% error on a rig whose stimuli are configured at a TDT rate.
try
    ap = audioplayer(zeros(1, 64), FS); %#ok<TNMLP>
    delete(ap);
    fprintf('PASS audioplayer accepts Fs=%.4f Hz (preview works)\n', FS);
catch ME
    fprintf(2, 'INFO audioplayer rejects non-integer Fs: %s\n', ME.message);
    fprintf(2, 'INFO StimType.play would fail previewing a TDT-rate stimulus.\n');
end

fprintf('\nALL PASS\n');
end
