function smoke_test_filter_design_samplerate
% Headless smoke test for the design_filter SampleRate override and the
% CalibrationGui rate-mismatch reporting that goes with it.
%
%   matlab -batch "run('tmp/smoke_test_filter_design_samplerate.m')"

repoRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(repoRoot, 'obj', 'stimgen'));
addpath(fileparts(mfilename('fullpath')));

global GVerbosity %#ok<GVMIS>
GVerbosity = 1;

%% 1. Lint the touched files
sg = fullfile(repoRoot, 'obj', 'stimgen', '+stimgen');
files = { ...
    fullfile(sg, '+calibration', '@Engine', 'design_filter.m'), ...
    fullfile(sg, '+calibration', 'CalibrationGui.m'), ...
    fullfile(sg, '+util', 'assert_filter_rate.m'), ...
    fullfile(sg, '@StimType', 'apply_calibration.m'), ...
    fullfile(sg, 'SoundFile.m'), ...
    fullfile(sg, '@StimPlayer', 'StimPlayer.m')};
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

%% 2. Default still follows the adapter
FS_HW  = 44100;
FS_ALT = 22050;

adapter = FakeSpeakerAdapter(FS_HW);
eng = stimgen.calibration.Engine(adapter);
eng.set_configuration(MicSensitivity=0.01, ExcitationVoltage=1);
eng.calibrate_swept_sine(0.5, [], 1);

eng.design_filter("swept_sine", ShowResponse=false, SmoothingOctaves=1/6);
D = eng.CalibrationData.filterDesign;
assert(abs(D.sampleRate - FS_HW) < 1e-9, 'default design rate %g, expected %g', D.sampleRate, FS_HW);
assert(abs(eng.CalibrationData.filter.SampleRate - FS_HW) < 1e-9, 'filter carries the wrong SampleRate');
hHw = eng.CalibrationData.filter.Coefficients;
fprintf('PASS default rate follows adapter (%g Hz)\n', D.sampleRate);

%% 3. Override designs for another rate, and clips the band to its Nyquist
eng.design_filter("swept_sine", ShowResponse=false, SmoothingOctaves=1/6, SampleRate=FS_ALT);
D = eng.CalibrationData.filterDesign;
assert(abs(D.sampleRate - FS_ALT) < 1e-9, 'override ignored: design rate %g', D.sampleRate);
assert(abs(eng.CalibrationData.filter.SampleRate - FS_ALT) < 1e-9, 'filter carries the wrong SampleRate');
assert(D.frequencyRange(2) <= FS_ALT/2 + 1e-9, ...
    'design band %g Hz exceeds the new Nyquist %g Hz', D.frequencyRange(2), FS_ALT/2);
hAlt = eng.CalibrationData.filter.Coefficients;
fprintf('PASS override designs at %g Hz, band %g-%g Hz\n', ...
    D.sampleRate, D.frequencyRange(1), D.frequencyRange(2));

%% 4. The two designs agree in Hz -- which is the entire point
% Same measured LUT, two rates: the correction applied at a given frequency
% in Hz must match. Compared as a shape (difference between two in-band
% frequencies) because each design normalizes to its own peak.
F1 = 2000; F2 = 6000;
shapeHw  = band_shape_db_(hHw,  FS_HW,  F1, F2);
shapeAlt = band_shape_db_(hAlt, FS_ALT, F1, F2);
fprintf('shape %g->%g Hz: %.2f dB at %g Hz vs %.2f dB at %g Hz\n', ...
    F1, F2, shapeHw, FS_HW, shapeAlt, FS_ALT);
assert(abs(shapeHw - shapeAlt) < 2, ...
    'redesigned filter does not reproduce the same correction in Hz (%.2f vs %.2f dB)', ...
    shapeHw, shapeAlt);

% Negative control: the same taps run at the wrong rate do not.
shapeWrong = band_shape_db_(hHw, FS_ALT, F1, F2);
fprintf('same taps run at %g Hz instead: %.2f dB (error %.2f dB)\n', ...
    FS_ALT, shapeWrong, shapeWrong - shapeHw);
assert(abs(shapeWrong - shapeHw) > 2, ...
    'negative control did not separate: the simulated speaker is too flat to test this');
fprintf('PASS correction lands on the same frequencies in Hz\n');

%% 5. test_filter refuses the mismatched filter
try
    eng.test_filter(Duration=0.25, RepeatCount=1);
    error('smoke:rateGuard', 'test_filter accepted a filter designed for another rate');
catch ME
    assert(strcmp(ME.identifier, 'stimgen:calibration:Engine:filterRateMismatch'), ...
        'unexpected error: %s / %s', ME.identifier, ME.message);
end
fprintf('PASS test_filter refuses a rate mismatch\n');

%% 6. Offline: no adapter, so the rate must be supplied
offline = stimgen.calibration.Engine();
offline.restore(struct('CalibrationData', eng.CalibrationData));
try
    offline.design_filter("swept_sine", ShowResponse=false);
    error('smoke:offlineGuard', 'offline design_filter did not demand a sample rate');
