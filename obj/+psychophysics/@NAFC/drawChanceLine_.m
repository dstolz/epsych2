function drawChanceLine_(obj, ax, chance)
% drawChanceLine_(obj, ax, chance)
% Dashed 1/N reference across the curve plots. Kept out of the legend —
% the inline label says what it is without spending a legend row.
%
% Parameters:
%   obj    — psychophysics.NAFC instance
%   ax     — target axes
%   chance — chance level as a fraction (1/NumAlternatives)

if ~obj.ShowChance || ~isfinite(chance)
    return
end

yline(ax, chance, '--', 'chance', ...
    'Color', hex2rgb(obj.ChanceColor), ...
    'LineWidth', 1, ...
    'FontSize', max(8, ax.FontSize - 2), ...
    'LabelHorizontalAlignment', 'left', ...
    'LabelVerticalAlignment', 'bottom', ...
    'HandleVisibility', 'off');
