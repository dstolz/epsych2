classdef ParameterScatter < handle
    % obj = gui.ParameterScatter(source, container)
    % Generic trial-parameter scatter plot for custom behavior GUIs.
    %
    % Compares any two per-trial parameters recorded in the current
    % experiment. X, Y, and an optional color-by parameter are chosen from
    % dropdowns at any time and the plot updates immediately; a NewData
    % listener refreshes the plot after every completed trial. "Trial
    % Number" (chronological DATA index) is always offered as a parameter.
    % Parameters flagged Visible=false on their hw.Parameter are excluded
    % from the selectable lists.
    %
    % Display behavior:
    %   - Right-click the axes for basic aesthetics: marker style, size,
    %     opacity, color, colormap (for color-by mode), log scales, grid.
    %   - Parameter selections and aesthetics persist across sessions via
    %     getpref/setpref, keyed to the hosting GUI figure (or an explicit
    %     PreferenceTag).
    %   - The plot can be hosted in any graphics container (uifigure,
    %     legacy figure, panel, tab, or a uigridlayout cell) and adapts to
    %     resizing. uifigure-family containers get a uigridlayout/uidropdown
    %     control row; legacy figures get equivalent uicontrol popupmenus.
    %
    % Properties:
    %   XParameter, YParameter - Selected DATA field names (or 'Trial Number')
    %   ColorParameter         - Third parameter for marker color, or '(none)'
    %   Marker, MarkerSize, MarkerColor, MarkerAlpha - Marker aesthetics
    %   ColormapName           - Colormap used when colorizing by a parameter
    %   LogX, LogY, ShowGrid   - Axes aesthetics
    %   BoxID                  - Restrict NewData updates to these boxes; empty accepts all
    %
    % Methods:
    %   ParameterScatter - Construct the plot UI and attach the NewData listener
    %   update           - Refresh parameter lists and redraw from current data
    %   delete           - Cleanup listener and context menu resources
    %
    % Examples:
    %   % In a custom behavior GUI (online; pObj is e.g. psychophysics.Detection):
    %   obj.hScatter = gui.ParameterScatter(pObj, parentPanel);
    %
    %   % Directly from the runtime:
    %   obj.hScatter = gui.ParameterScatter(RUNTIME, parentPanel);
    %
    %   % Offline, from saved trial data:
    %   S = gui.ParameterScatter(DATA, uifigure);
    %
    % See also: documentation/gui/gui_ParameterScatter.md, gui.History

    properties
        XParameter     (1,:) char = ''        % DATA field for the x axis; empty = auto
        YParameter     (1,:) char = ''        % DATA field for the y axis; empty = auto
        ColorParameter (1,:) char = '(none)'  % DATA field for marker color, or '(none)'

        Marker      (1,:) char {mustBeMember(Marker,{'o','s','d','^','v','p','h'})} = 'o'
        MarkerSize  (1,1) double {mustBePositive,mustBeFinite} = 48
        MarkerColor (1,3) double {mustBeNonnegative,mustBeLessThanOrEqual(MarkerColor,1)} = [0 .4 .8]
        MarkerAlpha (1,1) double {mustBeNonnegative,mustBeLessThanOrEqual(MarkerAlpha,1)} = 0.6
        ColormapName (1,:) char = 'parula'    % colormap used in color-by mode

        LogX     (1,1) logical = false
        LogY     (1,1) logical = false
        ShowGrid (1,1) logical = true

        BoxID (1,:) double = [] % restrict NewData updates to these boxes; empty accepts all
    end

    properties (SetAccess = private)
        AxesH                        % Axes hosting the scatter
        ScatterH = []                % Scatter graphics object
        ColorbarH = []               % Colorbar shown in color-by mode
        ContainerH                   % Hosting container supplied at construction
        DropdownX                    % X parameter selector
        DropdownY                    % Y parameter selector
        DropdownC                    % Color-by parameter selector

        hl_NewData = event.listener.empty % Listener for NewData events
    end

    properties (Access = private)
        DATA_ = []                   % Cached per-trial data struct array
        Runtime_ = []                % epsych.Runtime used to resolve invisible parameters
        PanelH_ = []                 % Wrapper panel (legacy-figure hosting only)
        LabelX_ = []                 % X control label (legacy-figure hosting only)
        LabelY_ = []                 % Y control label (legacy-figure hosting only)
        LabelC_ = []                 % Color control label (legacy-figure hosting only)
        ContextMenuH_ = []           % Right-click aesthetics menu
        PendingSelections_ = []      % Saved selections awaiting first data update
        PreferenceTag_ char = ''     % Optional explicit preference key
        isWeb_ (1,1) logical = true  % True when hosted in uifigure-family graphics
        suspend_ (1,1) logical = false % Guard against redraw recursion during batch updates
        invisibleResolved_ (1,1) logical = false
        InvisibleNames_ (1,:) cell = {} % validNames of invisible parameters
    end

    properties (Constant, Access = private)
        TRIAL_NUMBER_LABEL = 'Trial Number' % synthetic parameter: chronological DATA index
        NONE_LABEL = '(none)'               % ColorParameter entry meaning "flat marker color"
        PREF_GROUP = 'epsych2_gui_ParameterScatter'
        VALID_MARKERS = {'o','s','d','^','v','p','h'}
        VALID_COLORMAPS = {'parula','turbo','jet','hot','cool','copper','bone'}
        MARKER_SIZES = [12 24 36 48 72 96 144]
        MARKER_ALPHAS = [0.25 0.5 0.75 1]
    end

    methods
        function obj = ParameterScatter(source, container, options)
            % obj = gui.ParameterScatter(source, container)
            % obj = gui.ParameterScatter(source, container, PreferenceTag=tag)
            % Initialize the scatter plot UI and attach the data listener.
            %
            % Parameters:
            %   source - Data source: a psychophysics object (updates via its
            %       Helper NewData event), an epsych.Runtime (updates via
            %       RUNTIME.HELPER), or a DATA struct array for offline use.
            %   container - Figure, panel, tab, or layout host. If empty,
            %       creates a uifigure.
            %   options.PreferenceTag - Optional key for saved preferences;
            %       defaults to the hosting figure Tag (or Name) so each GUI
            %       keeps its own settings.
            %   options.BoxID - Restrict NewData updates to these boxes.
            %   options.XParameter, options.YParameter, options.ColorParameter -
            %       Initial selections; override saved preferences when given.
            %
            % Returns:
            %   obj - gui.ParameterScatter object.
            arguments
                source = []
                container = []
                options.PreferenceTag {mustBeTextScalar} = ''
                options.BoxID (1,:) double = []
                options.XParameter {mustBeTextScalar} = ''
                options.YParameter {mustBeTextScalar} = ''
                options.ColorParameter {mustBeTextScalar} = ''
            end

            if isempty(container)
                container = uifigure('Name','Parameter Scatter');
            end
            obj.ContainerH = container;
            obj.PreferenceTag_ = char(options.PreferenceTag);
            obj.BoxID = options.BoxID;

            obj.build_(container);
            obj.loadPreferences_;

            % Explicit constructor selections take precedence over saved ones
            if ~isempty(options.XParameter)
                obj.XParameter = char(options.XParameter);
                obj.clearPendingSelection_('XParameter');
            end
            if ~isempty(options.YParameter)
                obj.YParameter = char(options.YParameter);
                obj.clearPendingSelection_('YParameter');
            end
            if ~isempty(options.ColorParameter)
                obj.ColorParameter = char(options.ColorParameter);
                obj.clearPendingSelection_('ColorParameter');
            end

            obj.attachSource_(source);
            obj.update;
        end

        function delete(obj)
            % delete(obj)
            % Release the NewData listener and context menu resources.
            if ~isempty(obj.hl_NewData)
                listeners = obj.hl_NewData(isvalid(obj.hl_NewData));
                if ~isempty(listeners), delete(listeners); end
                obj.hl_NewData = event.listener.empty;
            end
            if ~isempty(obj.ContextMenuH_) && isvalid(obj.ContextMenuH_)
                delete(obj.ContextMenuH_);
            end
        end

        function update(obj,~,~)
            % update(obj, ~, ~)
            % Refresh the selectable parameter lists and redraw the scatter.
            if isempty(obj.AxesH) || ~isvalid(obj.AxesH), return; end
            vprintf(4,'Updating ParameterScatter')

            D = obj.currentData_;
            avail = obj.availableParameters_(D);
            obj.applyPendingSelections_(avail);

            obj.suspend_ = true;
            if ~ismember(obj.XParameter,avail)
                obj.XParameter = obj.TRIAL_NUMBER_LABEL;
            end
            if ~ismember(obj.YParameter,avail)
                others = setdiff(avail,{obj.TRIAL_NUMBER_LABEL},'stable');
                if isempty(others)
                    obj.YParameter = obj.TRIAL_NUMBER_LABEL;
                else
                    obj.YParameter = others{1};
                end
            end
            if ~ismember(obj.ColorParameter,[{obj.NONE_LABEL} avail])
                obj.ColorParameter = obj.NONE_LABEL;
            end
            obj.setDropdownItems_(obj.DropdownX,avail,obj.XParameter);
            obj.setDropdownItems_(obj.DropdownY,avail,obj.YParameter);
            obj.setDropdownItems_(obj.DropdownC,[{obj.NONE_LABEL} avail],obj.ColorParameter);
            obj.suspend_ = false;

            obj.redraw_(D);
        end

        function onNewData(obj,~,event)
            % onNewData(obj, ~, event)
            % NewData listener callback: cache the trial data and refresh.
            %
            % Parameters:
            %   event - Event payload with event.Data.DATA (epsych.TrialsData).
            try
                if ~isempty(obj.BoxID) && ~isempty(event.BoxID) ...
                        && ~ismember(event.BoxID,obj.BoxID)
                    return
                end
            catch
                % Event without box information; accept it.
            end
            obj.DATA_ = event.Data.DATA;
            obj.update;
        end

        function onSelectionChanged(obj,~,~)
            % onSelectionChanged(obj, ~, ~)
            % Dropdown callback: apply the selections, persist them, redraw.
            obj.suspend_ = true;
            obj.XParameter = obj.getDropdownValue_(obj.DropdownX);
            obj.YParameter = obj.getDropdownValue_(obj.DropdownY);
            obj.ColorParameter = obj.getDropdownValue_(obj.DropdownC);
            obj.suspend_ = false;
            obj.savePreferences_;
            obj.redraw_(obj.currentData_);
        end

        function set.XParameter(obj,v)
            obj.XParameter = char(string(v));
            obj.selectionChanged_;
        end

        function set.YParameter(obj,v)
            obj.YParameter = char(string(v));
            obj.selectionChanged_;
        end

        function set.ColorParameter(obj,v)
            v = char(string(v));
            if isempty(v), v = obj.NONE_LABEL; end
            obj.ColorParameter = v;
            obj.selectionChanged_;
        end
    end

    methods (Access = private)
        function attachSource_(obj,source)
            % Resolve the data source and attach the NewData listener.
            if isstruct(source)
                obj.DATA_ = source; % offline data; no listener
            elseif isa(source,'epsych.Runtime') || (isobject(source) && isprop(source,'HELPER'))
                obj.Runtime_ = source;
                obj.hl_NewData = listener(source.HELPER,'NewData',@obj.onNewData);
                try
                    obj.DATA_ = source.TRIALS(1).DATA;
                catch
                    % No trial data yet; first NewData event populates it.
                end
            elseif epsych.Helper.valid_psych_obj(source)
                obj.Runtime_ = source.RUNTIME;
                obj.hl_NewData = listener(source.Helper,'NewData',@obj.onNewData);
                obj.DATA_ = source.DATA;
            else
                error('gui:ParameterScatter:InvalidSource', ...
                    'source must be a psychophysics object, an epsych.Runtime, or a DATA struct array');
            end
        end

        function build_(obj,container)
            % Create the control row and axes inside the container.
            try
                g = uigridlayout(container,[2 1]);
                g.RowHeight = {'fit','1x'};
                g.ColumnWidth = {'1x'};
                g.Padding = [2 2 2 2];
                g.RowSpacing = 2;

                ctrl = uigridlayout(g,[1 6]);
                ctrl.ColumnWidth = {'fit','1x','fit','1x','fit','1x'};
                ctrl.RowHeight = {'fit'};
                ctrl.Padding = [0 0 0 0];
                ctrl.ColumnSpacing = 4;

                uilabel(ctrl,'Text','X:');
                obj.DropdownX = uidropdown(ctrl,'Items',{obj.TRIAL_NUMBER_LABEL}, ...
                    'ValueChangedFcn',@obj.onSelectionChanged);
                uilabel(ctrl,'Text','Y:');
                obj.DropdownY = uidropdown(ctrl,'Items',{obj.TRIAL_NUMBER_LABEL}, ...
                    'ValueChangedFcn',@obj.onSelectionChanged);
                uilabel(ctrl,'Text','Color:');
                obj.DropdownC = uidropdown(ctrl,'Items',{obj.NONE_LABEL}, ...
                    'ValueChangedFcn',@obj.onSelectionChanged);

                obj.AxesH = uiaxes(g);
                obj.isWeb_ = true;
            catch
                % Legacy figure hosting: uigridlayout is unavailable, so lay
                % out uicontrols in a borderless wrapper panel we own.
                obj.isWeb_ = false;
                p = uipanel(container,'Units','normalized','Position',[0 0 1 1], ...
                    'BorderType','none');
                obj.PanelH_ = p;
                obj.LabelX_ = uicontrol(p,'Style','text','String','X:', ...
                    'Units','pixels','HorizontalAlignment','right');
                obj.DropdownX = uicontrol(p,'Style','popupmenu', ...
                    'String',{obj.TRIAL_NUMBER_LABEL},'Units','pixels', ...
                    'Callback',@obj.onSelectionChanged);
                obj.LabelY_ = uicontrol(p,'Style','text','String','Y:', ...
                    'Units','pixels','HorizontalAlignment','right');
                obj.DropdownY = uicontrol(p,'Style','popupmenu', ...
                    'String',{obj.TRIAL_NUMBER_LABEL},'Units','pixels', ...
                    'Callback',@obj.onSelectionChanged);
                obj.LabelC_ = uicontrol(p,'Style','text','String','Color:', ...
                    'Units','pixels','HorizontalAlignment','right');
                obj.DropdownC = uicontrol(p,'Style','popupmenu', ...
                    'String',{obj.NONE_LABEL},'Units','pixels', ...
                    'Callback',@obj.onSelectionChanged);
                obj.AxesH = axes('Parent',p,'Units','pixels');
                p.SizeChangedFcn = @(~,~) obj.classicResize_;
                obj.classicResize_;
            end
            box(obj.AxesH,'on');
            obj.buildContextMenu_;
        end

        function classicResize_(obj)
            % Keep a fixed-height control strip above the axes (legacy hosting).
            if isempty(obj.PanelH_) || ~isvalid(obj.PanelH_), return; end
            pos = getpixelposition(obj.PanelH_);
            w = max(pos(3),200);
            h = max(pos(4),120);
            pad = 4; ctrlH = 22;
            labW = [20 20 40];
            ddW = max(50,floor((w - sum(labW) - 7*pad)/3));
            y = h - ctrlH - pad;
            x = pad;
            obj.LabelX_.Position   = [x y-3 labW(1) ctrlH]; x = x + labW(1) + pad;
            obj.DropdownX.Position = [x y ddW ctrlH];       x = x + ddW + pad;
            obj.LabelY_.Position   = [x y-3 labW(2) ctrlH]; x = x + labW(2) + pad;
            obj.DropdownY.Position = [x y ddW ctrlH];       x = x + ddW + pad;
            obj.LabelC_.Position   = [x y-3 labW(3) ctrlH]; x = x + labW(3) + pad;
            obj.DropdownC.Position = [x y ddW ctrlH];
            obj.AxesH.OuterPosition = [pad pad w-2*pad max(20,y-2*pad)];
        end

        function selectionChanged_(obj)
            % Programmatic selection change: revalidate lists and redraw.
            if obj.suspend_ || isempty(obj.DropdownX), return; end
            obj.update;
        end

        function D = currentData_(obj)
            % Cached DATA with the preallocated-but-empty first trial guard.
            D = obj.DATA_;
            if ~isempty(D) && isfield(D,'TrialID') && isempty(D(1).TrialID)
                D = D([]);
            end
        end

        function avail = availableParameters_(obj,D)
            % Scalar numeric DATA fields eligible for plotting, excluding
            % invisible parameters, plus the synthetic Trial Number entry.
            avail = {obj.TRIAL_NUMBER_LABEL};
            if isempty(D), return; end
            fn = fieldnames(D);
            keep = false(size(fn));
            for k = 1:numel(fn)
                v = D(1).(fn{k});
                if isstruct(v) && isfield(v,'Value'), v = v.Value; end
                keep(k) = (isnumeric(v) || islogical(v)) && isscalar(v);
            end
            fn = fn(keep);
            fn = setdiff(fn,obj.invisibleParameterNames_,'stable');
            avail = [avail sort(fn(:))'];
        end

        function names = invisibleParameterNames_(obj)
            % validNames of parameters flagged Visible=false, resolved once
            % from the runtime; empty when no runtime is available.
            if obj.invisibleResolved_
                names = obj.InvisibleNames_;
                return
            end
            names = {};
            R = obj.Runtime_;
            if isempty(R)
                obj.invisibleResolved_ = true;
            else
                try
                    P = R.all_parameters(includeInvisible=true,includeTriggers=true,Access='All');
                    if ~isempty(P)
                        names = {P(~[P.Visible]).validName};
                    end
                    obj.invisibleResolved_ = true;
                catch ME
                    vprintf(3,'gui.ParameterScatter: unable to resolve invisible parameters: %s',ME.message)
                end
            end
            obj.InvisibleNames_ = names;
        end

        function v = parameterValues_(obj,D,name)
            % Per-trial numeric values for a parameter; NaN where unavailable.
            n = numel(D);
            if strcmp(name,obj.TRIAL_NUMBER_LABEL)
                v = 1:n;
                return
            end
            v = nan(1,n);
            if isempty(D) || ~isfield(D,name), return; end
            for k = 1:n
                val = D(k).(name);
                if isstruct(val) && isfield(val,'Value'), val = val.Value; end
                if (isnumeric(val) || islogical(val)) && isscalar(val)
                    v(k) = double(val);
                end
            end
        end

        function redraw_(obj,D)
            % Redraw the scatter from the current selections and aesthetics.
            ax = obj.AxesH;
            if isempty(ax) || ~isvalid(ax), return; end

            sh = obj.ScatterH;
            if isempty(sh) || ~isvalid(sh)
                sh = scatter(ax,nan,nan,obj.MarkerSize,'filled');
                obj.ScatterH = sh;
                box(ax,'on');
            end

            x = obj.parameterValues_(D,obj.XParameter);
            y = obj.parameterValues_(D,obj.YParameter);

            if strcmp(obj.ColorParameter,obj.NONE_LABEL)
                set(sh,'XData',x,'YData',y,'CData',obj.MarkerColor);
                if ~isempty(obj.ColorbarH) && isvalid(obj.ColorbarH)
                    colorbar(ax,'off');
                    obj.ColorbarH = [];
                end
            else
                c = obj.parameterValues_(D,obj.ColorParameter);
                x(isnan(c)) = nan; % colormapped markers need a color value
                set(sh,'XData',x,'YData',y,'CData',c(:));
                try
                    colormap(ax,obj.ColormapName);
                catch
                    vprintf(2,'gui.ParameterScatter: unknown colormap "%s"',obj.ColormapName)
                end
                cf = c(isfinite(c));
                if ~isempty(cf)
                    if min(cf) == max(cf)
                        ax.CLim = min(cf) + [-1 1];
                    else
                        ax.CLim = [min(cf) max(cf)];
                    end
                end
                if isempty(obj.ColorbarH) || ~isvalid(obj.ColorbarH)
                    obj.ColorbarH = colorbar(ax);
                end
                obj.ColorbarH.Label.String = obj.ColorParameter;
                obj.ColorbarH.Label.Interpreter = 'none';
            end

            set(sh,'Marker',obj.Marker,'SizeData',obj.MarkerSize, ...
                'MarkerFaceAlpha',obj.MarkerAlpha,'MarkerEdgeAlpha',obj.MarkerAlpha);

            if obj.LogX, ax.XScale = 'log'; else, ax.XScale = 'linear'; end
            if obj.LogY, ax.YScale = 'log'; else, ax.YScale = 'linear'; end
            if obj.ShowGrid, grid(ax,'on'); else, grid(ax,'off'); end

            xlabel(ax,obj.XParameter,'Interpreter','none');
            ylabel(ax,obj.YParameter,'Interpreter','none');
        end

        % ------------------------------------------------------------------
        % Dropdown abstraction: uidropdown (web) vs uicontrol popupmenu (legacy)

        function setDropdownItems_(obj,h,items,value)
            % Replace a dropdown's item list, preserving the selection.
            items = cellstr(items);
            items = items(:)';
            if isempty(items), items = {''}; end
            if obj.isWeb_
                h.Items = items;
                if ismember(value,items)
                    h.Value = value;
                else
                    h.Value = items{1};
                end
            else
                idx = find(strcmp(items,value),1);
                if isempty(idx), idx = 1; end
                h.Value = 1; % keep Value in range while the list changes
                h.String = items;
                h.Value = idx;
            end
        end

        function v = getDropdownValue_(obj,h)
            % Currently selected dropdown item as char.
            if obj.isWeb_
                v = char(h.Value);
            else
                s = cellstr(h.String);
                v = s{h.Value};
            end
        end

        % ------------------------------------------------------------------
        % Aesthetics context menu

        function buildContextMenu_(obj)
            % Create the right-click menu for basic plot aesthetics.
            fig = ancestor(obj.AxesH,'figure');
            if isempty(fig), return; end
            try
                cm = uicontextmenu(fig);
                obj.ContextMenuH_ = cm;

                m = uimenu(cm,'Text','Marker');
                for mk = obj.VALID_MARKERS
                    uimenu(m,'Text',mk{1},'Tag',['aes|Marker|' mk{1}], ...
                        'MenuSelectedFcn',@(~,~) obj.setAesthetic_('Marker',mk{1}));
                end
                m = uimenu(cm,'Text','Marker Size');
                for sz = obj.MARKER_SIZES
                    uimenu(m,'Text',num2str(sz),'Tag',['aes|MarkerSize|' num2str(sz)], ...
                        'MenuSelectedFcn',@(~,~) obj.setAesthetic_('MarkerSize',sz));
                end
                m = uimenu(cm,'Text','Opacity');
                for a = obj.MARKER_ALPHAS
                    uimenu(m,'Text',sprintf('%d%%',round(a*100)),'Tag',['aes|MarkerAlpha|' num2str(a)], ...
                        'MenuSelectedFcn',@(~,~) obj.setAesthetic_('MarkerAlpha',a));
                end
                uimenu(cm,'Text','Marker Color ...','MenuSelectedFcn',@(~,~) obj.pickMarkerColor_);
                m = uimenu(cm,'Text','Colormap');
                for c = obj.VALID_COLORMAPS
                    uimenu(m,'Text',c{1},'Tag',['aes|ColormapName|' c{1}], ...
                        'MenuSelectedFcn',@(~,~) obj.setAesthetic_('ColormapName',c{1}));
                end
                uimenu(cm,'Text','Log X','Separator','on','Tag','tgl|LogX', ...
                    'MenuSelectedFcn',@(~,~) obj.toggleAesthetic_('LogX'));
                uimenu(cm,'Text','Log Y','Tag','tgl|LogY', ...
                    'MenuSelectedFcn',@(~,~) obj.toggleAesthetic_('LogY'));
                uimenu(cm,'Text','Grid','Tag','tgl|ShowGrid', ...
                    'MenuSelectedFcn',@(~,~) obj.toggleAesthetic_('ShowGrid'));

                obj.AxesH.ContextMenu = cm;
                obj.refreshMenuChecks_;
            catch ME
                vprintf(3,'gui.ParameterScatter: context menu unavailable: %s',ME.message)
            end
        end

        function setAesthetic_(obj,prop,val)
            % Apply an aesthetics menu choice, persist it, and redraw.
            obj.(prop) = val;
            obj.savePreferences_;
            obj.refreshMenuChecks_;
            obj.redraw_(obj.currentData_);
        end

        function toggleAesthetic_(obj,prop)
            obj.setAesthetic_(prop,~obj.(prop));
        end

        function pickMarkerColor_(obj)
            c = uisetcolor(obj.MarkerColor,'Marker Color');
            if isscalar(c), return; end % user cancelled
            obj.setAesthetic_('MarkerColor',c);
        end

        function refreshMenuChecks_(obj)
            % Sync menu item check marks with the current property values.
            cm = obj.ContextMenuH_;
            if isempty(cm) || ~isvalid(cm), return; end
            items = findall(cm,'Type','uimenu');
            for k = 1:numel(items)
                t = items(k).Tag;
                if startsWith(t,'aes|')
                    p = strsplit(t,'|');
                    cur = obj.(p{2});
                    if isnumeric(cur), cur = num2str(cur); end
                    items(k).Checked = strcmp(cur,p{3});
                elseif startsWith(t,'tgl|')
                    p = strsplit(t,'|');
                    items(k).Checked = logical(obj.(p{2}));
                end
            end
        end

        % ------------------------------------------------------------------
        % Preference persistence

        function loadPreferences_(obj)
            % Apply saved aesthetics immediately; stage parameter selections
            % until the first update with data so they can be validated
            % against the available parameter list.
            try
                pname = obj.preferenceName_;
                if ~ispref(obj.PREF_GROUP,pname), return; end
                s = getpref(obj.PREF_GROUP,pname);
                aes = {'Marker','MarkerSize','MarkerColor','MarkerAlpha', ...
                    'ColormapName','LogX','LogY','ShowGrid'};
                for k = 1:numel(aes)
                    if isfield(s,aes{k})
                        obj.(aes{k}) = s.(aes{k});
                    end
                end
                obj.PendingSelections_ = s;
                obj.refreshMenuChecks_;
                vprintf(3,'gui.ParameterScatter: loaded saved preferences "%s"',pname)
            catch ME
                vprintf(2,'gui.ParameterScatter: failed to load preferences: %s',ME.message)
            end
        end

        function applyPendingSelections_(obj,avail)
            % Apply staged parameter selections once real data are available.
            if isempty(obj.PendingSelections_) || numel(avail) < 2, return; end
            s = obj.PendingSelections_;
            obj.PendingSelections_ = [];
            obj.suspend_ = true;
            if isfield(s,'XParameter') && ismember(s.XParameter,avail)
                obj.XParameter = s.XParameter;
            end
            if isfield(s,'YParameter') && ismember(s.YParameter,avail)
                obj.YParameter = s.YParameter;
            end
            if isfield(s,'ColorParameter') && ismember(s.ColorParameter,[{obj.NONE_LABEL} avail])
                obj.ColorParameter = s.ColorParameter;
            end
            obj.suspend_ = false;
        end

        function clearPendingSelection_(obj,fieldName)
            % Drop one staged selection (constructor override wins over prefs).
            if ~isempty(obj.PendingSelections_) && isfield(obj.PendingSelections_,fieldName)
                obj.PendingSelections_ = rmfield(obj.PendingSelections_,fieldName);
            end
        end

        function savePreferences_(obj)
            % Persist selections and aesthetics for this GUI.
            try
                s = struct;
                s.XParameter = obj.XParameter;
                s.YParameter = obj.YParameter;
                s.ColorParameter = obj.ColorParameter;
                s.Marker = obj.Marker;
                s.MarkerSize = obj.MarkerSize;
                s.MarkerColor = obj.MarkerColor;
                s.MarkerAlpha = obj.MarkerAlpha;
                s.ColormapName = obj.ColormapName;
                s.LogX = obj.LogX;
                s.LogY = obj.LogY;
                s.ShowGrid = obj.ShowGrid;
                setpref(obj.PREF_GROUP,obj.preferenceName_,s);
            catch ME
                vprintf(2,'gui.ParameterScatter: failed to save preferences: %s',ME.message)
            end
        end

        function n = preferenceName_(obj)
            % Preference key scoped to the hosting GUI: explicit tag, else
            % the ancestor figure Tag, else its Name, else 'default'.
            n = obj.PreferenceTag_;
            if isempty(n)
                try
                    f = ancestor(obj.ContainerH,'figure');
                    if ~isempty(f) && isvalid(f)
                        if ~isempty(f.Tag)
                            n = f.Tag;
                        elseif ~isempty(f.Name)
                            n = f.Name;
                        end
                    end
                catch
                end
            end
            if isempty(n), n = 'default'; end
            n = matlab.lang.makeValidName(n);
        end
    end
end
