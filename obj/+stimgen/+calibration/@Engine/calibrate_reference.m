function calibrate_reference(obj)
% calibrate_reference(obj)
% Measure the microphone sensitivity using a 1-second tone at
% ReferenceFrequency. Updates MicSensitivity.
obj.assert_adapter_();
fs = obj.Fs;

so         = stimgen.Tone;
so.Fs      = fs;
so.Duration = 1;
so.Frequency = obj.ReferenceFrequency;
so.update_signal();

y = obj.ExcitationVoltage .* so.Signal;
obj.ExcitationSignal = y;

r = obj.measure_(y, "specfreq", StimFrequency=obj.ReferenceFrequency);

% Convert measured RMS voltage to V/Pa.
% At ReferenceLevel dB SPL (standard 94 dB = 1 Pa),
% dv = 1 -> MicSensitivity = r V/Pa.
dv = 10 ^ ((obj.ReferenceLevel - 94) / 20);
obj.MicSensitivity = r / dv;

stimgen.util.vprintf(1, 'Mic sensitivity = %.4f V @ %.1f dB SPL = %.4f V/Pa', ...
    r, obj.ReferenceLevel, obj.MicSensitivity);
end
