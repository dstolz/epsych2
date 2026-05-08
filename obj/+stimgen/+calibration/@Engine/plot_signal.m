function plot_signal(obj, reset)
% plot_signal(obj)  - plot current ResponseSignal vs time
% plot_signal(obj, true) - clear axes
arguments
    obj
    reset (1,1) logical = false
end
f = stimgen.calibration.Engine.cal_fig_('signal');
ax = subplot(2,1,1, 'Parent', f);
if reset, cla(ax); drawnow; return; end
if isempty(obj.ResponseSignal), return; end
fs = obj.Fs;
if fs == 0, return; end
t = (0:numel(obj.ResponseSignal)-1) ./ fs;
plot(ax, t, obj.ResponseSignal);
grid(ax, 'on');
xlabel(ax, 'time (s)');
ylabel(ax, 'V');
end
