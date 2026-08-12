function smoke_test_ac_coupling()
% smoke_test_ac_coupling()
% Verify that Engine.AcCoupleResponse high-passes acquired records the way the
% option promises, and that it replaces the DemeanResponse option it grew out
% of without stranding files written under the old name.
%
% Checks:
%   1) Off by default: the record keeps its DC offset.
%   2) On: DC and sub-corner drift are removed, the in-band tone is not.
%   3) Zero phase: the coupled record is not shifted against the raw one.
%   4) The corner is honoured -- raising it above the tone attenuates the tone.
%   5) LiveUpdate metrics report the corner and the DC that came off.
%   6) A corner at or above Nyquist is skipped rather than thrown.
%   7) A record too short to filter falls back to mean removal.
%   8) .esgc round-trip preserves both new parameters.
%   9) A struct carrying the retired DemeanResponse restores as AC coupling.

fprintf('== smoke_test_ac_coupling ==\n');

fs  = 48000;
dur = 1;
ad  = AcCoupleTestAdapter(fs);

% --- 1: default off ------------------------------------------------------
eng = stimgen.calibration.Engine(ad);
assert(~eng.AcCoupleResponse, 'AcCoupleResponse should default to false.');
assert(eng.AcCoupleFrequency == 20, 'AcCoupleFrequency should default to 20 Hz.');

eng.measure_background(dur, 1);
raw = eng.ResponseSignal;
assert(abs(mean(raw) - ad.DcOffset) < 1e-3, ...
    'Uncoupled record lost its DC offset: mean %.4g V, expected %.4g V.', ...
    mean(raw), ad.DcOffset);
fprintf('  PASS  off by default: record keeps its %.1f mV offset\n', mean(raw)*1e3);

% --- 2: coupled ----------------------------------------------------------
eng.set_configuration(AcCoupleResponse=true);
eng.measure_background(dur, 1);
cpl = eng.ResponseSignal;

assert(numel(cpl) == numel(raw), 'Coupling changed the record length.');
% Not zero: filtfilt settles across the record's ends, which leaves a small
% residual mean behind. What matters is that the offset is gone as an offset.
dcDb = 20*log10(max(abs(mean(cpl)), eps) / ad.DcOffset);
assert(dcDb < -30, 'Coupled record still carries %.4g V DC (only %.1f dB down).', ...
    mean(cpl), -dcDb);

toneRaw = amp_at_(raw, ad.ToneFreq,  fs);
toneCpl = amp_at_(cpl, ad.ToneFreq,  fs);
drRaw   = amp_at_(raw, ad.DriftFreq, fs);
drCpl   = amp_at_(cpl, ad.DriftFreq, fs);

toneErr = abs(toneCpl - toneRaw) / toneRaw;
driftDb = 20*log10(max(drCpl, eps) / max(drRaw, eps));
assert(toneErr < 0.01, 'The %g Hz tone changed by %.2f%% through the filter.', ...
    ad.ToneFreq, toneErr*100);
assert(driftDb < -20, 'The %g Hz drift was only attenuated %.1f dB.', ...
    ad.DriftFreq, -driftDb);
fprintf('  PASS  coupled: DC %.3g V, %g Hz drift %.1f dB down, %g Hz tone within %.2f%%\n', ...
    mean(cpl), ad.DriftFreq, -driftDb, ad.ToneFreq, toneErr*100);

% --- 3: zero phase -------------------------------------------------------
% Compare over the middle of the record so the filter's edge settling does not
% dominate the correlation.
n   = numel(raw);
mid = round(n*0.25):round(n*0.75);
[xc, lags] = xcorr(cpl(mid) - mean(cpl(mid)), raw(mid) - mean(raw(mid)), 200);
[~, iPk] = max(xc);
assert(lags(iPk) == 0, 'Coupling shifted the record by %d samples.', lags(iPk));
fprintf('  PASS  zero phase: peak correlation at lag 0\n');

% --- 4: the corner is the corner ----------------------------------------
eng.set_configuration(AcCoupleFrequency=8000);
eng.measure_background(dur, 1);
toneHigh = amp_at_(eng.ResponseSignal, ad.ToneFreq, fs);
cutDb = 20*log10(max(toneHigh, eps) / toneRaw);
assert(cutDb < -20, 'An 8 kHz corner only cut the 2 kHz tone by %.1f dB.', -cutDb);
fprintf('  PASS  corner honoured: 8 kHz corner cuts the %g Hz tone %.1f dB\n', ...
    ad.ToneFreq, -cutDb);

% --- 5: metrics reported to the monitor ---------------------------------
eng.set_configuration(AcCoupleFrequency=20, ShowLivePlots=true);
captured = [];
lh = addlistener(eng, 'LiveUpdate', @(~,d) assignin_(d));
cleanup = onCleanup(@() delete(lh));
eng.measure_background(dur, 1);
assert(~isempty(captured), 'No LiveUpdate was broadcast.');
assert(captured.Metrics.ac_coupled_hz == 20, ...
    'ac_coupled_hz reported %.4g, expected 20.', captured.Metrics.ac_coupled_hz);
