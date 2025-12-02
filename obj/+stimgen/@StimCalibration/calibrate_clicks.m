function calibrate_clicks(obj,clickdur)

if nargin < 2 || isempty(clickdur)
    clickdur = 2.^(0:7)./obj.Fs;
end
so = stimgen.ClickTrain;
so.Fs = obj.Fs;
so.Duration = 0.05;
so.Rate = 1;
so.WindowFcn = "";
so.OnsetDelay = 0.01;
obj.StimTypeObj = so;
obj.CalibrationMode = "peak";
m = nan(size(clickdur));
for i = 1:length(clickdur)
    vprintf(1,'[%d/%d] Calibrating click of duration = %.2f μs', ...
        i,length(clickdur),clickdur(i)*1e6);
    so.ClickDuration = clickdur(i);
    so.update_signal;
    y = obj.ExcitationSignalVoltage .* so.Signal;
    m(i) = obj.calibrate(y);
    
    obj.plot_signal;
    obj.plot_spectrum;
    obj.plot_transferfcn('click');
%     obj.plot_transferfcn([],'click');
end
% RMS -> peak
mref = obj.MicSensitivity * sqrt(2);
c = 20*log10(m./mref) + obj.ReferenceLevel + 20*log10(sqrt(2));
v = 10.^((obj.NormativeValue-c)./20);
obj.CalibrationData.click = [clickdur(:) m(:) c(:) v(:)];
