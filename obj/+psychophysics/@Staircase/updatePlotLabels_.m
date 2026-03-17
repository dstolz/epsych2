function updatePlotLabels_(obj)
% updatePlotLabels_(obj)
% Update labels, subtitle, and title.
%
% Parameters:
%   obj — psychophysics.Staircase instance

ylabel(obj.plotAxes_, char(obj.ParameterName), 'Interpreter', 'none');
xlabel(obj.plotAxes_, 'Trial Index', 'Interpreter', 'none');

nPlotted = numel(obj.columnize_(obj.stimulusValues));
subtitle(obj.plotAxes_, sprintf('# Plotted Trials = %d', nPlotted));

[titleText, hasTitle] = obj.getTitleText_();
if hasTitle
    title(obj.plotAxes_, titleText);
    obj.plotAxes_.TitleHorizontalAlignment = 'right';
else
    title(obj.plotAxes_, '');
end
