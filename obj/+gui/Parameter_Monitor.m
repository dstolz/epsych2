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
%     - "table" (default): uitable with columns {"Parameter","Value"}
%     - "text"           : uicontrol text block with one line per parameter
%
%   Construction
%     M = gui.Parameter_Monitor(parent)
%     M = gui.Parameter_Monitor(parent, Parameters)
%     M = gui.Parameter_Monitor(parent, Parameters, pollPeriod=..., type=...)
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
%   Examples
%     % Show parameters in a uitable, updated at 2 Hz
%     f = uifigure('Name','Params');
%     p = [hw.Parameter(...), hw.Parameter(...)];
%     M = Parameter_Monitor(f, p, pollPeriod=0.5, type="table");
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
%
%   See also timer, uitable, uicontrol

    properties (SetAccess = private,GetAccess = public)
        Parent

        % homogeneous array of hw.Parameter objects; starts empty
        Parameters (1,:) hw.Parameter = hw.Parameter.empty(1,0)

        ParameterValues % current values of the parameters being monitored
        ParameterNames % names of the parameters being monitored

        pollPeriod (1,1) double = 1 % seconds

        Timer

        handle % handle to the GUI element (e.g. text box, table, etc.) that displays the parameters
        type (1,1) string = "text" % type of display, e.g. "text", "table", etc.
    end

    methods

        function obj = Parameter_Monitor(parent,Parameters,options)
            arguments
                parent (1,1)
                Parameters (1,:) hw.Parameter = hw.Parameter.empty(1,0)
                options.pollPeriod (1,1) double = 1
                options.type (1,1) string {mustBeMember(options.type,["text","table"])} = "table"
            end

            % Ensure the supplied list is an array of hw.Parameter objects
            if ~isempty(Parameters) && ~all(arrayfun(@(p) isa(p,'hw.Parameter'), Parameters))
                error('Parameters must be an array of hw.Parameter objects.');
            end

            obj.Parent = parent;
            obj.Parameters = Parameters;        % already validated as hw.Parameter array
            obj.type = options.type;


            if ~isempty(parent)
                obj.create_gui();

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
                    data = [N(:), V(:)];
                    obj.handle.Data = data;
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
                        'Position', [10, 10, 300, 200]);
                case "table"
                    % Create a table to display parameters
                    pos = obj.Parent.Position;
                    obj.handle = uitable(obj.Parent, ...
                        'ColumnName', {'Parameter', 'Value'}, ...
                        'ColumnEditable',[false false], ...
                        'Position', [1, 1, pos([3 4])-10]);
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

    end

end
