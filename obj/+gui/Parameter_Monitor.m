classdef Parameter_Monitor < handle
%PARAMETER_MONITOR Poll hw.Parameter objects and display their current values.
%
%   Parameter_Monitor attaches to a graphics parent (e.g., uifigure, uipanel,
%   uigridlayout, or figure), creates a small display, and periodically
%   refreshes that display by polling an array of hw.Parameter objects.
%
%   The monitor reads each parameter's:
%     - Name     (display label)
%     - ValueStr (display value)
%
%   A MATLAB timer (Name="Parameter_Monitor_Timer") runs in fixed-rate mode
%   and calls poll_parameters() at the configured pollPeriod.
%
%   Display types
%     - "table" (default): uitable with columns {"Parameter","Value"} plus
%       any optional property columns requested via Columns (see below)
%     - "text"           : uicontrol text block with one line per parameter
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
%     M = gui.Parameter_Monitor(parent, Parameters, Columns=["Type","Min","Max"])
%
%   Inputs
%     parent
%       Graphics parent that will contain the display UI. If parent is empty,
%       no UI or timer is created.
%
%     Parameters
%       1×N hw.Parameter array (may be empty). Duplicates are ignored by
%       add_parameter().
%
%   Name-Value options
%     pollPeriod
%       Poll period in seconds for the fixed-rate timer. Default 1.
%
%     type
%       Display type: "table" or "text". Default "table".
%
%     Columns
%       Additional hw.Parameter properties to show as extra table columns
%       (type="table" only). Any subset of ["Type","Description",
%       "UpdateEveryTrial","Expression","isRandom","Min","Max"]. Default: none.
%
%     PreferenceTag
%       Explicit key used to scope saved sort/column-arrangement preferences
%       for this monitor. Default: derived from the hosting figure's Tag (or
%       Name), so each GUI that uses Parameter_Monitor keeps its own settings.
%
%   Examples
%     % Show parameters in a uitable, updated at 2 Hz
%     f = uifigure('Name','Params');
%     p = [hw.Parameter(...), hw.Parameter(...)];
%     M = Parameter_Monitor(f, p, pollPeriod=0.5, type="table");
%
%     % Include extra columns describing each parameter
%     M = Parameter_Monitor(f, p, Columns=["Type","Min","Max","isRandom"]);
%
%     % Add a parameter at runtime (display updates on next poll)
%     M.add_parameter(hw.Parameter(...));
%
%   Public read-only properties (SetAccess = private)
%     Parent
%       Parent graphics container.
%
%     Parameters
%       1×N hw.Parameter array being monitored.
%
%     ParameterNames
%       Cell array of parameter names (from hw.Parameter.Name).
%
%     ParameterValues
%       Cell array of parameter display strings (from hw.Parameter.ValueStr).
%
%     Columns
%       Extra hw.Parameter property columns shown alongside Parameter/Value.
%
%     pollPeriod
%       Timer period in seconds.
%
%     Timer
%       MATLAB timer object used for polling.
%
%     handle
%       Handle to the display UI element (uitable or uicontrol).
%
%     type
%       Display type ("text" or "table").
%
%   Public properties
%     SortByColumn
%       Name of the column currently used to order table rows (""=insertion
%       order).
%
%     SortDirection
%       "ascend" or "descend".
%
%   Public methods
%     add_parameter(parameter)
%       Append a hw.Parameter to the monitored list. If the parameter is
%       already present, it is ignored with a warning.
%
%     poll_parameters()
%       Poll parameters (update_parameters) then refresh the UI (update_gui).
%
%     update_parameters()
%       Refresh ParameterNames/ParameterValues from the current Parameters.
%
%     update_gui()
%       Render ParameterNames/ParameterValues into the current UI element.
%
%   Private methods
%     create_gui()
%       Create the UI element according to type.
%
%     create_timer()
%       Create/configure the polling timer and delete any existing timer with
%       the same name.
%
%   Notes
%     - The constructor validates that the supplied Parameters are hw.Parameter
%       objects (and accepts empty).
%     - The timer BusyMode is set to "drop".
%     - Sorting, rearranging, and preference persistence require a
%       uifigure-hosted table; legacy figure-based tables degrade gracefully
%       to a plain (non-sortable, non-rearrangeable) table.
%
%   See also timer, uitable, uicontrol

    properties (SetAccess = private,GetAccess = public)
        Parent

        % homogeneous array of hw.Parameter objects; starts empty
        Parameters (1,:) hw.Parameter = hw.Parameter.empty(1,0)

        ParameterValues % current values of the parameters being monitored
        ParameterNames % names of the parameters being monitored

        % Extra hw.Parameter property columns shown alongside Parameter/Value
        % (type="table" only); see SUPPORTED_COLUMNS for allowed values.
        Columns (1,:) string = string.empty(1,0)

        pollPeriod (1,1) double = 1 % seconds

        Timer

        handle % handle to the GUI element (e.g. text box, table, etc.) that displays the parameters
        type (1,1) string = "text" % type of display, e.g. "text", "table", etc.
    end

    properties
        SortByColumn (1,1) string = "" % column name used to order table rows; "" = insertion order
        SortDirection (1,1) string {mustBeMember(SortDirection,["ascend","descend"])} = "ascend"
    end

    properties (Access = private)
        PreferenceTag_ (1,1) string = "" % explicit preference key; falls back to hosting figure Tag/Name
    end

    properties (Constant)
        % Allowed values for the Columns option. Keep in sync with the
        % mustBeMember list in the constructor's arguments block (MATLAB
        % argument validators may not reference class properties).
        SUPPORTED_COLUMNS = ["Type","Description","UpdateEveryTrial","Expression","isRandom","Min","Max"]
    end

    properties (Constant, Access = private)
        PREF_GROUP = 'epsych2_gui_Parameter_Monitor' % getpref/setpref group name
    end

    methods

        function obj = Parameter_Monitor(parent,Parameters,options)
            arguments
                parent (1,1)
                Parameters (1,:) hw.Parameter = hw.Parameter.empty(1,0)
                options.pollPeriod (1,1) double = 1
                options.type (1,1) string {mustBeMember(options.type,["text","table"])} = "table"
                options.Columns (1,:) string {mustBeMember(options.Columns,["Type","Description","UpdateEveryTrial","Expression","isRandom","Min","Max"])} = string.empty(1,0)
                options.PreferenceTag (1,1) string = ""
            end

            % Ensure the supplied list is an array of hw.Parameter objects
            if ~isempty(Parameters) && ~all(arrayfun(@(p) isa(p,'hw.Parameter'), Parameters))
                error('Parameters must be an array of hw.Parameter objects.');
            end

            obj.Parent = parent;
            obj.Parameters = Parameters;        % already validated as hw.Parameter array
            obj.type = options.type;
            obj.Columns = unique(options.Columns,'stable');
            obj.PreferenceTag_ = options.PreferenceTag;

            if obj.type == "text" && ~isempty(obj.Columns)
                vprintf(2,'gui.Parameter_Monitor: Columns option is ignored for type="text"')
            end

            if ~isempty(parent)
                obj.create_gui();
                obj.load_preferences();

                obj.pollPeriod = options.pollPeriod;
                obj.create_timer();
                obj.Timer.start();
            end
        end

        function delete(obj)
            try
                obj.Timer.stop();
                delete(obj.Timer);
            end
        end

        function add_parameter(obj, parameter)
            if ~isa(parameter, 'hw.Parameter')
                error('Only hw.Parameter objects can be added to the monitor.');
            end

            % ignore duplicates
            if any(obj.Parameters == parameter)
                warning('Parameter already exists in the monitor.');
                return
            end

            obj.Parameters(end+1) = parameter;  % append to homogeneous array
        end


        function poll_parameters(obj)
            obj.update_parameters();
            obj.update_gui();
        end

        function update_parameters(obj)
            obj.ParameterValues = string(arrayfun(@(p) p.ValueStr, obj.Parameters,'uni',0));
            obj.ParameterNames  = string(arrayfun(@(p) p.Name, obj.Parameters,'uni',0));
        end

        function update_gui(obj)
            V = obj.ParameterValues;
            N = obj.ParameterNames;

            % Update the display for each parameter
            switch obj.type
                case "text"
                    textStr = '';
                    for j = 1:length(V)
                        textStr = sprintf('%s%s: %s\n', textStr, N{j}, V{j});
                    end
                    obj.handle.String = textStr;

                case "table"
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

                    obj.handle.Data = data(order,:);
                    obj.update_column_widths_(columnNames,data);
            end

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

                    try
                        % Header-click sorting and drag-to-rearrange require a
                        % uifigure-based uitable; degrade gracefully otherwise.
                        obj.handle.ColumnSortable = true;
                        obj.handle.ColumnRearrangeable = true;
                        obj.handle.DisplayDataChangedFcn = @(~,evt) obj.on_display_data_changed(evt);
                    catch ME
                        vprintf(3,'gui.Parameter_Monitor: column sort/rearrange unavailable: %s',ME.message)
                    end
            end


        end

        function create_timer(obj)
            delete(timerfindall("Name", "Parameter_Monitor_Timer"));
            obj.Timer = timer("Name", "Parameter_Monitor_Timer", ...
                "ExecutionMode", "fixedRate", ...
                "Period", obj.pollPeriod, ...
                "busyMode", "drop", ...
                "TimerFcn", @(~,~) obj.poll_parameters());
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
            % table's own Data is reassigned every poll, so the user's
            % chosen sort must be reapplied manually each time rather than
            % relying on the table's transient built-in sort state.
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

            if isempty(obj.handle) || ~isvalid(obj.handle), return; end

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

end
