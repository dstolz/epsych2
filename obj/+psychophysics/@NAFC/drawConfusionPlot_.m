function drawConfusionPlot_(obj, ax, R)
% drawConfusionPlot_(obj, ax, R)
% Confusion matrix heatmap: rows are the correct alternative, columns the
% chosen one, cell color the row-normalized rate and cell text the raw
% count. Unscored rows (an alternative never presented) render transparent
% rather than as a fake zero.
%
% Parameters:
%   obj — psychophysics.NAFC instance
%   ax  — target axes
%   R   — obj.Results

labels = obj.alternativeLabels();
N = numel(labels);

M = R.ConfusionRate;
if ~isequal(size(M), [N N])
    M = nan(N, N);
end

im = imagesc(ax, M);
im.AlphaData = ~isnan(M);
clim(ax, [0 1]);

% White-to-accent ramp so the diagonal of a good session reads dark.
accent = hex2rgb(obj.PerformanceColor);
ramp = zeros(64, 3);
for i = 1:3
    ramp(:,i) = linspace(1, accent(i), 64);
end
colormap(ax, ramp);

% Counts over the cells, flipping to white where the fill gets dark.
counts = R.ConfusionCount;
if isequal(size(counts), [N N])
    for r = 1:N
        for c = 1:N
            if isnan(M(r,c)), continue; end
            if M(r,c) > 0.5
                txtColor = [1 1 1];
            else
                txtColor = [0.20 0.22 0.26];
            end
            text(ax, c, r, sprintf('%d', counts(r,c)), ...
                'HorizontalAlignment', 'center', ...
                'FontSize', ax.FontSize, ...
                'Color', txtColor);
        end
    end
end

ax.XTick = 1:N;
ax.YTick = 1:N;
ax.XTickLabel = cellstr(labels);
ax.YTickLabel = cellstr(labels);
ax.YDir = 'reverse';
xlim(ax, [0.5 N+0.5]);
ylim(ax, [0.5 N+0.5]);

xlabel(ax, 'Chosen', 'Interpreter', 'none');
ylabel(ax, 'Correct', 'Interpreter', 'none');
