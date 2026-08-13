function smoke_test_calibration_refine()
% smoke_test_calibration_refine()
% Verify Engine.refine_tones/refine_clicks: the iterative test-and-correct
% loop behind the CalibrationGui's Iterative Level Refinement option, against
% a simulated compressive rig (CompressiveSpeakerAdapter).
%
% Checks:
%   1) Refusal with missingTypeCalibration before any calibration exists.
%   2) The compressive rig leaves the one-shot tone LUT measurably off at the
%      normative level -- the error the refinement exists to remove.
%   3) refine_tones converges within tolerance, changes the table, stores the
%      refinement record in the table, and leaves the final verifying test in
%      toneTest.
%   4) refine_clicks converges the click LUT the same way.
%   5) An abort mid-refinement (simulated hardware fault after a correction
%      was already applied) restores the pre-refinement table and test record.

thisDir = fileparts(mfilename('fullpath'));
repoRoot = fileparts(thisDir);
if isempty(which('stimgen.calibration.Engine'))
    addpath(fullfile(repoRoot, 'obj', 'stimgen'));
end
if isempty(which('CompressiveSpeakerAdapter'))
    addpath(thisDir);
end

fprintf('== smoke_test_calibration_refine ==\n');
rng(1312, 'twister');   % the mock adds noise; keep the run reproducible

fs  = 48000;
ad  = CompressiveSpeakerAdapter(fs);
eng = stimgen.calibration.Engine(ad);

% --- 1: refusal without data ---------------------------------------------
ok = false;
try
    eng.refine_tones();
catch ME
    ok = strcmp(ME.identifier, 'stimgen:calibration:Engine:missingTypeCalibration');
end
assert(ok, 'refine_tones without a calibration should refuse with missingTypeCalibration.');
fprintf('  PASS  refuses to refine before a calibration exists\n');

% --- 2: sweep, then measure the one-shot error ---------------------------
freqs = 500 .* 2 .^ (0:0.5:3.5);   % 8 points, 500 Hz .. ~5.7 kHz
eng.calibrate_tones(freqs, 1);
r0 = eng.test_tones(freqs, eng.NormativeValue, RepeatCount=1, ToleranceDb=0.5);
assert(~r0.passed && r0.max_abs_error_db > 1, ...
    'Expected the compressive rig to leave more than 1 dB error at the normative level; got %.2f dB.', ...
    r0.max_abs_error_db);
fprintf('  PASS  one-shot tone LUT off by %.2f dB at the normative level\n', ...
    r0.max_abs_error_db);

% --- 3: refine tones ------------------------------------------------------
vPre = eng.CalibrationData.tone.voltage;
r = eng.refine_tones(ToleranceDb=0.5, MaxIterations=5, RepeatCount=1);
assert(r.converged, 'Tone refinement did not converge: %.2f dB residual.', ...
    r.final_max_abs_error_db);
assert(r.final_max_abs_error_db <= 0.5 && ...
    r.final_max_abs_error_db < r.initial_max_abs_error_db, ...
    'Residual %.2f dB not within target or not improved from %.2f dB.', ...
    r.final_max_abs_error_db, r.initial_max_abs_error_db);
assert(r.n_iterations >= 2, 'Convergence on the first pass means nothing was corrected.');
assert(any(eng.CalibrationData.tone.voltage ~= vPre), ...
    'Refinement converged without changing the table.');
assert(isfield(eng.CalibrationData.tone, 'refinement') && ...
    eng.CalibrationData.tone.refinement.converged, ...
    'Refinement record missing from the tone table.');
assert(eng.CalibrationData.toneTest.passed, ...
    'The stored toneTest should be the final verifying (passing) test.');
fprintf('  PASS  tone LUT refined %.2f -> %.2f dB in %d pass(es)\n', ...
    r.initial_max_abs_error_db, r.final_max_abs_error_db, r.n_iterations);

% --- 4: refine clicks -----------------------------------------------------
durs = [0.04 0.08 0.16 0.32 0.64 1.28] .* 1e-3;
eng.calibrate_clicks(durs, 1);
rc = eng.refine_clicks(ToleranceDb=0.5, MaxIterations=5, RepeatCount=1);
assert(rc.converged, 'Click refinement did not converge: %.2f dB residual.', ...
    rc.final_max_abs_error_db);
assert(rc.final_max_abs_error_db < rc.initial_max_abs_error_db, ...
    'Click residual %.2f dB did not improve from %.2f dB.', ...
    rc.final_max_abs_error_db, rc.initial_max_abs_error_db);
assert(isfield(eng.CalibrationData.click, 'refinement') && ...
    eng.CalibrationData.click.refinement.converged, ...
    'Refinement record missing from the click table.');
fprintf('  PASS  click LUT refined %.2f -> %.2f dB in %d pass(es)\n', ...
    rc.initial_max_abs_error_db, rc.final_max_abs_error_db, rc.n_iterations);

% --- 5: abort restores the table ------------------------------------------
tonePre = eng.CalibrationData.tone;
testPre = eng.CalibrationData.toneTest;
ad.NCalls = 0;
ad.FailAfterNCalls = 1;   % the first test pass runs; the second one faults
ok = false;
try
    % A target no pass can meet, so a correction is applied after pass 1 and
    % the fault lands mid-refinement with the table already modified.
    eng.refine_tones(ToleranceDb=1e-3, MaxIterations=5, RepeatCount=1);
catch ME
    ok = strcmp(ME.identifier, 'tmp:CompressiveSpeakerAdapter:failed');
end
assert(ok, 'The simulated fault should have propagated out of refine_tones.');
% isequaln: single-repeat runs leave NaN in sd_db and friends, and NaN ~= NaN
% under plain isequal.
assert(isequaln(eng.CalibrationData.tone, tonePre), ...
    'Abort did not restore the tone table.');
assert(isequaln(eng.CalibrationData.toneTest, testPre), ...
    'Abort did not restore the toneTest record.');
ad.FailAfterNCalls = inf;
fprintf('  PASS  abort mid-refinement restored the table and its test record\n');

fprintf('== all checks passed ==\n');
end
