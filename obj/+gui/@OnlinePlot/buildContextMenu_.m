function buildContextMenu_(obj)
% buildContextMenu_(obj)
% Build the axes right-click menu: session controls, trace selection and
% order, and the aesthetics the operator is allowed to change.
%
% Every item routes through the same public setter a script would call
% (setWatched, setTraceOrder, or an ordinary property), then through
% savePreferences_, so nothing the operator does here is unreachable from
% code and nothing is forgotten at the end of the session.
%
% Tags follow two conventions the check-mark refresh reads back:
%   'aes|<Property>|<value>' - a radio choice among fixed values
%   'tgl|<Property>'         - a logical toggle
%
% See also: gui.OnlinePlot.refreshMenuChecks_, gui.OnlinePlot.savePreferences_

fig = ancestor(obj.hax,'figure');
if isempty(fig) || ~isvalid(fig), return; end

try
    c = uicontextmenu(fig);
    obj.ContextMenuH_ = c;

    % --- session controls (historic tags: stay_on_top and plot_type read them)
    if obj.ownsFigure_
        % Only for a window this plot made. In a pop-out gui.PopOut adds its
        % own "Keep Window on Top" below, and two of them would be absurd; in
        % an embedded axes the window belongs to the behavior GUI, so neither
        % appears.
        uimenu(c,'Tag','uic_stayOnTop','Label','Keep Window on Top', ...
            'MenuSelectedFcn',@obj.stay_on_top);
    end
    uimenu(c,'Tag','uic_pause','Label','Pause ||','MenuSelectedFcn',@obj.pause);
    uimenu(c,'Tag','uic_plotType','Label','Set Plot to Trial-Locked', ...
        'MenuSelectedFcn',{@obj.plot_type,true});
    uimenu(c,'Tag','uic_timeWindow', ...
        'Label',sprintf('Time Window = [%.1f %.1f] seconds',obj.timeWindow2number), ...
        'MenuSelectedFcn',@obj.update_window);

    % --- which traces, and in what order
    uimenu(c,'Tag','uic_selectTraces','Label','Select Traces...','Separator','on', ...
        'MenuSelectedFcn',@(~,~) obj.selectTraces);
    uimenu(c,'Tag','uic_reorderTraces','Label','Reorder Traces...', ...
        'MenuSelectedFcn',@(~,~) obj.reorderTraces);

    % --- appearance
    m = uimenu(c,'Text','Line Width','Separator','on');
    for w = obj.LINE_WIDTHS
        uimenu(m,'Text',num2str(w),'Tag',sprintf('aes|lineWidth|%g',w), ...
            'MenuSelectedFcn',@(~,~) obj.setAesthetic_('lineWidth',w));
    end

    m = uimenu(c,'Text','Palette');
    for k = 1:numel(obj.PALETTES)
        p = obj.PALETTES{k};
        uimenu(m,'Text',p,'Tag',['aes|palette|' p], ...
            'MenuSelectedFcn',@(~,~) obj.setAesthetic_('palette',p));
    end

    % One entry per trace, so a single trace can be recoloured without
    % disturbing the rest. Rebuilt whenever the trace list changes.
    uimenu(c,'Tag','uic_traceColors','Text','Trace Colour');

    m = uimenu(c,'Text','Redraw Rate');
    for r = obj.REDRAW_RATES
        uimenu(m,'Text',sprintf('%g Hz',r),'Tag',sprintf('aes|redrawPeriod|%g',1/r), ...
            'MenuSelectedFcn',@(~,~) obj.setAesthetic_('redrawPeriod',1/r));
    end

    uimenu(c,'Text','Grid','Separator','on','Tag','tgl|showGrid', ...
        'MenuSelectedFcn',@(~,~) obj.toggleAesthetic_('showGrid'));
    uimenu(c,'Text','Blank Zeros','Tag','tgl|setZeroToNan', ...
        'MenuSelectedFcn',@(~,~) obj.toggleAesthetic_('setZeroToNan'));
    uimenu(c,'Text','Trial Markers','Tag','tgl|trialMarker', ...
        'MenuSelectedFcn',@(~,~) obj.toggleAesthetic_('trialMarker'));
    uimenu(c,'Text','Reset Appearance','Tag','uic_resetStyle', ...
        'MenuSelectedFcn',@(~,~) obj.resetAppearance_);

    obj.addPopOutMenu_(c);

    obj.hax.ContextMenu = c; % ContextMenu, not the deprecated UIContextMenu alias
    obj.rebuildTraceColorMenu_;
    obj.refreshMenuChecks_;
catch ME
    vprintf(3,'gui.OnlinePlot: context menu unavailable: %s',ME.message)
end
end
