function h = createPopOut_(obj,container)
% h = createPopOut_(obj,container)
% Build a second OnlinePlot over the same box, in its own window (gui.PopOut).
%
% The pop-out is a fully independent instance: its own timer, its own read
% plan, its own buffers, and its own preference key. It therefore takes its
% own trace selection, order and styling, and nothing the operator does in
% it reaches the plot it came from -- which is the point, since the usual
% reason to pop one out is to watch a DIFFERENT set of traces large.
%
% It opens showing what the host shows, unless it has been opened before: a
% pop-out with preferences of its own restores those instead, or reopening a
% window would undo the arrangement made in it last time.
%
% See also: gui.PopOut, gui.components.OnlinePlot.popOutHostContainer_

tag = obj.popOutPreferenceTag_();
hasSaved = ispref(obj.PREF_GROUP,tag);

% A classic axes, not a uiaxes: OnlinePlot draws with line() into a duration
% ruler and sets XLim by hand, which is the same axes the BehaviorBuilder
% emits for an embedded plot.
ax = axes(container);

h = gui.components.OnlinePlot(obj.RUNTIME, obj.currentSource_, ax, obj.BoxID, ...
    PreferenceTag=tag);

if isempty(h) || ~isvalid(h), h = []; return; end
if hasSaved, return; end % it has an arrangement of its own already

% First open: mirror the host, then remember that as the pop-out's own start.
% setWatched, not setTraceOrder: in bitmask mode the constructor gives the
% bank's WHOLE bit set, and the host may be showing a subset of it.
if isempty(obj.BM)
    h.setTraceOrder(obj.traceNames);
else
    h.setWatched(obj.traceNames);
end
h.lineColors = obj.lineColors; % after setWatched, which resets them
h.lineWidth = obj.lineWidth;
for p = {'timeWindow','trialLocked','setZeroToNan','trialMarker', ...
         'showGrid','palette','redrawPeriod','maxTrialMarkers'}
    h.(p{1}) = obj.(p{1});
end
h.applyStyle_;
h.refreshMenuChecks_;
h.savePreferences_;
end
