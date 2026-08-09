function smoke_test_calibrate_reference()
% smoke_test_calibrate_reference()
% Verify that Engine.calibrate_reference records an external acoustic
% calibrator instead of playing a tone out of the speaker.
%
% Checks:
%   1) The waveform handed to the hardware output is silent.
%   2) MicSensitivity is recovered from the recorded calibrator tone.
%   3) A recording with no calibrator tone fails loudly instead of storing a
%      sensitivity derived from noise.

fprintf('== smoke_test_calibrate_reference ==\n');

fs   = 48000;
f0   = 1000;
sens = 0.0125;   % V/Pa the fake microphone is built with

% --- 1 & 2: normal run, calibrator on the mic --------------------------
ad  = CalibratorAdapter(fs, f0, sens, 1);
eng = stimgen.calibration.Engine(ad);
eng.set_configuration(ReferenceFrequency=f0, ReferenceLevel=94);
eng.calibrate_reference();

assert(ad.PlayCount == 1, 'Expected exactly one acquisition, got %d.', ad.PlayCount);
assert(~any(ad.LastPlayed), 'A non-silent waveform was sent to the speaker.');
assert(isempty(eng.ExcitationSignal), 'ExcitationSignal should be empty for a record-only step.');
err = abs(eng.MicSensitivity - sens) / sens;
assert(err < 0.01, 'MicSensitivity %.5f differs from %.5f by %.2f%%.', ...
    eng.MicSensitivity, sens, err*100);
fprintf('  PASS  silent output, %d samples recorded, MicSensitivity = %.5f V/Pa (%.2f%% error)\n', ...
    numel(ad.LastPlayed), eng.MicSensitivity, err*100);

% --- 3: calibrator switched off ----------------------------------------
ad2  = CalibratorAdapter(fs, f0, sens, 0);   % noise only, no tone
eng2 = stimgen.calibration.Engine(ad2);
eng2.set_configuration(ReferenceFrequency=f0, ReferenceLevel=94);
try
    eng2.calibrate_reference();
    error('smoke:noError', 'A tone-free recording was accepted.');
catch ME
    assert(strcmp(ME.identifier, 'stimgen:calibration:Engine:noReferenceTone'), ...
        'Unexpected error: %s (%s)', ME.identifier, ME.message);
    fprintf('  PASS  tone-free recording rejected: %s\n', ME.message);
end
assert(eng2.MicSensitivity == 1, 'MicSensitivity was modified by a failed run.');

fprintf('== all checks passed ==\n');
end
