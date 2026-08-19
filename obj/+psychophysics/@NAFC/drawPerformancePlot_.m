function drawPerformancePlot_(obj, ax, R)
% drawPerformancePlot_(obj, ax, R)
% Proportion correct against the tracked parameter value, with the 1/N
% chance level for reference. The overall percent correct is in the
% subtitle position of gui.SessionPerformance, not here; this plot is
% about the shape of performance across difficulty.
%
% Parameters:
%   obj — psychophysics.NAFC instance
%   ax  — target axes
%   R   — obj.Results

c = hex2rgb(obj.PerformanceColor);

if ~isempty(R.Values)
    line(ax, R.Values, R.CorrectRate, ...
        'Color', c, ...
        'LineWidth', obj.LineWidth, ...
        'Marker', 'none', ...
        'HandleVisibility', 'off');
end

x = nan; y = nan;
if ~isempty(R.Values)
    x = R.Values; y = R.CorrectRate;
end
scatter(ax, x, y, obj.MarkerSize, ...
    'filled', ...
    'Marker', 'o', ...
    'MarkerFaceColor', c, ...
    'MarkerEdgeColor', [1 1 1], ...
    'LineWidth', 0.75, ...
    'DisplayName', 'P(correct)');

obj.drawChanceLine_(ax, R.ChanceLevel);

xlabel(ax, curveXLabel(obj), 'Interpreter', 'none');
ylabel(ax, 'P(correct)', 'Interpreter', 'none');
applyCurveLimits(ax, R.Values);
end

%% --- Local helper functions ---

function s = curveXLabel(obj)
    s = char(obj.ParameterName);
    if isempty(s)
        s = 'Value';
    end
end

function applyCurveLimits(ax, x)
    ylim(ax, [-0.03 1.03]);
    x = x(isfinite(x));
    if isempty(x)
        return
    end
    lo = min(x); hi = max(x);
    pad = (hi - lo) * 0.06;
    if pad == 0
        pad = max(0.5, abs(lo) * 0.1);
    end
    xlim(ax, [lo - pad, hi + pad]);
end