assert(abs(captured.Metrics.dc_removed_v - ad.DcOffset) < 1e-3, ...
    'dc_removed_v reported %.4g V, expected %.4g V.', ...
    captured.Metrics.dc_removed_v, ad.DcOffset);
fprintf('  PASS  metrics: ac_coupled_hz = %g Hz, dc_removed_v = %.1f mV\n', ...
    captured.Metrics.ac_coupled_hz, captured.Metrics.dc_removed_v*1e3);
clear cleanup

% --- 5b: the waveform panel says so --------------------------------------
mon = stimgen.calibration.LiveMonitor(eng);
monCleanup = onCleanup(@() delete(mon));
eng.measure_background(dur, 1);
titleTxt = mon.AxSignal.Title.String;
assert(contains(titleTxt, 'AC coupled 20 Hz'), ...
    'Waveform title does not name the coupling: "%s"', titleTxt);
assert(contains(titleTxt, 'DC 80.00 mV removed'), ...
    'Waveform title does not name the DC removed: "%s"', titleTxt);
fprintf('  PASS  waveform title: "%s"\n', titleTxt);
clear monCleanup
eng.set_configuration(ShowLivePlots=false);

% --- 6: corner at or above Nyquist ---------------------------------------
% Compared against the same acquisition with coupling off rather than against
% the offset alone: over a fraction of a drift cycle the record's mean is not
% the offset, and the point here is that nothing at all was done to it.
eng.set_configuration(AcCoupleResponse=false);
eng.measure_background(0.2, 1);
untouched = eng.ResponseSignal;
eng.set_configuration(AcCoupleResponse=true, AcCoupleFrequency=fs);
eng.measure_background(0.2, 1);
assert(isequal(eng.ResponseSignal, untouched), ...
    'A skipped filter still altered the record.');
fprintf('  PASS  corner above Nyquist skipped, record passed through unchanged\n');
eng.set_configuration(AcCoupleFrequency=20);

% --- 7: record too short to filter ---------------------------------------
% Under filtfilt's minimum of three filter orders the mean subtraction stands
% in on its own. Reached here by acquiring at a rate low enough that the
% shortest record measure_background allows is only a handful of samples.
shortAd  = AcCoupleTestAdapter(100);
shortAd.ToneFreq = 10;
shortEng = stimgen.calibration.Engine(shortAd);
shortEng.set_configuration(AcCoupleResponse=true);
% The record is conditioned and stored before the band analysis runs, and that
% analysis has its own floor on how few samples it can reduce -- well above the
% filter's. So the run is expected to abort, and what is under test is the
% record it left behind.
try
    shortEng.measure_background(0.05, 1);
catch ME
    assert(contains(ME.message, 'segments'), 'Unexpected failure: %s', ME.message);
end
short = shortEng.ResponseSignal;
assert(numel(short) <= 6, 'Expected a record short enough to skip the filter, got %d samples.', ...
    numel(short));
assert(abs(mean(short)) < 1e-12, 'Short record kept %.4g V of DC.', mean(short));
fprintf('  PASS  %d-sample record fell back to mean removal\n', numel(short));

% --- 8: .esgc round-trip -------------------------------------------------
ffn = fullfile(tempdir, 'smoke_ac_coupling.esgc');
eng.set_configuration(AcCoupleResponse=true, AcCoupleFrequency=35);
eng.save(ffn);
loaded = stimgen.calibration.Engine.load(ffn);
assert(loaded.AcCoupleResponse, 'AcCoupleResponse did not survive the round-trip.');
assert(loaded.AcCoupleFrequency == 35, ...
    'AcCoupleFrequency came back as %.4g, expected 35.', loaded.AcCoupleFrequency);
delete(ffn);
fprintf('  PASS  .esgc round-trip kept AC coupling on at 35 Hz\n');

% --- 9: legacy DemeanResponse migrates ----------------------------------
legacy = stimgen.calibration.Engine();
legacy.restore(struct('DemeanResponse', true));
assert(legacy.AcCoupleResponse, ...
    'A struct carrying DemeanResponse=true did not turn AC coupling on.');
assert(legacy.AcCoupleFrequency == 20, 'Migration should use the default corner.');
fprintf('  PASS  retired DemeanResponse restores as AC coupling at the default corner\n');

fprintf('== all checks passed ==\n');

    function assignin_(d)
        captured = d;
    end
end

% ------------------------------------------------------------------------ %
function a = amp_at_(y, f, fs)
% Single-sided amplitude of y at frequency f, by direct projection so the
% estimate does not depend on where f lands relative to an FFT bin.
n = numel(y);
t = (0:n-1) / fs;
a = 2 * abs(mean(y .* exp(-2i*pi*f*t)));
end
