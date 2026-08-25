function loadPreferences_(obj,hasExplicitSource)
% loadPreferences_(obj,hasExplicitSource)
% Restore the layout and appearance saved for this plot's preference key.
%
% Called from the constructor, after the axes exists (the key is scoped by
% the hosting figure) and before the context menu is built (so the check
% marks are drawn against what was restored).
%
% Two rules decide how far a saved layout may reach:
%
%   * SELECTION. Re-applied only when the operator chose it by hand. A
%     `source` given to the constructor is what a paradigm's build() asked
%     for, and a saved list from a different protocol must not quietly
%     replace it -- hasExplicitSource is how that case is recognized.
%   * ORDER and STYLE. Always re-applied, matched BY TRACE NAME. A name that
%     is no longer plotted is skipped and a trace the saved order never knew
%     keeps its place, so an edited protocol degrades instead of throwing.
%
% Nothing here throws, and nothing it does is written back: suspendSave_ is
% held for the duration, or restoring a preference would immediately re-save
% a half-applied one.
%
% See also: gui.components.OnlinePlot.savePreferences_

try
    pname = obj.preferenceName_;
    if ~ispref(obj.PREF_GROUP,pname), return; end
    s = getpref(obj.PREF_GROUP,pname);
    if ~isstruct(s), return; end

    obj.suspendSave_ = true;
    restore = onCleanup(@() localRelease(obj));

    % --- scalars -------------------------------------------------------
    if isfield(s,'TimeWindow') && numel(s.TimeWindow) == 2
        obj.timeWindow = seconds(s.TimeWindow(:)');
    end
    if isfield(s,'TrialLocked'),  obj.trialLocked  = logical(s.TrialLocked);  end
    if isfield(s,'SetZeroToNan'), obj.setZeroToNan = logical(s.SetZeroToNan); end
    if isfield(s,'TrialMarker'),  obj.trialMarker  = logical(s.TrialMarker);  end
    if isfield(s,'ShowGrid'),     obj.showGrid     = logical(s.ShowGrid);     end
    if isfield(s,'RedrawPeriod'), obj.redrawPeriod = s.RedrawPeriod;          end
    if isfield(s,'MaxTrialMarkers') && s.MaxTrialMarkers >= 1
        obj.maxTrialMarkers = s.MaxTrialMarkers;
    end
    if isfield(s,'Palette') && any(strcmpi(s.Palette,obj.PALETTES))
        obj.palette = char(s.Palette);
    end

    % --- selection, only if the operator made it ------------------------
    if isfield(s,'SelectionByOperator') && s.SelectionByOperator ...
            && isfield(s,'TraceOrder') && ~isempty(s.TraceOrder)
        obj.selectionByOperator_ = true;
        if ~hasExplicitSource || ~isempty(obj.BMFull_)
            % No constructor source to defend, or bitmask mode where the
            % saved list can only ever be a subset of this bank's own bits.
            obj.setWatched(s.TraceOrder, Rebuild=false);
        else
            obj.setWatched(localIntersect(obj,s.TraceOrder), Rebuild=false);
        end
    end

    % --- order, always --------------------------------------------------
    if isfield(s,'TraceOrder') && ~isempty(s.TraceOrder)
        obj.setTraceOrder(s.TraceOrder, Rebuild=false);
    end

    % --- per-trace style, matched by name --------------------------------
    if isfield(s,'TraceStyle') && ~isempty(s.TraceStyle)
        names = obj.traceNames;
        c = obj.lineColors;   % expanded from the palette
        w = obj.lineWidth;
        saved = {s.TraceStyle.Name};
        for i = 1:numel(names)
            k = find(strcmp(saved,names{i}),1);
            if isempty(k), continue; end
            if numel(s.TraceStyle(k).Color) == 3
                c(i,:) = min(max(s.TraceStyle(k).Color(:)',0),1);
            end
            if isscalar(s.TraceStyle(k).Width) && s.TraceStyle(k).Width > 0
                w(i) = s.TraceStyle(k).Width;
            end
        end
        obj.lineColors = c;
        obj.lineWidth = w;
    end

    vprintf(3,'gui.components.OnlinePlot: restored saved layout "%s"',pname)
catch ME
    vprintf(2,'gui.components.OnlinePlot: failed to load preferences: %s',ME.message)
    obj.suspendSave_ = false;
end
end


function localRelease(obj)
if isvalid(obj), obj.suspendSave_ = false; end
end


function names = localIntersect(obj,saved)
% The saved list narrowed to what this protocol actually offers, so a
% remembered selection cannot smuggle in a trace from another rig.
avail = {};
if ~isempty(obj.allParams_), avail = {obj.allParams_.Name}; end
avail = unique([avail, obj.traceNames],'stable');
names = saved(ismember(saved,avail));
end
