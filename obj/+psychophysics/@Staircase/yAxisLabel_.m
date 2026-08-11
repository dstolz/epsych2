function lbl = yAxisLabel_(obj)
% lbl = yAxisLabel_(obj)
% Build the y-axis label for the staircase plot as "<Name> (<Unit>)", using the
% tracked parameter's raw unit. When ConvertToDecibels is enabled the plotted
% values are no longer in that unit, so the decibel reference is shown instead.
% Offline string parameters carry no unit, so the label is the name alone.
%
% Parameters:
%   obj — psychophysics.Staircase instance
%
% Returns:
%   lbl — char y-axis label

lbl = char(obj.ParameterName);

if obj.ConvertToDecibels
    unit = 'dB re 100%';
elseif isa(obj.Parameter, 'hw.Parameter')
    unit = char(obj.Parameter.Unit);
else
    unit = '';
end

if ~isempty(unit)
    lbl = sprintf('%s (%s)', lbl, unit);
end