catch ME
    assert(strcmp(ME.identifier, 'stimgen:calibration:Engine:noSampleRate'), ...
        'unexpected error: %s / %s', ME.identifier, ME.message);
    assert(contains(ME.message, 'SampleRate'), ...
        'the offline error does not mention the way out: %s', ME.message);
end

offline.design_filter("swept_sine", ShowResponse=false, SampleRate=100e3);
assert(abs(offline.CalibrationData.filterDesign.sampleRate - 100e3) < 1e-9, ...
    'offline design did not take the supplied rate');
fprintf('PASS offline redesign with an explicit rate\n');

%% 7. The GUI says so: the sample-rate line names a mismatched design rate
cleanupObj = onCleanup(@() close_all_uifigures_());
gui = stimgen.calibration.CalibrationGui(eng);   % filter at 22050, adapter at 44100
lbl = sample_rate_label_();
fprintf('sample rate label: "%s"\n', lbl.Text);
assert(contains(lbl.Text, '22050'), 'label does not name the filter design rate: %s', lbl.Text);
assert(lbl.FontColor(1) > lbl.FontColor(2), 'label is not flagged red on a mismatch');
delete(gui);
close_all_uifigures_();

% Redesigning at the adapter's rate clears it.
eng.design_filter("swept_sine", ShowResponse=false, SmoothingOctaves=1/6);
gui2 = stimgen.calibration.CalibrationGui(eng); %#ok<NASGU>
lbl2 = sample_rate_label_();
fprintf('sample rate label after redesign: "%s"\n', lbl2.Text);
assert(~contains(lbl2.Text, 'designed at'), 'label still warns after the rates matched: %s', lbl2.Text);
assert(all(lbl2.FontColor == 0), 'label stayed red after the rates matched');
fprintf('PASS GUI reports the mismatch\n');

%% 8. A stimulus refuses a filter cut for another rate
% The engine now holds a filter designed at FS_HW (step 7 redesigned it).
eng.set_configuration(ToneLutSource="swept_sine");   % the only LUT this rig has
esgcFile = fullfile(tempdir, 'smoke_test_filter_rate.esgc');
eng.save(esgcFile);
cleanupEsgc = onCleanup(@() delete(esgcFile));

cal = stimgen.StimCalibration();
cal.load_calibration(esgcFile);

stim = stimgen.Noise;            % CalibrationType "filter"
stim.SoundLevel = 60;
stim.Calibration = cal;
stim.ApplyCalibration = true;

stim.Fs = FS_HW;                 % matches the filter -- must go through
stim.update_signal();
assert(any(stim.Signal ~= 0), 'calibrated stimulus came out empty at the design rate');
fprintf('PASS stimulus equalizes at the filter''s design rate\n');

stim.Fs = 96000;                 % does not -- must refuse
try
    stim.update_signal();
    error('smoke:applyGuard', 'apply_calibration filtered at the wrong rate without complaint');
catch ME
    assert(strcmp(ME.identifier, 'stimgen:util:filterRateMismatch'), ...
        'unexpected error: %s / %s', ME.identifier, ME.message);
    assert(contains(ME.message, 'SampleRate'), ...
        'the error does not name the way out: %s', ME.message);
end
fprintf('PASS stimulus refuses a filter designed for another rate\n');

% An unequalized stimulus at the same rate is unaffected: the guard is on the
% filter, not on the calibration.
tone = stimgen.Tone;             % CalibrationType "tone"
tone.Fs = 96000;
tone.Frequency = 4000;
tone.SoundLevel = 60;
tone.Calibration = cal;
tone.ApplyCalibration = true;
tone.update_signal();
assert(any(tone.Signal ~= 0), 'scalar-calibrated stimulus was blocked by the filter guard');
fprintf('PASS scalar (non-filter) calibration is untouched by the guard\n');

fprintf('\nALL PASS\n');
end

% ------------------------------------------------------------------------ %
function d = band_shape_db_(h, fs, f1, f2)
% Gain difference in dB between two frequencies in Hz, for taps h run at fs.
H = freqz(h, 1, [f1 f2], fs);
d = 20 * log10(abs(H(2)) / abs(H(1)));
end

function lbl = sample_rate_label_()
% The open GUI's Hardware Sample Rate value label, found by its neighbouring
% caption: the handle property itself is private.
fig = findall(groot, 'Type', 'figure', 'Name', 'Stim Calibration');
assert(~isempty(fig), 'the calibration window is not open');
labels = findall(fig(1), 'Type', 'uilabel');
for k = 1:numel(labels)
    if ~strcmp(labels(k).Text, 'Hardware Sample Rate'), continue; end
    row = labels(k).Layout.Row;
    for j = 1:numel(labels)
        if labels(j).Layout.Row == row && labels(j) ~= labels(k)
            lbl = labels(j);
            return
        end
    end
end
error('smoke:noLabel', 'could not find the sample rate label');
end

function close_all_uifigures_()
figs = findall(groot, 'Type', 'figure');
for k = 1:numel(figs)
    delete(figs(k));
end
end
