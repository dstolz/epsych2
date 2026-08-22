function savePreferences_(obj)
% savePreferences_(obj)
% Persist this plot's layout and appearance under its preference key.
%
% Per-trace styling is stored BY TRACE NAME rather than by position, so a
% colour the operator picked follows its signal through a reorder, a
% reselection, or a protocol edit that changes how many traces there are.
% Everything else is a scalar and stores as itself.
%
% Nothing here throws: a plot whose preferences cannot be written must still
% run the session.
%
% See also: gui.OnlinePlot.loadPreferences_

if obj.suspendSave_, return; end % restoring; do not write back what we just read

try
    names = obj.traceNames;
    c = obj.lineColors;
    w = obj.lineWidth;

    style = struct('Name',{},'Color',{},'Width',{});
    for i = 1:numel(names)
        style(i).Name  = names{i};
        style(i).Color = c(i,:);
        style(i).Width = w(i);
    end

    s = struct();
    s.Version = 1;
    s.TimeWindow = seconds(obj.timeWindow);
    s.TrialLocked = obj.trialLocked;
    s.SetZeroToNan = obj.setZeroToNan;
    s.TrialMarker = obj.trialMarker;
    s.ShowGrid = obj.showGrid;
    s.Palette = obj.palette;
    s.RedrawPeriod = obj.redrawPeriod;
    s.MaxTrialMarkers = obj.maxTrialMarkers;
    s.TraceOrder = names;
    s.SelectionByOperator = obj.selectionByOperator_;
    s.TraceStyle = style;

    setpref(obj.PREF_GROUP, obj.preferenceName_, s);
catch ME
    vprintf(2,'gui.OnlinePlot: failed to save preferences: %s',ME.message)
end
end
