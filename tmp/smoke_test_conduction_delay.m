function smoke_test_conduction_delay()
% smoke_test_conduction_delay()
% Verify the run-start click-probe conduction delay measurement and its use
% by the tone calibration/test segmentation. Headless-safe.
%
%   matlab -batch "cd('tmp'); smoke_test_conduction_delay"
%
% Sections:
%   1) measure_conduction_delay recovers a known delay (flat rig)
%   2) ... through a ringing speaker coloration
%   3) ... at a non-integer TDT-style sample rate
%   4) dead microphone -> valid=false, run would fall back to xcorr
%   5) delay beyond the search bound -> at_bound, valid=false
%   6) calibrate_tones cuts every analysis window at onset+ramp+delay and
%      records conduction_delay_s in the committed tone table
%   7) test_tones passes on a delayed rig and records the same delay
%   8) CalibrationGui reports the delay in its Conduction Delay label

epsych_startup

cleanupObj = onCleanup(@() delete(findall(groot, 'Type', 'figure'))); %#ok<NASGU>

FS    = 44100;
DELAY = 141;   % samples, ~3.2 ms: the regime the reported bug was seen in

% --- 1) Known delay, flat rig -------------------------------------------- %
fake = flat_rig_(FS, DELAY);
eng  = stimgen.calibration.Engine(fake);
info = eng.measure_conduction_delay();
assert(info.valid, 'Flat-rig probe reported invalid');
assert(abs(info.delay_samples - DELAY) <= 2, ...
    'Flat-rig delay off: measured %d, injected %d', info.delay_samples, DELAY);
assert(isequal(eng.ConductionDelay, info), 'ConductionDelay property not stored');
fprintf('PASS: delay recovered on flat rig (%.2f ms)\n', info.delay_s * 1e3);

% --- 2) Known delay through the ringing coloration ----------------------- %
fake = FakeSpeakerAdapter(FS);
fake.DelaySamples = DELAY;
eng  = stimgen.calibration.Engine(fake);
info = eng.measure_conduction_delay();
assert(info.valid, 'Colored-rig probe reported invalid');
assert(abs(info.delay_samples - DELAY) <= 2, ...
    'Colored-rig delay off: measured %d, injected %d', info.delay_samples, DELAY);
fprintf('PASS: delay recovered through speaker coloration\n');

% --- 3) Non-integer TDT-style rate --------------------------------------- %
fsTdt = 97656.25;
dTdt  = round(0.0032 * fsTdt);
eng   = stimgen.calibration.Engine(flat_rig_(fsTdt, dTdt));
info  = eng.measure_conduction_delay();
assert(info.valid && abs(info.delay_samples - dTdt) <= 2, ...
    'TDT-rate delay off: measured %d, injected %d', info.delay_samples, dTdt);
fprintf('PASS: delay recovered at Fs = %.10g Hz\n', fsTdt);

% --- 4) Dead microphone --------------------------------------------------- %
eng  = stimgen.calibration.Engine(DeadMicAdapter());
info = eng.measure_conduction_delay();
assert(~info.valid, 'Dead-mic probe must not be trusted');
fprintf('PASS: dead microphone rejected (valid=false)\n');

% --- 5) Delay beyond the search bound ------------------------------------- %
% The bounded search cannot land on the true delay, and the noise peak it
% picks instead is rarely on the bound -- the alignment-quality check is
% what has to catch this.
eng  = stimgen.calibration.Engine(flat_rig_(FS, round(0.08 * FS)));
info = eng.measure_conduction_delay(MaxDelay=0.05);
assert(~info.valid, 'Out-of-bound delay must be reported invalid');
fprintf('PASS: out-of-bound delay rejected (corr %.3f, at_bound %d)\n', ...
    info.corr, info.at_bound);

% --- 6) calibrate_tones window placement ---------------------------------- %
fake = flat_rig_(FS, DELAY);
eng  = stimgen.calibration.Engine(fake);
eng.set_configuration(ShowLivePlots=true);

