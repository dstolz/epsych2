function names = traceNames(obj)
% names = traceNames(obj)
% Labels of the plotted traces, bottom of the axes to top.
%
% This is the identity every operator-facing feature works in: the order
% dialog reorders these, the colour menu names them, and saved preferences
% match against them. Parameter mode reports parameter names; bitmask mode
% reports the bit labels parsed out of '~BM-<bank>#<bit>^<label>'.
%
% Returns:
%   names - 1xN cellstr, empty when nothing is plotted
%
% See also: gui.components.OnlinePlot.setTraceOrder, gui.components.OnlinePlot.setWatched

names = obj.trace_labels;
names = cellstr(names(:))';
end
