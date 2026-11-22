function updatePlotLabels_(obj)
% updatePlotLabels_(obj)
% Update labels, subtitle, and title.
%
% Each text is written only when it differs from what the axes shows. On a
% running session the two axis labels never change and the title changes
% only when the threshold does; rewriting all four on every trial made each
% redraw lay the axes out again for text that was already there.
%
% Parameters:
%   obj — psychophysics.Staircase instance

ax = obj.plotAxes_;

setAxisLabel(ax.YLabel, obj.yAxisLabel_());
setAxisLabel(ax.XLabel, 'Trial Index');

% trialCount is already the number of trials; extracting the stimulus values
% just to measure them walked the whole session a fourth time (and counted a
% session with no trials as one, since columnize_ returns NaN for empty).
sub = sprintf('%d trials', obj.trialCount);
if ~isequal(ax.Subtitle.String, sub)
    subtitle(ax, sub);
end

[titleText, hasTitle] = obj.getTitleText_();
if ~hasTitle
    titleText = '';
end
if ~isequal(ax.Title.String, titleText)
    title(ax, titleText);
end
end

function setAxisLabel(h, txt)
% An axis label, written only when its text changes. The interpreter is
% 'none' because these are parameter names, underscores and all.
if ~isequal(h.String, txt)
    h.String = txt;
end
if ~strcmp(h.Interpreter, 'none')
    h.Interpreter = 'none';
end
end
