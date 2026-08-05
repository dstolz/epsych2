classdef Parameter_Monitor < handle
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
%   Name-Value options (type="table")
%     Columns
%       Additional hw.Parameter properties to show as extra table columns.
%       Any subset of ["Type","Description","UpdateEveryTrial","Expression",
%       "isRandom","Min","Max"]. Default: none.
%
%     PreferenceTag
%       Explicit key used to scope saved sort/column-arrangement preferences
%       for this monitor. Default: derived from the hosting figure's Tag (or
%       Name), so each GUI that uses Parameter_Monitor keeps its own settings.
%
%   Name-Value options (type="graphical")
%     Styles
%       Struct mapping parameter names (Name or validName) to a widget style:
%       "auto", "lamp", "label", or "gauge". Parameters not listed use "auto".
%       Example: Styles=struct('InTrial',"lamp",'RespLatency',"label")
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
%     Parameters      - 1xN hw.Parameter array being monitored.
%     ParameterNames  - String array of parameter names (last poll).
%     ParameterValues - String array of parameter display values (last poll).
%     Columns         - Extra table columns (type="table").
%     pollPeriod      - Timer period in seconds (change via setPollPeriod).
%     Timer           - MATLAB timer object used for polling.
%     handle          - Display UI element (uitable, uicontrol, or the
%                       uigridlayout containing the graphical widgets).
%     type            - Display type ("text", "table", or "graphical").
%     Widgets         - (type="graphical") struct array with one entry per
%                       parameter: Parameter, Style, ValueHandle, LabelHandle
%                       plus internal change-tracking fields. Use this to
%                       tweak individual widgets after construction.
%
%   Public properties
%     SortByColumn  - Table column used to order rows (""=insertion order).
%     SortDirection - "ascend" or "descend".
%
%   Public methods
%     add_parameter(p)      - Append hw.Parameter(s); duplicates are ignored.
%                             Graphical displays rebuild immediately.
%     remove_parameter(p)   - Remove parameter(s) by handle or name.
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

        % homogeneous array of hw.Parameter objects; starts empty
        Parameters (1,:) hw.Parameter = hw.Parameter.empty(1,0)

        ParameterValues % display values of the parameters as of the last poll
        ParameterNames  % names of the parameters being monitored

        % Extra hw.Parameter property columns shown alongside Parameter/Value
        % (type="table" only); see SUPPORTED_COLUMNS for allowed values.
        Columns (1,:) string = string.empty(1,0)

        pollPeriod (1,1) double = 1 % seconds; change via setPollPeriod

        Timer

        handle % display UI element (uitable, uicontrol, or graphical widget grid)
        type (1,1) string = "table" % display type: "text", "table", or "graphical"

        % type="graphical": one entry per parameter with fields Parameter,
        % Style, ValueHandle, LabelHandle, LastValue, LastText, HighlightOn
        Widgets (1,:) struct = struct('Parameter',{},'Style',{},'ValueHandle',{}, ...
            'LabelHandle',{},'LastValue',{},'LastText',{},'HighlightOn',{})

        % graphical display options (set at construction)
        Styles (1,1) struct = struct()
        BooleanStyle (1,1) string = "lamp"
        LayoutColumns (1,1) double = 1
        LabelPosition (1,1) string = "left"
        FontSize = [] % empty = component default
        LampOnColor = [0.18 0.76 0.36]
        LampOffColor = [0.66 0.66 0.66]
        HighlightOnChange (1,1) logical = true
        HighlightColor = [1 0.97 0.65]
    end

    properties
        SortByColumn (1,1) string = "" % column name used to order table rows; "" = insertion order
        SortDirection (1,1) string {mustBeMember(SortDirection,["ascend","descend"])} = "ascend"
    end

    properties (Access = private)
        PreferenceTag_ (1,1) string = "" % explicit preference key; falls back to hosting figure Tag/Name

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
        SUPPORTED_COLUMNS = ["Type","Description","UpdateEveryTrial","Expression","isRandom","Min","Max"]

        % Recognized per-widget styles for type="graphical"
        SUPPORTED_STYLES = ["auto","lamp","label","gauge"]
    end

    properties (Constant, Access = private)
        PREF_GROUP = 'epsych2_gui_Parameter_Monitor' % getpref/setpref group name
    end

    methods

        function obj = Parameter_Monitor(parent,Parameters,options)
            arguments
                parent
                Parameters (1,:) hw.Parameter = hw.Parameter.empty(1,0)
                options.pollPeriod (1,1) double {mustBePositive} = 1
                options.type (1,1) string {mustBeMember(options.type,["text","table","graphical"])} = "table"
                options.Columns (1,:) string {mustBeMember(options.Columns,["Type","Description","UpdateEveryTrial","Expression","isRandom","Min","Max"])} = string.empty(1,0)
                options.PreferenceTag (1,1) string = ""
                options.FontSize double = []
                options.Styles (1,1) struct = struct()
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
                obj.create_gui();
                obj.load_preferences();

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
        end

        function add_parameter(obj, parameter)
            % add_parameter(obj, parameter)
            % Append one or more hw.Parameter objects to the monitored list.
            % Duplicates are skipped. Graphical displays rebuild immediately;
            % table/text displays pick up the change on the next poll.
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

            if added && obj.type == "graphical" && obj.display_is_valid_()
                obj.build_graphical_();
                obj.refresh_after_rebuild_();
            end
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

            if obj.type == "graphical" && obj.display_is_valid_()
                obj.build_graphical_();
                obj.refresh_after_rebuild_();
            end
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
            obj.ParameterNames = string(arrayfun(@(p) p.Name, obj.Parameters,'uni',0));

            % The graphical display reads each parameter once per widget in
            % update_graphical_ (which also refreshes ParameterValues); reading
            % ValueStr here as well would double the hardware I/O per poll.
            if obj.type ~= "graphical"
                obj.ParameterValues = string(arrayfun(@(p) p.ValueStr, obj.Parameters,'uni',0));
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
                    catch ME
                        vprintf(3,'gui.Parameter_Monitor: column sort/rearrange unavailable: %s',ME.message)
                    end

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
                case {"UpdateEveryTrial","isRandom"}
                    fmt = "logical";
                case {"Min","Max"}
                    fmt = "numeric";
                otherwise
                    fmt = "char";
            end
        end

        function vals = column_raw_values_(obj,name)
            % Extract one hw.Parameter property, across all monitored
            % parameters, as a numeric/logical/string vector suitable for
            % both display formatting and sort-key comparison.
            P = obj.Parameters;
            switch name
                case "Type"
                    vals = string({P.Type});
                case "Description"
                    vals = string({P.Description});
                case "UpdateEveryTrial"
                    vals = [P.UpdateEveryTrial];
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

        function load_preferences(obj)
            % Restore saved sort column/direction and column arrangement for
            % this GUI. Column identity (count/order) is fixed at
            % construction, so this can be applied immediately rather than
            % staged until first poll.
            if obj.type ~= "table", return; end
            try
                pname = obj.preference_name_();
                if ispref(obj.PREF_GROUP,pname)
                    s = getpref(obj.PREF_GROUP,pname);
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
                            obj.handle.DisplayColumnOrder = ord;
                        end
                    end
                    vprintf(3,'gui.Parameter_Monitor: loaded saved preferences "%s"',pname)
                end
            catch ME
                vprintf(2,'gui.Parameter_Monitor: failed to load preferences: %s',ME.message)
            end
        end

        function save_preferences(obj)
            % Persist sort column/direction and column arrangement for this GUI.
            if obj.type ~= "table", return; end
            try
                s = struct;
                s.SortByColumn = char(obj.SortByColumn);
                s.SortDirection = char(obj.SortDirection);
                try
                    s.DisplayColumnOrder = obj.handle.DisplayColumnOrder;
                catch
                    s.DisplayColumnOrder = [];
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
