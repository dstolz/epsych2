function plot_transfer(~, type, tableData, reset)
% plot_transfer(obj, type)
% plot_transfer(obj, type, tableData) - overlay in-progress table
% plot_transfer(obj, '', [], true)    - clear axes
if nargin < 2, type = ''; end
if nargin < 3, tableData = []; end
if nargin < 4, reset = false; end
f  = stimgen.calibration.Engine.cal_fig_('transfer');
ax = axes('Parent', f);
if reset, cla(ax); drawnow; return; end
if isempty(type), return; end

hold(ax, 'on');
switch type
    case 'tone'
        if ~isempty(tableData)
            validIdx = ~isnan(tableData.spl_db);
            x = tableData.x(validIdx) ./ 1000;
            y = tableData.spl_db(validIdx);
            plot(ax, x, y, 'x-r');
            xlabel(ax, 'frequency (kHz)');
        end
    case 'click'
        if ~isempty(tableData)
            validIdx = ~isnan(tableData.spl_db);
            x = tableData.x(validIdx) .* 1e6;
            y = tableData.spl_db(validIdx);
            plot(ax, x, y, 'o-b');
            xlabel(ax, 'duration (μs)');
        end
    case 'swept_sine'
        if ~isempty(tableData)
            validIdx = ~isnan(tableData.spl_db);
            x = tableData.x(validIdx) ./ 1000;
            y = tableData.spl_db(validIdx);
            loglog(ax, x, y, '^-g');
            xlabel(ax, 'frequency (kHz)');
        end
end
ylabel(ax, 'dB SPL');
grid(ax, 'on');
hold(ax, 'off');
end
