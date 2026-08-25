classdef Parameter_Monitor < gui.PopOut
%PARAMETER_MONITOR Poll hw.Parameter objects and display their current values.
%
%   Parameter_Monitor attaches to a graphics parent (e.g., uifigure, uipanel,
%   uigridlayout, or figure), creates a display, and periodically refreshes
%   that display by polling an array of hw.Parameter objects. It is intended
%   as a drop-in monitoring widget for custom experiment GUIs.
%
%   Display types
%     - "table" (default): uitable with columns {"Parameter","Value"} plus
%       any optional property columns requested via Columns (see below)
%     - "graphical"      : per-parameter widget dashboard. Boolean parameters
%       display as uilamp indicators, bounded numerics can display as gauges,
%       and everything else displays as a bold value label. Widget choice is
%       automatic but can be overridden per parameter via Styles.
%     - "text"           : uicontrol text block with one line per parameter
%
%   All display types refresh efficiently: the current value is compared to
%   the last rendered value and graphics properties are only touched when
%   something actually changed, so a fast pollPeriod does not continuously
%   redraw an unchanging display.
%
%   Graphical display behavior (type="graphical")
%     - Each parameter renders as a (label, widget) pair laid out in a
%       scrollable uigridlayout. LayoutColumns controls how many columns of
%       parameters are used; parameters fill down each column first.
%     - Widget styles: "lamp" (uilamp; on/off from Value ~= 0), "label"
%       (bold uilabel showing ValueStr), "gauge" (semicircular uigauge;
%       requires finite Min/Max), or "auto" (Boolean -> BooleanStyle,
%       everything else -> label).
%     - Value labels briefly highlight when the value changes
%       (HighlightOnChange); the highlight clears on the next poll in which
%       the value is stable.
%     - Tooltips are populated from Parameter.Description automatically.
%     - Requires a uifigure-based parent (uilamp/uilabel components).
%
%   Table display behavior (type="table")
%     - All columns are read-only (non-editable).
%     - Column widths are automatically sized to fit each column's content.
%     - Column headers are user sortable; clicking a header toggles
%       ascend/descend and the chosen sort is reapplied on every poll rather
%       than being reset (uifigure containers only).
%     - Columns are user rearrangeable by dragging headers (uifigure
%       containers only).
%     - The chosen sort column/direction and column arrangement persist
%       across sessions via getpref/setpref, keyed to the hosting GUI figure
%       (or an explicit PreferenceTag).
%
%   Right-click menu (all display types)
%     - "Show Parameter" lists every monitored parameter with a check mark
%       beside the ones currently displayed; clicking one toggles it. Hidden
%       parameters are not polled, so hiding trims hardware I/O as well as
%       clutter. "Show All" restores everything.
%     - "Set Color" (type="graphical" only) offers "On Color..."/"Off
%       Color..." for a lamp widget or "Font Color..." for a label widget,
%       plus "Reset Color" to remove the override. Only enabled when the
%       right-click landed on a lamp or label widget.
%     - "Move Up" / "Move Down" reposition the parameter that was
%       right-clicked. Reordering is a manual arrangement, so it clears any
%       active table column sort.
%     - "Open in Separate Window" repeats the monitor in a window of its
%       own (see gui.PopOut). It is a second monitor with its own timer and
%       its own visibility/order, so hiding a parameter there does not hide
%       it in the GUI, and each shown parameter is polled by both.
%     - Visibility, order, and per-parameter colors persist across sessions
%       alongside the table sort/arrangement preferences, keyed the same way
%       (hosting figure Tag/Name or an explicit PreferenceTag). Parameters
%       are remembered by name, so a saved layout also applies to parameters
%       added later.
%
%   Construction
%     M = gui.Parameter_Monitor(parent)
%     M = gui.Parameter_Monitor(parent, Parameters)
%     M = gui.Parameter_Monitor(parent, Parameters, pollPeriod=..., type=...)
%     M = gui.Parameter_Monitor(parent, Parameters, type="graphical", ...
%             Styles=struct(InTrial="lamp", Level="gauge"), LayoutColumns=2)
%
%   Inputs
%     parent
%       Graphics parent that will contain the display UI. If parent is empty,
%       no UI or timer is created.
%
%     Parameters
%       1xN hw.Parameter array (may be empty). Duplicates are ignored by
%       add_parameter().
%
%   Name-Value options (all display types)
%     pollPeriod
%       Poll period in seconds for the fixed-rate timer. Default 1.
%
%     type
%       Display type: "table", "graphical", or "text". Default "table".
%
%     FontSize
%       Font size applied to the display. Default: component default
%       (12 for type="graphical").
%
%     PreferenceTag
%       Explicit key used to scope saved preferences (parameter visibility
%       and order for every display type; sort column/direction and column
%       arrangement for type="table"). Default: derived from the hosting
%       figure's Tag (or Name), so each GUI that uses Parameter_Monitor
%       keeps its own settings.
%
%   Name-Value options (type="table")
%     Columns
%       Additional hw.Parameter properties to show as extra table columns.
%       Any subset of ["Type","Description","UpdateEveryTrial","SetOnce","Expression",
%       "isRandom","Min","Max"]. Default: none.
%
%   Name-Value options (type="graphical")
%     Styles
%       Struct mapping parameter names (Name or validName) to a widget style:
%       "auto", "lamp", "label", or "gauge". Parameters not listed use "auto".
%       Example: Styles=struct('InTrial',"lamp",'RespLatency',"label")
%
%     Colors
%       Struct mapping parameter names (Name or validName) to a per-parameter
%       color override struct with fields OnColor/OffColor (lamp widgets) or
%       Color (label font color). Parameters not listed use the monitor-wide
%       LampOnColor/LampOffColor or the component's default label color.
%       Example: Colors=struct('InTrial',struct('OnColor',"r"))
%       Overrides can also be set at runtime via set_parameter_color() or the
%       right-click "Set Color" menu, and persist across sessions like the
%       parameter visibility/order preferences.
%
%     BooleanStyle
%       Widget used for Type='Boolean' parameters when their style resolves
%       to "auto": "lamp" (default) or "label".
%
%     LayoutColumns
%       Number of parameter columns in the widget grid. Default 1.
%
%     LabelPosition
%       Where the parameter-name label sits relative to its widget: "left"
%       (default), "above", or "none" (tooltip still names the parameter).
%
%     LampOnColor / LampOffColor
%       Lamp colors for on (Value ~= 0) and off states. RGB triplet or hex
%       string. Defaults: green / gray.
%
%     HighlightOnChange
%       When true (default), value labels flash HighlightColor when the
%       value changes; the flash clears once the value is stable.
%
%     HighlightColor
%       Background color of the change flash. Default: soft yellow.
%
%   Examples
%     % Live table, updated at 2 Hz
%     f = uifigure('Name','Params');
%     M = gui.Parameter_Monitor(f, p, pollPeriod=0.5, type="table");
%
%     % Graphical dashboard: lamps for state monitors, labels elsewhere
%     M = gui.Parameter_Monitor(f, p, type="graphical", LayoutColumns=2, ...
%             Styles=struct('InTrial',"lamp",'Platform',"lamp"));
%
%     % Add a parameter at runtime (display updates immediately)
%     M.add_parameter(newParam);
%
%   Public read-only properties (SetAccess = private)
%     Parent          - Parent graphics container.
%     Parameters      - 1xN hw.Parameter array being monitored, in display
%                       order (hidden parameters included).
%     VisibleParameters - The subset of Parameters currently displayed, in
%                       display order. This is what actually gets polled.
%     ParameterNames  - String array of visible parameter names (last poll).
%     ParameterValues - String array of visible display values (last poll).
%     Columns         - Extra table columns (type="table").
%     pollPeriod      - Timer period in seconds (change via setPollPeriod).
%     Timer           - MATLAB timer object used for polling.
%     handle          - Display UI element (uitable, uicontrol, or the
%                       uigridlayout containing the graphical widgets).
%     type            - Display type ("text", "table", or "graphical").
%     Widgets         - (type="graphical") struct array with one entry per
%                       visible parameter: Parameter, Style, ValueHandle,
%                       LabelHandle, CellHandle plus internal
%                       change-tracking fields. Use this to tweak individual
%                       widgets after construction.
%
%   Public properties
%     SortByColumn  - Table column used to order rows (""=display order).
%     SortDirection - "ascend" or "descend".
%
%   Public methods
%     add_parameter(p)      - Append hw.Parameter(s); duplicates are ignored.
%                             Graphical displays rebuild immediately.
%     remove_parameter(p)   - Remove parameter(s) by handle or name.
%     set_parameter_visible(name,tf) - Show/hide parameter(s) by name.
%     show_all_parameters() - Unhide every monitored parameter.
%     move_parameter(name,delta) - Shift a parameter up (-1) or down (+1)
%                             in the display order.
%     set_parameter_color(name,Name=Value) - Set a per-parameter color
%                             override (type="graphical"): OnColor/OffColor
%                             for a lamp widget, Color for a label widget.
%                             Applied immediately and persisted.
%     clear_parameter_color(name) - Remove a parameter's color override(s),
%                             reverting to the monitor-wide defaults.
%     poll_parameters()     - Poll parameters and refresh the display.
%     update_parameters()   - Refresh ParameterNames/ParameterValues.
%     update_gui()          - Render current values into the display.
%     start() / stop()      - Resume / pause the polling timer.
%     setPollPeriod(sec)    - Change the poll period (restarts the timer).
%
%   Lifecycle
%     - Each monitor owns a uniquely-named timer; multiple monitors can
%       coexist in one MATLAB session.
%     - The monitor deletes itself (stopping its timer) when its display is
%       destroyed, e.g. when the hosting figure closes. Explicitly calling
%       delete(M) stops the timer but leaves the last-rendered display.
%     - Poll errors (e.g. transient hardware read failures) are logged at
%       debug verbosity and do not kill the timer.
%
% Documentation: documentation/gui/Parameter_Monitor.md
% See also gui.Parameter_Control, gui.Parameter_Update, timer, uitable, uilamp

    properties (SetAccess = private, GetAccess = public)
        Parent

        % homogeneous array of hw.Parameter objects, in display order
        % (hidden parameters included); starts empty
        Parameters (1,:) hw.Parameter = hw.Parameter.empty(1,0)

        ParameterValues % display values of the visible parameters as of the last poll
        ParameterNames  % names of the visible parameters being monitored

        % Extra hw.Parameter property columns shown alongside Parameter/Value
        % (type="table" only); see SUPPORTED_COLUMNS for allowed values.
        Columns (1,:) string = string.empty(1,0)

        pollPeriod (1,1) double = 1 % seconds; change via setPollPeriod

        Timer

        handle % display UI element (uitable, uicontrol, or graphical widget grid)

        % Right-click menu shared by every display component. Exposed so a
        % host GUI can append its own uimenu items; the built-in items are
        % rebuilt on each open, so append rather than replace.
        ContextMenu = []
        type (1,1) string = "table" % display type: "text", "table", or "graphical"

        % type="graphical": one entry per visible parameter with fields
        % Parameter, Style, ValueHandle, LabelHandle, CellHandle, LastValue,
        % LastText, HighlightOn, OnColor, OffColor, DefaultColor. CellHandle
        % is the component occupying the grid cell (the same as ValueHandle
        % except for lamps, which are nested in a fixed-size wrapper).
        % OnColor/OffColor are the resolved (override-or-default) lamp
        % colors, cached at build time so per-poll updates need no lookup.
        % DefaultColor is a label widget's original FontColor, captured
        % before any override is applied, so a cleared override can restore it.
        Widgets (1,:) struct = struct('Parameter',{},'Style',{},'ValueHandle',{}, ...
            'LabelHandle',{},'CellHandle',{},'LastValue',{},'LastText',{},'HighlightOn',{}, ...
            'OnColor',{},'OffColor',{},'DefaultColor',{})

        % graphical display options (set at construction)
        Styles (1,1) struct = struct()

        % Per-parameter color overrides (type="graphical"); struct keyed by
        % parameter name (Name or validName) to a struct with fields
        % OnColor/OffColor (lamp) or Color (label). See set_parameter_color.
        Colors (1,1) struct = struct()

        BooleanStyle (1,1) string = "lamp"
        LayoutColumns (1,1) double = 1
        LabelPosition (1,1) string = "left"
        FontSize = [] % empty = component default
        LampOnColor = [0.18 0.76 0.36]
        LampOffColor = [0.66 0.66 0.66]
        HighlightOnChange (1,1) logical = true
        HighlightColor = [1 0.97 0.65]
    end

    properties (Dependent, SetAccess = private)
        % The subset of Parameters currently displayed, in display order.
        % Only these are polled; hidden parameters cost no hardware I/O.
        VisibleParameters
    end

    properties
        SortByColumn (1,1) string = "" % column name used to order table rows; "" = display order
        SortDirection (1,1) string {mustBeMember(SortDirection,["ascend","descend"])} = "ascend"
    end

    properties (Access = private)
        PreferenceTag_ (1,1) string = "" % explicit preference key; falls back to hosting figure Tag/Name

        % Persisted display layout, keyed by parameter FullName (or Name).
        % Kept as names rather than handles so a saved layout also applies to
        % parameters added after the monitor was constructed.
        HiddenKeys_ (1,:) string = string.empty(1,0) % parameters the user hid
        OrderKeys_ (1,:) string = string.empty(1,0)  % preferred display order

        pendingColumnOrder_ = [] % saved uitable DisplayColumnOrder, applied in create_gui
        lastRowOrder_ = []       % visible-parameter index for each rendered table row

        ShowMenuH_ = []      % "Show Parameter" submenu
        ColorMenuH_ = []     % "Set Color" submenu (type="graphical" only)
        MoveUpMenuH_ = []
        MoveDownMenuH_ = []
        menuTargetIdx_ (1,1) double = 0 % Parameters index under the last right-click; 0 = none

        lastTableData_ = {} % cell array rendered into the uitable on the last poll
        lastTextStr_ (1,:) char = '' % string rendered into the text display on the last poll

        % suppress the change flash for the poll immediately after (re)build,
        % otherwise every widget flashes as it goes from empty to its value
        suppressHighlight_ (1,1) logical = true

        destroyListener_ % deletes this monitor when its display is destroyed
    end

    properties (Constant)
        % Allowed values for the Columns option. Keep in sync with the
        % mustBeMember list in the constructor's arguments block (MATLAB
        % argument validators may not reference class properties).
        SUPPORTED_COLUMNS = ["Type","Description","UpdateEveryTrial","SetOnce","Expression","isRandom","Min","Max"]

        % Recognized per-widget styles for type="graphical"
        SUPPORTED_STYLES = ["auto","lamp","label","gauge"]
    end

    properties (Constant, Access = private)
        PREF_GROUP = 'epsych2_gui_Parameter_Monitor' % getpref/setpref group name
    end

    methods (Static)
        function s = getComponentSpec()
            % s = gui.Parameter_Monitor.getComponentSpec()
            % Takes the container FIRST and its parameters second, which the
            % shape says explicitly. Parameter names are resolved against the
            % GUI's parameter set and misses are dropped individually, so a
            % protocol missing one still gets a monitor of the rest.
            % See gui.ComponentSpec.
            s = gui.ComponentSpec();
            s.type        = 'Monitor';
            s.label       = 'Parameter Monitor';
            s.category    = 'Displays';
            s.description = 'Polled read-only display of chosen parameters (table or text)';
            s.shape       = ["parent","arg:Parameters"];
            s.resolve     = "Parameters";
            s.options     = [ ...
                gui.ComponentSpecOption('name','Parameters','inputType','paramlist'), ...
                gui.ComponentSpecOption('name','pollPeriod','inputType','numeric','defaultValue',1), ...
                gui.ComponentSpecOption('name','type','inputType','choice', ...
                    'choices',{{'text','table','graphical'}},'defaultValue','table'), ...
                gui.ComponentSpecOption('name','Columns','inputType','text','isList',true), ...
                gui.ComponentSpecOption('name','PreferenceTag','inputType','text')];
        end
    end

    methods

        function obj = Parameter_Monitor(parent,Parameters,options)
            arguments
                parent
                Parameters (1,:) hw.Parameter = hw.Parameter.empty(1,0)
                options.pollPeriod (1,1) double {mustBePositive} = 1
                options.type (1,1) string {mustBeMember(options.type,["text","table","graphical"])} = "table"
                options.Columns (1,:) string {mustBeMember(options.Columns,["Type","Description","UpdateEveryTrial","SetOnce","Expression","isRandom","Min","Max"])} = string.empty(1,0)
                options.PreferenceTag (1,1) string = ""
                options.FontSize double = []
                options.Styles (1,1) struct = struct()
                options.Colors (1,1) struct = struct()
                options.BooleanStyle (1,1) string {mustBeMember(options.BooleanStyle,["lamp","label"])} = "lamp"
                options.LayoutColumns (1,1) double {mustBeInteger,mustBePositive} = 1
                options.LabelPosition (1,1) string {mustBeMember(options.LabelPosition,["left","above","none"])} = "left"
                options.LampOnColor = [0.18 0.76 0.36]
                options.LampOffColor = [0.66 0.66 0.66]
                options.HighlightOnChange (1,1) logical = true
                options.HighlightColor = [1 0.97 0.65]
            end

            obj.Parent = parent;
            obj.Parameters = Parameters;
            obj.type = options.type;
            obj.Columns = unique(options.Columns,'stable');
            obj.PreferenceTag_ = options.PreferenceTag;
            obj.FontSize = options.FontSize;

            obj.Styles = options.Styles;
            obj.Colors = options.Colors;
            obj.BooleanStyle = options.BooleanStyle;
            obj.LayoutColumns = options.LayoutColumns;
            obj.LabelPosition = options.LabelPosition;
            obj.LampOnColor = options.LampOnColor;
            obj.LampOffColor = options.LampOffColor;
            obj.HighlightOnChange = options.HighlightOnChange;
            obj.HighlightColor = options.HighlightColor;

            if obj.type ~= "table" && ~isempty(obj.Columns)
                vprintf(2,'gui.Parameter_Monitor: Columns option is ignored for type="%s"',obj.type)
            end

            if ~isempty(parent)
                % Preferences first: visibility/order decide what create_gui
                % renders, and the saved column arrangement is staged for it.
                obj.load_preferences();
                obj.create_gui();
                obj.create_context_menu_();

                obj.pollPeriod = options.pollPeriod;
                obj.create_timer();

                % render immediately rather than waiting out the first period
                try
                    obj.poll_parameters();
                catch ME
                    vprintf(2,'gui.Parameter_Monitor: initial poll failed: %s',ME.message)
                end

                obj.Timer.start();
            end
        end

        function delete(obj)
            try
                if ~isempty(obj.Timer) && isvalid(obj.Timer)
                    stop(obj.Timer);
                    delete(obj.Timer);
                end
            catch
            end
            try
                delete(obj.destroyListener_);
            catch
            end
            try
                if ~isempty(obj.ContextMenu) && isvalid(obj.ContextMenu)
                    delete(obj.ContextMenu);
                end
            catch
            end
        end

        function P = get.VisibleParameters(obj)
            P = obj.Parameters(obj.visible_mask_());
        end

        function add_parameter(obj, parameter)
            % add_parameter(obj, parameter)
            % Append one or more hw.Parameter objects to the monitored list.
            % Duplicates are skipped. A saved layout is reapplied afterwards,
            % so a parameter added at runtime lands in its remembered
            % position (and stays hidden if the user had hidden it).
            arguments
                obj
                parameter (1,:) hw.Parameter
            end

            added = false;
            for p = parameter
                if any(obj.Parameters == p)
                    vprintf(1,'gui.Parameter_Monitor: parameter "%s" is already monitored',p.Name)
                    continue
                end
                obj.Parameters(end+1) = p;
                added = true;
            end

            if ~added, return; end
            obj.apply_saved_order_();
            obj.rebuild_display_();
        end

        function remove_parameter(obj, parameter)
            % remove_parameter(obj, parameter)
            % Remove parameter(s) from the monitored list. parameter may be a
            % hw.Parameter array or a string/char array of parameter names.
            if isa(parameter,'hw.Parameter')
                keep = ~ismember(obj.Parameters, parameter);
            else
                names = string({obj.Parameters.Name});
                keep = ~ismember(names, string(parameter));
            end

            if all(keep), return; end
            obj.Parameters = obj.Parameters(keep);
            obj.rebuild_display_();
        end

        function set_parameter_visible(obj, name, tf)
            % set_parameter_visible(obj, name, tf)
            % Show (tf=true) or hide (tf=false) monitored parameter(s) by
            % name. name matches either Name or FullName ("Module.Param"),
            % and may be a string array. Hidden parameters are not polled.
            % The new visibility is persisted for the next session.
            arguments
                obj
                name (1,:) string
                tf (1,1) logical
            end

            keys = obj.parameter_keys_();
            names = obj.parameter_names_();
            changed = false;
            for n = name
                hit = keys(keys == n | names == n);
                if isempty(hit)
                    vprintf(1,'gui.Parameter_Monitor: "%s" is not monitored',n)
                    continue
                end
                for k = hit
                    isHidden = any(obj.HiddenKeys_ == k);
                    if tf && isHidden
                        obj.HiddenKeys_(obj.HiddenKeys_ == k) = [];
                        changed = true;
                    elseif ~tf && ~isHidden
                        obj.HiddenKeys_(end+1) = k;
                        changed = true;
                    end
                end
            end

            if ~changed, return; end
            obj.save_preferences();
            obj.rebuild_display_();
        end

        function show_all_parameters(obj)
            % show_all_parameters(obj) - Unhide every monitored parameter.
            if isempty(obj.HiddenKeys_), return; end
            obj.HiddenKeys_ = string.empty(1,0);
            obj.save_preferences();
            obj.rebuild_display_();
        end

        function move_parameter(obj, name, delta)
            % move_parameter(obj, name, delta)
            % Shift a parameter earlier (delta<0) or later (delta>0) in the
            % display order by swapping it with its neighbour among the
            % *visible* parameters, so hidden entries never absorb a move.
            % The new order is persisted for the next session.
            %
            % A manual arrangement supersedes a table column sort, so any
            % active sort is cleared.
            arguments
                obj
                name (1,1) string
                delta (1,1) double {mustBeInteger}
            end

            if delta == 0, return; end

            keys = obj.parameter_keys_();
            names = obj.parameter_names_();
            idx = find(keys == name | names == name, 1);
            if isempty(idx), return; end

            vis = find(obj.visible_mask_());
            k = find(vis == idx, 1);
            if isempty(k), return; end
            j = k + sign(delta);
            if j < 1 || j > numel(vis), return; end

            swap = 1:numel(obj.Parameters);
            swap([vis(k) vis(j)]) = swap([vis(j) vis(k)]);
            obj.Parameters = obj.Parameters(swap);
            obj.OrderKeys_ = obj.parameter_keys_();
            obj.SortByColumn = "";

            obj.save_preferences();
            obj.rebuild_display_();
        end

        function set_parameter_color(obj, name, options)
            % set_parameter_color(obj, name, Name=Value)
            % Set per-parameter widget color override(s) for type="graphical"
            % (no-op otherwise). name matches Name or FullName. Recognized
            % options: OnColor/OffColor (lamp widgets), Color (label font
            % color) - each an RGB triplet or color name/hex string. Applied
            % to the widget immediately, if currently displayed, and
            % persisted for the next session.
            arguments
                obj
                name (1,1) string
                options.OnColor = []
                options.OffColor = []
                options.Color = []
            end

            p = obj.find_parameter_(name);
            if isempty(p)
                vprintf(1,'gui.Parameter_Monitor: "%s" is not monitored',name)
                return
            end

            if ~isempty(options.OnColor),  obj.apply_color_override_(p,'OnColor',options.OnColor);   end
            if ~isempty(options.OffColor), obj.apply_color_override_(p,'OffColor',options.OffColor); end
            if ~isempty(options.Color),    obj.apply_color_override_(p,'Color',options.Color);       end
        end

        function clear_parameter_color(obj, name)
            % clear_parameter_color(obj, name)
            % Remove a parameter's color override(s), reverting its widget to
            % the monitor-wide default (or, for a label, its original
            % component color). Persisted for the next session.
            arguments
                obj
                name (1,1) string
            end

            p = obj.find_parameter_(name);
            if isempty(p), return; end
            obj.remove_color_override_(p);
        end

        function start(obj)
            % start(obj) - Resume the polling timer.
            if ~isempty(obj.Timer) && isvalid(obj.Timer) && obj.Timer.Running == "off"
                obj.Timer.start();
            end
        end

        function stop(obj)
            % stop(obj) - Pause the polling timer; the display freezes.
            if ~isempty(obj.Timer) && isvalid(obj.Timer)
                obj.Timer.stop();
            end
        end

        function setPollPeriod(obj, seconds)
            % setPollPeriod(obj, seconds) - Change the poll period at runtime.
            arguments
                obj
                seconds (1,1) double {mustBePositive}
            end
            obj.pollPeriod = seconds;
            if isempty(obj.Timer) || ~isvalid(obj.Timer), return; end
            wasRunning = obj.Timer.Running == "on";
            obj.Timer.stop();
            obj.Timer.Period = seconds;
            if wasRunning
                obj.Timer.start();
            end
        end

        function poll_parameters(obj)
            obj.update_parameters();
            obj.update_gui();
        end

        function update_parameters(obj)
            % Hidden parameters are skipped entirely: hiding a parameter
            % removes its per-poll hardware read as well as its display.
            P = obj.VisibleParameters;
            obj.ParameterNames = string(arrayfun(@(p) p.Name, P,'uni',0));

            % The graphical display reads each parameter once per widget in
            % update_graphical_ (which also refreshes ParameterValues); reading
            % ValueStr here as well would double the hardware I/O per poll.
            if obj.type ~= "graphical"
                obj.ParameterValues = string(arrayfun(@(p) p.ValueStr, P,'uni',0));
            end
        end

        function update_gui(obj)
            if ~obj.display_is_valid_(), return; end

            switch obj.type
                case "text"
                    V = obj.ParameterValues;
                    N = obj.ParameterNames;
                    textStr = '';
                    for j = 1:length(V)
                        textStr = sprintf('%s%s: %s\n', textStr, N{j}, V{j});
                    end
                    if ~strcmp(textStr, obj.lastTextStr_)
                        obj.handle.String = textStr;
                        obj.lastTextStr_ = textStr;
                    end

                case "table"
                    obj.update_table_();

                case "graphical"
                    obj.update_graphical_();
            end
        end
    end

    methods (Access = private)
        build_graphical_(obj)   % create the widget grid for type="graphical"
        update_graphical_(obj)  % efficient per-widget refresh for type="graphical"
    end

    methods (Access = protected)

        function c = popOutHostContainer_(obj)
            % Container this monitor was built into (gui.PopOut).
            c = obj.Parent;
        end

        function h = createPopOut_(obj, container)
            % A second monitor over the same hw.Parameter objects, in its
            % own window, with its own timer, visibility, and order. Note it
            % polls the hardware on its own schedule: with the window open,
            % every parameter shown in both places is read twice a period.
            tag = obj.popOutPreferenceTag_();
            hasSaved = ispref(obj.PREF_GROUP,tag);

            h = gui.Parameter_Monitor(container, obj.Parameters, ...
                pollPeriod        = obj.pollPeriod, ...
                type              = obj.type, ...
                Columns           = obj.Columns, ...
                PreferenceTag     = string(tag), ...
                FontSize          = obj.FontSize, ...
                Styles            = obj.Styles, ...
                Colors            = obj.Colors, ...
                BooleanStyle      = obj.BooleanStyle, ...
                LayoutColumns     = obj.LayoutColumns, ...
                LabelPosition     = obj.LabelPosition, ...
                LampOnColor       = obj.LampOnColor, ...
                LampOffColor      = obj.LampOffColor, ...
                HighlightOnChange = obj.HighlightOnChange, ...
                HighlightColor    = obj.HighlightColor);

            if hasSaved, return; end % the constructor already restored its own layout

            % First open: start from what the host is showing.
            h.HiddenKeys_   = obj.HiddenKeys_;
            h.OrderKeys_    = obj.OrderKeys_;
            h.SortByColumn  = obj.SortByColumn;
            h.SortDirection = obj.SortDirection;
            h.apply_saved_order_();
            h.rebuild_display_();
            h.save_preferences();
        end
    end

    methods (Access = private)

        function create_gui(obj)
            switch obj.type
                case "text"
                    % Create a single text area with scrollbar
                    obj.handle = uicontrol(obj.Parent, 'Style', 'text', ...
                        'String', '', ...
                        'Tag', 'ParameterTextBox', ...
                        'HorizontalAlignment', 'left', ...
                        'Units','normalized', ...
                        'Position', [0, 0, 1, 1]);
                    obj.apply_font_size_(obj.handle);

                case "table"
                    % Create a table to display parameters
                    columnNames = obj.column_names_();
                    nCols = numel(columnNames);
                    obj.handle = uitable(obj.Parent, ...
                        'ColumnName', cellstr(columnNames), ...
                        'ColumnFormat', obj.column_formats_(), ...
                        'ColumnEditable', false(1,nCols), ...
                        'Units','normalized', ...
                        'Position', [0, 0, 1, 1]);
                    obj.apply_font_size_(obj.handle);

                    try
                        % Header-click sorting and drag-to-rearrange require a
                        % uifigure-based uitable; degrade gracefully otherwise.
                        obj.handle.ColumnSortable = true;
                        obj.handle.ColumnRearrangeable = true;
                        obj.handle.DisplayDataChangedFcn = @(~,evt) obj.on_display_data_changed(evt);

                        % staged by load_preferences (column identity is fixed
                        % at construction, so this can be applied right away)
                        if ~isempty(obj.pendingColumnOrder_)
                            obj.handle.DisplayColumnOrder = obj.pendingColumnOrder_;
                        end
                    catch ME
                        vprintf(3,'gui.Parameter_Monitor: column sort/rearrange unavailable: %s',ME.message)
                    end
                    obj.pendingColumnOrder_ = [];

                case "graphical"
                    % build_graphical_ arms its own destroy listener
                    obj.build_graphical_();
                    return
            end

            % Stop the polling timer when the hosting GUI is torn down, even
            % if the owner never calls delete() on this monitor.
            obj.destroyListener_ = listener(obj.handle, ...
                'ObjectBeingDestroyed', @(~,~) delete(obj));
        end

        function create_timer(obj)
            % Each instance owns a uniquely-named timer so multiple monitors
            % can coexist (and so cleanup only ever touches our own timer).
            tname = sprintf('Parameter_Monitor_Timer_%d', gui.Parameter_Monitor.next_instance_id_());
            delete(timerfindall("Name", tname));
            obj.Timer = timer("Name", tname, ...
                "ExecutionMode", "fixedRate", ...
                "Period", obj.pollPeriod, ...
                "busyMode", "drop", ...
                "TimerFcn", @(~,~) obj.timer_tick_());
        end

        function timer_tick_(obj)
            % An uncaught error in a TimerFcn stops the timer; a transient
            % hardware read failure should not permanently kill the monitor.
            if ~isvalid(obj), return; end
            try
                obj.poll_parameters();
            catch ME
                vprintf(2,'gui.Parameter_Monitor: poll failed: %s',ME.message)
            end
        end

        function tf = display_is_valid_(obj)
            tf = ~isempty(obj.handle) && isvalid(obj.handle);
        end

        function refresh_after_rebuild_(obj)
            obj.suppressHighlight_ = true;
            try
                obj.poll_parameters();
            catch ME
                vprintf(2,'gui.Parameter_Monitor: refresh failed: %s',ME.message)
            end
        end

        function rebuild_display_(obj)
            % Re-render after the monitored set, its visibility, or its order
            % changed. Graphical displays need their widget grid rebuilt;
            % table/text displays only need their change-detection caches
            % cleared so the next poll is not skipped as "unchanged".
            if ~obj.display_is_valid_(), return; end
            if obj.type == "graphical"
                obj.build_graphical_();
            else
                obj.lastTableData_ = {};
                obj.lastTextStr_ = '';
            end
            obj.refresh_after_rebuild_();
        end

        function tf = visible_mask_(obj)
            tf = true(1,numel(obj.Parameters));
            if isempty(obj.HiddenKeys_) || isempty(obj.Parameters), return; end
            keys = obj.parameter_keys_();
            names = obj.parameter_names_();
            tf = ~(ismember(keys,obj.HiddenKeys_) | ismember(names,obj.HiddenKeys_));
        end

        function keys = parameter_keys_(obj)
            % Persistence key per parameter: FullName ("Module.Param") when
            % available so same-named parameters on different modules stay
            % distinct, otherwise Name.
            P = obj.Parameters;
            keys = strings(1,numel(P));
            for i = 1:numel(P)
                k = "";
                try
                    k = string(P(i).FullName);
                catch
                end
                if strlength(k) == 0
                    k = string(P(i).Name);
                end
                keys(i) = k;
            end
        end

        function names = parameter_names_(obj)
            names = string({obj.Parameters.Name});
            if isempty(names), names = strings(1,0); end
        end

        function apply_saved_order_(obj)
            % Reorder Parameters to match the remembered display order.
            % Parameters with no saved position keep their insertion order
            % after those that have one, so a newly-added parameter appends
            % rather than jumping to the front.
            if isempty(obj.OrderKeys_) || isempty(obj.Parameters), return; end
            keys = obj.parameter_keys_();
            n = numel(keys);
            rank = numel(obj.OrderKeys_) + (1:n);
            [tf,loc] = ismember(keys,obj.OrderKeys_);
            rank(tf) = loc(tf);
            [~,idx] = sort(rank);
            obj.Parameters = obj.Parameters(idx);
        end

        function apply_font_size_(obj, h)
            if isempty(obj.FontSize), return; end
            try
                h.FontSize = obj.FontSize;
            catch ME
                vprintf(3,'gui.Parameter_Monitor: unable to set font size: %s',ME.message)
            end
        end

        function style = resolve_style_(obj, p)
            % Widget style for one parameter: explicit Styles entry (matched
            % against Name or validName), otherwise "auto". Auto maps Boolean
            % parameters to BooleanStyle and everything else to a label.
            style = "auto";
            fn = fieldnames(obj.Styles);
            idx = find(strcmpi(fn, p.validName) | strcmpi(fn, p.Name), 1);
            if ~isempty(idx)
                style = string(obj.Styles.(fn{idx}));
            end

            if ~ismember(style, gui.Parameter_Monitor.SUPPORTED_STYLES)
                vprintf(2,'gui.Parameter_Monitor: unknown style "%s" for "%s"; using "label"',style,p.Name)
                style = "label";
            end

            if style == "auto"
                if isequal(p.Type,'Boolean')
                    style = obj.BooleanStyle;
                else
                    style = "label";
                end
            end

            if style == "gauge" && ~(isfinite(p.Min) && isfinite(p.Max))
                vprintf(2,'gui.Parameter_Monitor: "%s" needs finite Min/Max for a gauge; using "label"',p.Name)
                style = "label";
            end
        end

        function p = find_parameter_(obj, name)
            % Resolve a Name/FullName string to its hw.Parameter handle,
            % across the full monitored set (hidden parameters included).
            % Returns hw.Parameter.empty if not found.
            p = hw.Parameter.empty(1,0);
            keys = obj.parameter_keys_();
            names = obj.parameter_names_();
            idx = find(keys == name | names == name, 1);
            if ~isempty(idx), p = obj.Parameters(idx); end
        end

        function c = resolve_color_(obj, p, field, default)
            % Per-parameter color override lookup (Colors option/runtime
            % overrides), else the supplied default.
            c = default;
            fn = fieldnames(obj.Colors);
            idx = find(strcmpi(fn, p.validName) | strcmpi(fn, p.Name), 1);
            if isempty(idx), return; end
            entry = obj.Colors.(fn{idx});
            if isstruct(entry) && isfield(entry,field) && ~isempty(entry.(field))
                c = entry.(field);
            end
        end

        function key = color_key_(~, p)
            % Struct field name used to key the Colors override map, mirroring
            % resolve_style_'s Name/validName matching.
            key = matlab.lang.makeValidName(char(p.validName));
        end

        function tf = has_color_override_(obj, p)
            key = obj.color_key_(p);
            tf = isfield(obj.Colors,key) && ~isempty(fieldnames(obj.Colors.(key)));
        end

        function c = default_color_for_(obj, p, field)
            % The color a widget would use with no override in place: the
            % monitor-wide lamp colors, or a label's own original FontColor.
            switch field
                case 'OnColor'
                    c = obj.LampOnColor;
                case 'OffColor'
                    c = obj.LampOffColor;
                otherwise
                    c = [0 0 0];
                    idx = find(arrayfun(@(w) isequal(w.Parameter,p), obj.Widgets), 1);
                    if ~isempty(idx) && ~isempty(obj.Widgets(idx).DefaultColor)
                        c = obj.Widgets(idx).DefaultColor;
                    end
            end
        end

        function apply_color_override_(obj, p, field, value)
            % Store one color override field for a parameter, persist it, and
            % push it to the widget immediately if the parameter is displayed.
            key = obj.color_key_(p);
            entry = struct();
            if isfield(obj.Colors,key), entry = obj.Colors.(key); end
            entry.(field) = value;
            obj.Colors.(key) = entry;

            obj.save_preferences();
            obj.apply_widget_color_(p);
        end

        function remove_color_override_(obj, p)
            % Remove all color overrides for a parameter, persist, and revert
            % its widget (if displayed) to the monitor-wide default.
            key = obj.color_key_(p);
            if ~isfield(obj.Colors,key), return; end
            obj.Colors = rmfield(obj.Colors,key);

            obj.save_preferences();
            obj.apply_widget_color_(p);
        end

        function apply_widget_color_(obj, p)
            % Recompute and push resolved color(s) for one parameter's
            % widget, without rebuilding the grid. No-op if the parameter has
            % no widget (hidden, not built yet, or type ~= "graphical").
            if obj.type ~= "graphical" || ~obj.display_is_valid_(), return; end
            W = obj.Widgets;
            idx = find(arrayfun(@(w) isequal(w.Parameter,p), W), 1);
            if isempty(idx), return; end
            h = W(idx).ValueHandle;
            if isempty(h) || ~isvalid(h), return; end

            switch W(idx).Style
                case "lamp"
                    W(idx).OnColor  = obj.resolve_color_(p,'OnColor',obj.LampOnColor);
                    W(idx).OffColor = obj.resolve_color_(p,'OffColor',obj.LampOffColor);
                    if isequal(W(idx).LastValue, true)
                        h.Color = W(idx).OnColor;
                    else
                        h.Color = W(idx).OffColor;
                    end

                case "label"
                    default = W(idx).DefaultColor;
                    if isempty(default), default = [0 0 0]; end
                    h.FontColor = obj.resolve_color_(p,'Color',default);
            end

            obj.Widgets = W;
        end

        function pick_color_(obj, p, field)
            % Open a color picker seeded with the widget's current color for
            % `field`, applying the choice unless the user cancels.
            current = obj.resolve_color_(p, field, obj.default_color_for_(p,field));
            try
                c = uisetcolor(current, sprintf('%s - %s', p.Name, field));
            catch ME
                vprintf(2,'gui.Parameter_Monitor: color picker unavailable: %s',ME.message)
                return
            end
            if isequal(c,0), return; end % user cancelled
            obj.apply_color_override_(p, field, c);
        end

        function update_table_(obj)
            V = obj.ParameterValues;
            N = obj.ParameterNames;
            n = numel(N);
            columnNames = obj.column_names_();

            data = cell(n,numel(columnNames));
            data(:,1) = cellstr(N(:));
            data(:,2) = cellstr(V(:));

            rawExtra = cell(1,numel(obj.Columns));
            for k = 1:numel(obj.Columns)
                rawExtra{k} = obj.column_raw_values_(obj.Columns(k));
                data(:,2+k) = obj.to_cell_column_(rawExtra{k});
            end

            order = obj.resolve_sort_order_(columnNames,N,V,rawExtra);
            rendered = data(order,:);

            % Kept even when the render below is skipped: the context menu
            % maps a right-clicked row back to its visible parameter.
            obj.lastRowOrder_ = order;

            % Reassigning uitable Data forces a redraw even when nothing
            % changed; skip the whole render when the display is current.
            if isequal(rendered, obj.lastTableData_), return; end

            obj.handle.Data = rendered;
            obj.lastTableData_ = rendered;
            obj.update_column_widths_(columnNames,data);
        end

        function names = column_names_(obj)
            % Fixed logical column order: Parameter, Value, then any extra
            % hw.Parameter property columns requested via Columns.
            names = ["Parameter","Value", obj.Columns];
        end

        function fmts = column_formats_(obj)
            % One ColumnFormat entry per column in column_names_() order.
            names = obj.column_names_();
            fmts = cell(1,numel(names));
            for k = 1:numel(names)
                fmts{k} = char(obj.column_format_(names(k)));
            end
        end

        function fmt = column_format_(~,name)
            switch name
                case {"UpdateEveryTrial","SetOnce","isRandom"}
                    fmt = "logical";
                case {"Min","Max"}
                    fmt = "numeric";
                otherwise
                    fmt = "char";
            end
        end

        function vals = column_raw_values_(obj,name)
            % Extract one hw.Parameter property, across all visible
            % parameters, as a numeric/logical/string vector suitable for
            % both display formatting and sort-key comparison.
            P = obj.VisibleParameters;
            switch name
                case "Type"
                    vals = string({P.Type});
                case "Description"
                    vals = string({P.Description});
                case "UpdateEveryTrial"
                    vals = [P.UpdateEveryTrial];
                case "SetOnce"
                    vals = [P.SetOnce];
                case "Expression"
                    vals = string({P.Expression});
                case "isRandom"
                    vals = [P.isRandom];
                case "Min"
                    vals = [P.Min];
                case "Max"
                    vals = [P.Max];
                otherwise
                    vals = strings(1,numel(P));
            end
            vals = vals(:);
        end

        function c = to_cell_column_(~,vals)
            % Convert a raw property column into a uitable Data column,
            % preserving type (logical/numeric/char) so ColumnFormat renders
            % correctly (e.g. checkboxes for logical columns).
            n = numel(vals);
            c = cell(n,1);
            if islogical(vals)
                for i = 1:n
                    c{i} = logical(vals(i));
                end
            elseif isnumeric(vals)
                for i = 1:n
                    c{i} = double(vals(i));
                end
            else
                vals = string(vals);
                for i = 1:n
                    c{i} = char(vals(i));
                end
            end
        end

        function order = resolve_sort_order_(obj,columnNames,N,V,rawExtra)
            % Compute row display order from SortByColumn/SortDirection.
            % Sorting uses raw (unformatted) values so numeric/logical
            % columns sort numerically rather than lexicographically. The
            % table's own Data is reassigned when values change, so the
            % user's chosen sort must be reapplied manually each time rather
            % than relying on the table's transient built-in sort state.
            n = numel(N);
            order = (1:n)';

            name = obj.SortByColumn;
            if strlength(name) == 0, return; end

            idx = find(columnNames == name,1);
            if isempty(idx), return; end

            if idx == 1
                key = N;
            elseif idx == 2
                key = V;
            else
                key = rawExtra{idx-2};
            end

            try
                if isempty(key)
                    order = (1:n)';
                elseif isnumeric(key) || islogical(key)
                    [~,order] = sort(double(key(:)));
                else
                    [~,order] = sort(string(key(:)));
                end
                order = order(:);
                if obj.SortDirection == "descend"
                    order = flipud(order);
                end
            catch ME
                vprintf(2,'gui.Parameter_Monitor: unable to sort by "%s": %s',name,ME.message)
                order = (1:n)';
            end
        end

        function update_column_widths_(obj,columnNames,data)
            % Size each column to fit its header and current cell content
            % (character-count heuristic; uitable has no text-extent API).
            try
                nCols = numel(columnNames);
                widths = zeros(1,nCols);
                for c = 1:nCols
                    len = strlength(columnNames(c));
                    if ~isempty(data)
                        cellLens = cellfun(@(x) strlength(string(x)),data(:,c));
                        len = max([len; cellLens(:)]);
                    end
                    widths(c) = min(max(double(len)*7 + 20,50),400);
                end
                obj.handle.ColumnWidth = num2cell(widths);
            catch ME
                vprintf(3,'gui.Parameter_Monitor: unable to set column widths: %s',ME.message)
            end
        end

        function on_display_data_changed(obj,evt)
            % Handle header-click sorting and drag-to-rearrange interactions
            % so the chosen sort/arrangement can be reapplied on every poll
            % and persisted via getpref/setpref.
            try
                interaction = string(evt.Interaction);
            catch
                return % programmatic data change or unsupported event
            end

            if ~obj.display_is_valid_(), return; end

            switch interaction
                case "sort"
                    try
                        col = evt.InteractionColumn;
                    catch
                        return
                    end
                    if isempty(col), return; end
                    col = col(1);
                    cn = string(obj.handle.ColumnName);
                    if col < 1 || col > numel(cn), return; end

                    clicked = cn(col);
                    if obj.SortByColumn == clicked
                        if obj.SortDirection == "descend"
                            obj.SortDirection = "ascend";
                        else
                            obj.SortDirection = "descend";
                        end
                    else
                        obj.SortByColumn = clicked;
                        obj.SortDirection = "ascend";
                    end

                    obj.save_preferences();
                    obj.update_gui();

                case "rearrange"
                    obj.save_preferences();
            end
        end

        function create_context_menu_(obj)
            % Right-click menu for choosing which parameters are displayed
            % and reordering them. Parented to the hosting figure and shared
            % by every display component, so it survives graphical rebuilds.
            f = ancestor(obj.Parent,'figure');
            if isempty(f) || ~isvalid(f), return; end

            try
                cm = uicontextmenu(f);
                obj.ContextMenu = cm;
                obj.ShowMenuH_ = uimenu(cm,'Text','Show Parameter');
                if obj.type == "graphical"
                    obj.ColorMenuH_ = uimenu(cm,'Text','Set Color','Separator','on');
                end
                obj.MoveUpMenuH_ = uimenu(cm,'Text','Move Up','Separator','on', ...
                    'MenuSelectedFcn',@(~,~) obj.move_menu_target_(-1));
                obj.MoveDownMenuH_ = uimenu(cm,'Text','Move Down', ...
                    'MenuSelectedFcn',@(~,~) obj.move_menu_target_(1));
                obj.addPopOutMenu_(cm);

                % The parameter list and its checked state are rebuilt each
                % time the menu opens, so runtime add/remove stays in sync.
                try
                    cm.ContextMenuOpeningFcn = @(~,evt) obj.on_context_menu_opening_(evt);
                catch
                    cm.Callback = @(~,~) obj.on_context_menu_opening_([]);
                end
            catch ME
                vprintf(3,'gui.Parameter_Monitor: context menu unavailable: %s',ME.message)
                obj.ContextMenu = [];
                return
            end

            obj.attach_context_menu_();
        end

        function attach_context_menu_(obj)
            % Attach the shared context menu to every component the user can
            % right-click. Graphical widgets are recreated on every rebuild,
            % so this is re-run from build_graphical_.
            cm = obj.ContextMenu;
            if isempty(cm) || ~isvalid(cm), return; end

            targets = {obj.handle};
            if obj.type == "graphical"
                W = obj.Widgets;
                targets = [targets, {W.ValueHandle}, {W.LabelHandle}, {W.CellHandle}];
            end

            for k = 1:numel(targets)
                h = targets{k};
                if isempty(h) || ~isgraphics(h) || ~isvalid(h), continue; end
                try
                    h.ContextMenu = cm;
                catch
                    try
                        h.UIContextMenu = cm; % legacy figure components
                    catch ME
                        vprintf(3,'gui.Parameter_Monitor: cannot attach context menu: %s',ME.message)
                    end
                end
            end
        end

        function on_context_menu_opening_(obj,evt)
            obj.menuTargetIdx_ = obj.resolve_menu_target_(evt);
            obj.refresh_show_menu_();
            obj.refresh_color_menu_();

            % Move is only meaningful when the click landed on a parameter
            % and that parameter has somewhere to go.
            up = 'off'; down = 'off';
            if obj.menuTargetIdx_ > 0
                vis = find(obj.visible_mask_());
                k = find(vis == obj.menuTargetIdx_,1);
                if ~isempty(k)
                    if k > 1, up = 'on'; end
                    if k < numel(vis), down = 'on'; end
                end
            end
            obj.MoveUpMenuH_.Enable = up;
            obj.MoveDownMenuH_.Enable = down;
        end

        function refresh_show_menu_(obj)
            % One checkable entry per monitored parameter, in display order,
            % plus a "Show All" escape hatch. Rebuilt on every open because
            % the monitored set can change at runtime.
            m = obj.ShowMenuH_;
            if isempty(m) || ~isvalid(m), return; end
            delete(m.Children);

            keys = obj.parameter_keys_();
            names = obj.parameter_names_();
            vis = obj.visible_mask_();
            for i = 1:numel(keys)
                % Bare Name unless two parameters share it, in which case the
                % module-qualified key is the only way to tell them apart.
                label = names(i);
                if sum(names == names(i)) > 1
                    label = keys(i);
                end
                item = uimenu(m,'Text',char(label), ...
                    'MenuSelectedFcn',@(~,~) obj.set_parameter_visible(keys(i),~vis(i)));
                item.Checked = vis(i);
            end

            uimenu(m,'Text','Show All','Separator',~isempty(keys), ...
                'Enable',~isempty(obj.HiddenKeys_), ...
                'MenuSelectedFcn',@(~,~) obj.show_all_parameters());
        end

        function refresh_color_menu_(obj)
            % Rebuild the "Set Color" submenu for whichever parameter was
            % right-clicked. Only lamp and label widgets support color
            % customization; the submenu is disabled otherwise (no target,
            % gauge, or a non-graphical display type).
            m = obj.ColorMenuH_;
            if isempty(m) || ~isvalid(m), return; end
            delete(m.Children);

            p = hw.Parameter.empty(1,0);
            if obj.menuTargetIdx_ > 0 && obj.menuTargetIdx_ <= numel(obj.Parameters)
                p = obj.Parameters(obj.menuTargetIdx_);
            end

            if isempty(p)
                m.Enable = 'off';
                return
            end

            style = obj.resolve_style_(p);
            switch style
                case "lamp"
                    m.Enable = 'on';
                    uimenu(m,'Text','On Color...', ...
                        'MenuSelectedFcn',@(~,~) obj.pick_color_(p,'OnColor'));
                    uimenu(m,'Text','Off Color...', ...
                        'MenuSelectedFcn',@(~,~) obj.pick_color_(p,'OffColor'));
                    uimenu(m,'Text','Reset Color','Separator','on', ...
                        'Enable',obj.has_color_override_(p), ...
                        'MenuSelectedFcn',@(~,~) obj.remove_color_override_(p));

                case "label"
                    m.Enable = 'on';
                    uimenu(m,'Text','Font Color...', ...
                        'MenuSelectedFcn',@(~,~) obj.pick_color_(p,'Color'));
                    uimenu(m,'Text','Reset Color','Separator','on', ...
                        'Enable',obj.has_color_override_(p), ...
                        'MenuSelectedFcn',@(~,~) obj.remove_color_override_(p));

                otherwise
                    m.Enable = 'off';
            end
        end

        function move_menu_target_(obj,delta)
            if obj.menuTargetIdx_ < 1, return; end
            keys = obj.parameter_keys_();
            if obj.menuTargetIdx_ > numel(keys), return; end
            obj.move_parameter(keys(obj.menuTargetIdx_), delta);
        end

        function idx = resolve_menu_target_(obj,evt)
            % Which parameter was right-clicked, as an index into Parameters.
            % 0 when the click did not land on one (empty table area, the
            % graphical grid background, or a text display, which has no
            % per-parameter hit testing).
            idx = 0;
            if isempty(evt) || ~obj.display_is_valid_(), return; end

            try
                switch obj.type
                    case "table"
                        row = evt.InteractionInformation.Row;
                        if isempty(row), return; end
                        vis = find(obj.visible_mask_());
                        ord = obj.lastRowOrder_;
                        row = row(1);
                        if row < 1 || row > numel(ord), return; end
                        v = ord(row);
                        if v >= 1 && v <= numel(vis)
                            idx = vis(v);
                        end

                    case "graphical"
                        h = evt.ContextObject;
                        for i = 1:numel(obj.Widgets)
                            W = obj.Widgets(i);
                            if isequal(h,W.ValueHandle) || isequal(h,W.LabelHandle) ...
                                    || isequal(h,W.CellHandle)
                                j = find(obj.Parameters == W.Parameter,1);
                                if ~isempty(j), idx = j; end
                                return
                            end
                        end
                end
            catch ME
                vprintf(3,'gui.Parameter_Monitor: cannot resolve right-click target: %s',ME.message)
            end
        end

        function load_preferences(obj)
            % Restore the saved display layout for this GUI: which
            % parameters are shown and in what order (all display types),
            % plus sort column/direction and column arrangement (table).
            % Called before create_gui, so the column arrangement is staged
            % in pendingColumnOrder_ rather than applied here.
            try
                pname = obj.preference_name_();
                if ~ispref(obj.PREF_GROUP,pname), return; end

                s = getpref(obj.PREF_GROUP,pname);
                if isfield(s,'HiddenParameters')
                    obj.HiddenKeys_ = reshape(string(s.HiddenParameters),1,[]);
                end
                if isfield(s,'ParameterOrder')
                    obj.OrderKeys_ = reshape(string(s.ParameterOrder),1,[]);
                    obj.apply_saved_order_();
                end

                if obj.type == "table"
                    if isfield(s,'SortByColumn')
                        obj.SortByColumn = string(s.SortByColumn);
                    end
                    if isfield(s,'SortDirection') && ismember(string(s.SortDirection),["ascend","descend"])
                        obj.SortDirection = string(s.SortDirection);
                    end
                    if isfield(s,'DisplayColumnOrder') && ~isempty(s.DisplayColumnOrder)
                        nCols = numel(obj.column_names_());
                        ord = double(s.DisplayColumnOrder(:)');
                        if isequal(sort(ord),1:nCols)
                            obj.pendingColumnOrder_ = ord;
                        end
                    end
                elseif obj.type == "graphical"
                    if isfield(s,'Colors') && isstruct(s.Colors)
                        obj.Colors = s.Colors;
                    end
                end
                vprintf(3,'gui.Parameter_Monitor: loaded saved preferences "%s"',pname)
            catch ME
                vprintf(2,'gui.Parameter_Monitor: failed to load preferences: %s',ME.message)
            end
        end

        function save_preferences(obj)
            % Persist the display layout for this GUI. Hidden/ordered
            % parameters are stored by key rather than index so the layout
            % survives a change in which parameters the monitor is given.
            try
                s = struct;
                s.HiddenParameters = cellstr(obj.HiddenKeys_);
                s.ParameterOrder = cellstr(obj.OrderKeys_);
                if obj.type == "table"
                    s.SortByColumn = char(obj.SortByColumn);
                    s.SortDirection = char(obj.SortDirection);
                    try
                        s.DisplayColumnOrder = obj.handle.DisplayColumnOrder;
                    catch
                        s.DisplayColumnOrder = [];
                    end
                elseif obj.type == "graphical"
                    s.Colors = obj.Colors;
                end
                setpref(obj.PREF_GROUP,obj.preference_name_(),s);
            catch ME
                vprintf(2,'gui.Parameter_Monitor: failed to save preferences: %s',ME.message)
            end
        end

        function n = preference_name_(obj)
            % Preference key scoped to the hosting GUI: explicit tag, else
            % the ancestor figure Tag, else its Name, else 'default'.
            n = obj.PreferenceTag_;
            if strlength(n) == 0
                try
                    f = ancestor(obj.Parent,'figure');
                    if ~isempty(f) && isvalid(f)
                        if ~isempty(f.Tag)
                            n = string(f.Tag);
                        elseif ~isempty(f.Name)
                            n = string(f.Name);
                        end
                    end
                catch
                end
            end
            if strlength(n) == 0, n = "default"; end
            n = matlab.lang.makeValidName(char(n));
        end

    end

    methods (Static, Access = private)

        function n = next_instance_id_()
            persistent counter
            if isempty(counter), counter = 0; end
            counter = counter + 1;
            n = counter;
        end

    end

end
