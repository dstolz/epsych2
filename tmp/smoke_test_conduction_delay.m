function smoke_test_conduction_delay()
% smoke_test_conduction_delay()
% Verify the per-acquisition conduction delay measurement: the probe click
% embedded at the head of every tone-train acquisition, the standalone
% measure_conduction_delay probe, and the GUI readout. Headless-safe.
%
%   matlab -batch "cd('c:/src/epsych2'); epsych_startup; cd tmp; smoke_test_conduction_delay"
%
% Sections:
%   1) standalone probe recovers a known delay (flat rig)
%   2) ... through a ringing speaker coloration
%   3) ... at a non-integer TDT-style sample rate
%   4) dead microphone -> valid=false
%   5) delay beyond the search bound -> valid=false (alignment check)
%   6) calibrate_tones: every analysis window cut at onset+ramp+delay,
%      verified against the same record's own probe click; delay stats
%      recorded in the committed tone table
%   7) per-record latency jitter (the failure seen on real TDT hardware):
%      windows still land correctly because each record is cut with its
%      own embedded-click delay
%   8) test_tones on the jittering rig passes and records the delay stats
%   9) CalibrationGui reports the delay in its Conduction Delay label

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
% picks instead is rarely on the bound -- the alignment check (does the lag
% explain where the response actually is?) is what has to catch this.
eng  = stimgen.calibration.Engine(flat_rig_(FS, round(0.08 * FS)));
info = eng.measure_conduction_delay(MaxDelay=0.05);
assert(~info.valid, 'Out-of-bound delay must be reported invalid');
fprintf('PASS: out-of-bound delay rejected (corr %.3f, at_bound %d)\n', ...
    info.corr, info.at_bound);

% --- 6) calibrate_tones window placement, fixed delay ---------------------- %
freqs = 500 .* 2 .^ (0:7);
freqs(freqs >= FS / 2) = [];
rampN = round(0.005 / 2 * FS);   % the sweep's fixed 5 ms cos^2 gate

eng = stimgen.calibration.Engine(flat_rig_(FS, DELAY));
eng.set_configuration(ShowLivePlots=true);
getSpans = capture_spans_(eng, ["tone", "tone_test"]);
eng.calibrate_tones(freqs, 1);
nChecked = check_spans_(getSpans(), rampN);
assert(nChecked > 0, 'No tone-measure LiveUpdate captured');

cds = eng.CalibrationData.tone.conduction_delay_s;
assert(abs(cds * FS - DELAY) <= 2, ...
    'tone.conduction_delay_s records %.4g ms, injected %.4g ms', ...
    cds * 1e3, DELAY / FS * 1e3);
assert(eng.CalibrationData.tone.conduction_delay_sd_s < 1 / FS, ...
    'Fixed-delay rig must record ~zero delay spread');
fprintf('PASS: %d fixed-delay windows all cut at onset+ramp+delay\n', nChecked);

% --- 7) Per-record latency jitter ------------------------------------------ %
% The failure observed on real hardware: a delay measured on one record did
% not hold for the next. Every record is now cut with its own embedded-click
% delay, so the windows must stay correct while the latency moves.
jit = JitterLoopbackAdapter(FS);
jit.Delays = [100 180 260];
eng = stimgen.calibration.Engine(jit);
eng.set_configuration(ShowLivePlots=true);
getSpans = capture_spans_(eng, ["tone", "tone_test"]);
eng.calibrate_tones(freqs, 3);   % 3 reps -> the delay changes across reps
nChecked = check_spans_(getSpans(), rampN);
assert(nChecked > 0, 'No tone-measure LiveUpdate captured on the jitter rig');

sd = eng.CalibrationData.tone.conduction_delay_sd_s;
assert(sd * FS > 10, 'Jitter rig must record a nonzero delay spread (sd %.4g samples)', sd * FS);
fprintf('PASS: %d jittered windows all cut with their own record''s delay (sd %.2f ms)\n', ...
    nChecked, sd * 1e3);

% --- 8) test_tones on the jittering rig ------------------------------------ %
getSpans2 = capture_spans_(eng, ["tone", "tone_test"]);
r = eng.test_tones([], [], RepeatCount=2);
nChecked = check_spans_(getSpans2(), rampN);
assert(nChecked > 0, 'No tone_test-measure LiveUpdate captured');
assert(isfinite(r.conduction_delay_s) && isfinite(r.conduction_delay_sd_s), ...
    'test_tones must record delay statistics');
assert(r.passed, 'Tone LUT test failed on a linear jittering rig (worst %.2f dB)', ...
    r.max_abs_error_db);
assert(r.max_abs_error_db < 1, ...
    'Tone LUT error too large on a linear rig: %.2f dB', r.max_abs_error_db);
fprintf('PASS: test_tones worst error %.3f dB under latency jitter (delay %.2f +/- %.2f ms)\n', ...
    r.max_abs_error_db, r.conduction_delay_s * 1e3, r.conduction_delay_sd_s * 1e3);

% --- 9) GUI label ---------------------------------------------------------- %
gui = stimgen.calibration.CalibrationGui(eng); %#ok<NASGU>
drawnow;
lbl = find_delay_label_();
assert(~isempty(lbl), 'Conduction Delay label not found or empty after a run');
assert(contains(lbl, 'ms'), 'Conduction Delay label does not show a delay: "%s"', lbl);
fprintf('PASS: GUI reports "%s"\n', lbl);

% A fresh probe while the GUI is open must update the label through the
% property listener, which is how the readout follows a run in progress.
eng.measure_conduction_delay();
drawnow;
assert(contains(find_delay_label_(), 'ms'), 'Label did not follow a new probe');
fprintf('PASS: label follows the ConductionDelay listener\n');

fprintf('\nAll conduction delay smoke tests passed\n');
end

% ------------------------------------------------------------------------ %
function getSpans = capture_spans_(eng, stages)
% Collect every burst-measure payload's span with its own record, so each
% window can be checked against the acquisition it was cut from. Returns a
% getter rather than the cell itself: the listener mutates this workspace,
% which nested functions share, while a returned cell would be a snapshot
% taken before any event fired.
spans = {};
addlistener(eng, 'LiveUpdate', @capture_);
getSpans = @getter_;
    function capture_(~, d)
        if ismember(d.Stage, stages) && d.Phase == "measure" && numel(d.Span) == 2
            spans{end+1} = struct('span', d.Span, 'x', d.Excitation, 'y', d.Response);
        end
    end
    function s = getter_()
        s = spans;
    end
end

% ------------------------------------------------------------------------ %
function nChecked = check_spans_(spansRef, rampN)
% Every span must start one gate-ramp past its burst's onset, shifted by the
% delay measured from that same record's probe click. The true delay is
% derived from the record itself -- the probe click is the first excitation
% energy, its response peak the first response energy -- so this check holds
% whatever latency the adapter chose for that particular call.
spans = spansRef;
nChecked = numel(spans);
for k = 1:nChecked
    s = spans{k};

    nz = find(abs(s.x) > 0);
    runStarts = nz([true, diff(nz) > 1]);
    clickStart = runStarts(1);
    burst1     = runStarts(2);

    [~, peakIdx] = max(abs(s.y(1:burst1 - 1)));
    trueDelay = peakIdx - clickStart;

    a = s.span(1) - trueDelay;   % window start mapped back onto the excitation
    onset = find(abs(s.x(1:a)) == 0, 1, 'last') + 1;
    assert(abs((a - onset) - rampN) <= 5, ...
        'Span %d starts %d samples after its burst onset; expected the %d-sample ramp', ...
        k, a - onset, rampN);
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
