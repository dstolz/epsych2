function lbl = yAxisLabel_(obj)
% lbl = yAxisLabel_(obj)
% The y-axis label, "<Name> (<Unit>)". The unit is obj.Unit when set, else
% the tracked hw.Parameter's. An offline staircase tracks a DATA field, which
% carries no unit, so the label is the name alone until the caller sets Unit.
%
% Parameters:
%   obj — psychophysics.Staircase instance
%
% Returns:
%   lbl — char y-axis label

lbl = char(obj.ParameterName);

unit = char(obj.Unit);
if isempty(unit) && isa(obj.Parameter, 'hw.Parameter')
    unit = char(obj.Parameter.Unit);
end

if ~isempty(unit)
    lbl = sprintf('%s (%s)', lbl, unit);
end
