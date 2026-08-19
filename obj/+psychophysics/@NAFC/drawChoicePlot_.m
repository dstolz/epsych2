function drawChoicePlot_(obj, ax, R)
% drawChoicePlot_(obj, ax, R)
% One curve per alternative: P(chose k) against the tracked parameter
% value. For a 2AFC over a signed stimulus this is the psychometric
% function; complementary curves cross at the point of subjective equality.
%
% Parameters:
%   obj — psychophysics.NAFC instance
%   ax  — target axes
%   R   — obj.Results

labels = obj.alternativeLabels();
colors = obj.alternativeColors();
N = numel(labels);

for k = 1:N
    c = hex2rgb(colors(k));
    if ~isempty(R.Values)
        line(ax, R.Values, R.ChoiceRate(k,:), ...
            'Color', c, ...
            'LineWidth', obj.LineWidth, ...
            'Marker', 'none', ...
            'HandleVisibility', 'off');
    end
    % The scatter both marks the data points and carries the legend entry;
    % NaN placeholders keep the entry alive in an empty session, so the
    % legend still names which color is which alternative.
    x = nan; y = nan;
    if ~isempty(R.Values)
        x = R.Values; y = R.ChoiceRate(k,:);
    end
    scatter(ax, x, y, obj.MarkerSize, ...
        'filled', ...
        'Marker', 'o', ...
        'MarkerFaceColor', c, ...
        'MarkerEdgeColor', [1 1 1], ...
        'LineWidth', 0.75, ...
        'DisplayName', char(labels(k)));
end

obj.drawChanceLine_(ax, R.ChanceLevel);

xlabel(ax, curveXLabel(obj), 'Interpreter', 'none');
ylabel(ax, 'P(choice)', 'Interpreter', 'none');
applyCurveLimits(ax, R.Values);

lgd = legend(ax, 'show');
lgd.Location = 'best';
lgd.Box = 'off';
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
