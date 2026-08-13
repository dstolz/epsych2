function updatePlotLabels_(obj)
% updatePlotLabels_(obj)
% Update labels, subtitle, and title.
%
% Parameters:
%   obj — psychophysics.Staircase instance

ylabel(obj.plotAxes_, obj.yAxisLabel_(), 'Interpreter', 'none');
xlabel(obj.plotAxes_, 'Trial Index', 'Interpreter', 'none');

% trialCount is already the number of trials; extracting the stimulus values
% just to measure them walked the whole session a fourth time (and counted a
% session with no trials as one, since columnize_ returns NaN for empty).
subtitle(obj.plotAxes_, sprintf('%d trials', obj.trialCount));

[titleText, hasTitle] = obj.getTitleText_();
if hasTitle
    title(obj.plotAxes_, titleText);
else
    title(obj.plotAxes_, '');
end
