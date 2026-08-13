% smoke_test_filter_level_reference.m
% Verifies stimgen.calibration.Engine.filter_level_reference: the closed-form
% white-noise source, the waveform source, exact equivalence with the software
% path's rms-normalize-then-scale, the StimCalibration proxy, and the error
% paths. Headless: a synthetic tone LUT is restored into an offline engine and
% the filter is designed with an explicit SampleRate, so no adapter or
% hardware is needed.

thisDir  = fileparts(mfilename('fullpath'));
repoRoot = fileparts(thisDir);
addpath(fullfile(repoRoot, 'obj', 'stimgen'));

fs = 97656.25;
NV = 60;                       % normative level the LUT voltages are stated at

% Synthetic tone LUT: a plausible speaker whose required drive varies smoothly
% with frequency (0.004-0.036 V), so the designed filter has real shape. The
% spl_db and measurement columns are derived consistently with the engine's
% model (voltage = Excitation * 10^((NV - spl)/20) at 1 V excitation, mic
% sensitivity 0.01 V/Pa), so the table also renders in LiveMonitor/GUI paths.
freqs = logspace(log10(500), log10(32000), 25);
volt  = 0.02 * (1 + 0.8 * sin(2 * pi * log2(freqs / 500) / 3));
spl   = NV - 20 * log10(volt);
meas  = 20e-6 * 10 .^ (spl / 20) * 0.01;

eng = stimgen.calibration.Engine();
eng.restore(struct( ...
    'CalibrationData',      struct('tone', struct('frequency', freqs(:), ...
                                'voltage', volt(:), 'spl_db', spl(:), ...
                                'measurement', meas(:))), ...
    'CalibrationTimestamp', datetime('now'), ...
    'MicSensitivity',       0.01, ...
    'ReferenceLevel',       94, ...
    'ReferenceFrequency',   1000, ...
    'NormativeValue',       NV, ...
    'ExcitationVoltage',    1));

% -- error before any filter exists --------------------------------------- %
try
    eng.filter_level_reference(1);
    error('smoke:fail', 'noFilter error was not raised');
catch ME
    assert(strcmp(ME.identifier, 'stimgen:calibration:Engine:noFilter'), ...
        'unexpected error: %s', ME.identifier);
end

eng.design_filter('tone', 'NumCoefficients', 99, 'SampleRate', fs, ...
    'ShowResponse', false);
b = tf(eng.CalibrationData.filter);

% -- 1. closed-form white source ------------------------------------------ %
r1 = eng.filter_level_reference(1);
v0 = eng.compute_adjusted_voltage('filter', nan, NV);
assert(abs(r1.filteredRms - norm(b)) < 1e-12, 'filteredRms is not ||b||2');
assert(abs(r1.scale - v0 / norm(b)) < 1e-12, 'scale is not v0/||b||2');
assert(abs(r1.unityGainSpl - (NV + 20*log10(norm(b) / v0))) < 1e-9, 'unityGainSpl formula');
assert(abs(r1.lutVoltage - v0) < 1e-15, 'lutVoltage mismatch');
assert(r1.normativeValue == NV && r1.referenceFrequency == 1000, 'echoed parameters');

% Scalar RMS scales linearly: half the source RMS doubles the scale and drops
% the unity-gain level by 6.02 dB.
r2 = eng.filter_level_reference(0.5);
assert(abs(r2.scale - 2 * r1.scale) < 1e-9 * r1.scale, 'scale not linear in source RMS');
assert(abs(r2.unityGainSpl - (r1.unityGainSpl - 20*log10(2))) < 1e-9, 'unityGainSpl offset');

% -- 2. waveform source: long white noise approaches the closed form ------ %
rng(1);
x  = randn(1, round(10 * fs));
rw = eng.filter_level_reference(x);
dbErr = abs(20 * log10(rw.filteredRms / (rms(x) * norm(b))));
assert(dbErr < 0.1, 'white waveform deviates %.3f dB from the closed form', dbErr);

% Column input reshapes through the arguments block rather than erroring.
rc = eng.filter_level_reference(x(:));
assert(abs(rc.filteredRms - rw.filteredRms) < 1e-12, 'column waveform differs');

% -- 3. software-path equivalence ------------------------------------------ %
% apply_calibration on an rms-normalized stimulus produces output RMS
% v0 * 10^((level-NV)/20) by construction. The hardware chain
% (filter -> scale -> dB gain), using the reference computed from the SAME
% waveform, must land on exactly that RMS.
level = 48;
yHard = filter(b, 1, x(:)) * rw.scale * 10^((level - NV) / 20);
want  = v0 * 10^((level - NV) / 20);
assert(abs(rms(yHard) - want) < 1e-9 * want, 'hardware chain RMS != software path RMS');

% -- 4. StimCalibration proxy ---------------------------------------------- %
sc = stimgen.StimCalibration();
sc.Engine.restore(struct( ...
    'CalibrationData',    eng.CalibrationData, ...
    'MicSensitivity',     0.01, ...
    'ReferenceLevel',     94, ...
    'ReferenceFrequency', 1000, ...
    'NormativeValue',     NV, ...
    'ExcitationVoltage',  1));
rp = sc.filter_level_reference(1);
assert(abs(rp.scale - r1.scale) < 1e-15, 'StimCalibration proxy differs from Engine');

% -- 5. error paths --------------------------------------------------------- %
try
    eng.filter_level_reference(-1);
    error('smoke:fail', 'badSourceRms error was not raised');
catch ME
    assert(strcmp(ME.identifier, 'stimgen:calibration:Engine:badSourceRms'), ...
        'unexpected error: %s', ME.identifier);
end
try
    eng.filter_level_reference(zeros(1, 1000));
    error('smoke:fail', 'badSourceWaveform error was not raised');
catch ME
    assert(strcmp(ME.identifier, 'stimgen:calibration:Engine:badSourceWaveform'), ...
        'unexpected error: %s', ME.identifier);
end

fprintf('smoke_test_filter_level_reference: ALL PASSED\n');
fprintf('  ||b||2 = %.4f, v0 = %.5f V, unity gain = %.2f dB SPL, scale = %.5g\n', ...
    norm(b), v0, r1.unityGainSpl, r1.scale);
