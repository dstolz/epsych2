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
c = m; v = m;

mref = obj.MicSensitivity * sqrt(2);

obj.plot_reset;
for i = 1:length(clickdur)
    vprintf(1,'[%d/%d] Calibrating click of duration = %.2f μs', ...
        i,length(clickdur),clickdur(i)*1e6);
    so.ClickDuration = clickdur(i);
    so.update_signal;
    y = obj.ExcitationSignalVoltage .* so.Signal;
    m(i) = obj.calibrate(y);
    
    obj.plot_signal;
    obj.plot_spectrum;

    c(i) = 20*log10(m(i)./mref) + obj.ReferenceLevel;
    v(i) = 10.^((obj.NormativeValue-m(i))./20);
    obj.CalibrationData.click(i,:) = [clickdur(i) m(i) c(i) v(i)];

    obj.plot_transferfcn('click');

end