spans = {};
lsn = addlistener(eng, 'LiveUpdate', @(~, d) capture_span_(d)); %#ok<NASGU>

freqs = 500 .* 2 .^ (0:7) ./ 1;   % 500 Hz .. 64 kHz, trimmed by the engine
freqs(freqs >= FS / 2) = [];
eng.calibrate_tones(freqs, 1);

rampN = round(0.005 / 2 * FS);   % the sweep's fixed 5 ms cos^2 gate
assert(~isempty(spans), 'No tone-measure LiveUpdate captured');
for k = 1:numel(spans)
    s = spans{k};
    a = s.span(1) - DELAY;   % window start mapped back onto the excitation
    onset = find(abs(s.x(1:a)) == 0, 1, 'last') + 1;   % burst onset in x
    assert(abs((a - onset) - rampN) <= 3, ...
        'Span %d starts %d samples after onset; expected ramp of %d', ...
        k, a - onset, rampN);
end
cds = eng.CalibrationData.tone.conduction_delay_s;
assert(abs(cds * FS - DELAY) <= 2, ...
    'tone.conduction_delay_s records %.4g ms, injected %.4g ms', ...
    cds * 1e3, DELAY / FS * 1e3);
fprintf('PASS: %d analysis windows all cut at onset+ramp+delay\n', numel(spans));

% --- 7) test_tones on the delayed rig ------------------------------------- %
r = eng.test_tones([], [], RepeatCount=1);
assert(isfinite(r.conduction_delay_s) && abs(r.conduction_delay_s * FS - DELAY) <= 2, ...
    'test_tones conduction_delay_s wrong');
assert(r.passed, 'Tone LUT test failed on a linear delayed rig (worst %.2f dB)', ...
    r.max_abs_error_db);
assert(r.max_abs_error_db < 1, ...
    'Tone LUT error too large on a linear rig: %.2f dB', r.max_abs_error_db);
fprintf('PASS: test_tones worst error %.3f dB with %.2f ms delay\n', ...
    r.max_abs_error_db, r.conduction_delay_s * 1e3);

% --- 8) GUI label ---------------------------------------------------------- %
gui = stimgen.calibration.CalibrationGui(eng); %#ok<NASGU>
drawnow;
lbl = find_delay_label_();
assert(~isempty(lbl), 'Conduction Delay label not found or empty after a run');
assert(contains(lbl, 'ms'), 'Conduction Delay label does not show a delay: "%s"', lbl);
fprintf('PASS: GUI reports "%s"\n', lbl);

% A fresh probe while the GUI is open must update the label through the
% property listener, which is how the readout appears mid-run.
eng.measure_conduction_delay();
drawnow;
assert(contains(find_delay_label_(), 'ms'), 'Label did not follow a new probe');
fprintf('PASS: label follows the ConductionDelay listener\n');

fprintf('\nAll conduction delay smoke tests passed\n');

% ------------------------------------------------------------------------ %
    function capture_span_(d)
        if d.Stage == "tone" && d.Phase == "measure" && numel(d.Span) == 2
            spans{end+1} = struct('span', d.Span, 'x', d.Excitation);
        end
    end
end

% ------------------------------------------------------------------------ %
function fake = flat_rig_(fs, delaySamples)
% FakeSpeakerAdapter reduced to gain + delay + noise, so level assertions
% are exact rather than riding the coloration FIR.
fake = FakeSpeakerAdapter(fs);
fake.Coloration = 1;
fake.DelaySamples = delaySamples;
end

% ------------------------------------------------------------------------ %
function txt = find_delay_label_()
% Text of the Conduction Delay readout, located by the caption next to it.
txt = '';
labels = findall(groot, 'Type', 'uilabel');
for k = 1:numel(labels)
    if strcmp(labels(k).Text, 'Conduction Delay')
        sibs = findall(labels(k).Parent, 'Type', 'uilabel');
        for j = 1:numel(sibs)
            if sibs(j).Layout.Row == labels(k).Layout.Row && ...
                    sibs(j).Layout.Column == 2
                txt = sibs(j).Text;
                return
            end
        end
    end
end
end
