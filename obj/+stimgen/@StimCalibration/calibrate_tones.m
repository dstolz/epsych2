function calibrate_tones(obj,freqs)

if nargin < 2 || isempty(freqs)
    freqs = 100.*2.^(linspace(0,9,50));
    freqs(freqs>obj.Fs*.5) = [];
end
so = stimgen.Tone;
so.Fs = obj.Fs;
so.Duration = 0.1;
obj.StimTypeObj = so;
obj.CalibrationMode = "specfreq";
m = nan(size(freqs));
obj.CalibrationData.tone = nan(length(freqs),4);

obj.plot_reset;
for i = 1:length(freqs)
    vprintf(1,'[%d/%d] Calibrating tone frequency = %.3f kHz', ...
        i,length(freqs),freqs(i)/1000)
    so.Frequency = freqs(i);
    so.WindowDuration = 4./freqs(i);
    so.update_signal;
    y = obj.ExcitationSignalVoltage .* so.Signal;
    m(i) = obj.calibrate(y);
    
    
    c = 20*log10(m./obj.MicSensitivity) + obj.ReferenceLevel;
    v = 10.^((obj.NormativeValue-c)./20).*obj.MicSensitivity;
    obj.CalibrationData.tone = [freqs(:) m(:) c(:) v(:)];

    obj.plot_signal;
    obj.plot_spectrum;
    obj.plot_transferfcn('tone');
    % obj.plot_transferfcn([],'tone');
end