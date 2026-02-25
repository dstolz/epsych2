classdef Parameter_Monitor < handle
%PARAMETER_MONITOR Poll hw.Parameter objects and display their current values.
%
%   Parameter_Monitor attaches to a parent graphics container (e.g., uifigure,
%   uipanel, or figure), creates a small display, and periodically refreshes
%   the display by polling a set of hw.Parameter objects.
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
%     - "text"            : uicontrol text block with one line per parameter
%
%   Construction
%     M = Parameter_Monitor(parent)
%     M = Parameter_Monitor(parent, Parameters)
%     M = Parameter_Monitor(parent, Parameters, pollPeriod=..., type=...)
%
%   Inputs
%     parent      Graphics parent that will contain the display UI.
%                 If empty, no UI or timer is created.
%
%     Parameters  1×N cell array of hw.Parameter objects.
%
%   Name-Value options
%     pollPeriod  Poll period in seconds (fixed-rate timer). Default 1.
%     type        Display type: "table" or "text". Default "table".
%
%   Examples
%     % Show parameters in a uitable, updated at 2 Hz
%     f = uifigure('Name','Params');
%     p = {hw.Parameter(...), hw.Parameter(...)};
%     M = Parameter_Monitor(f, p, pollPeriod=0.5, type="table");
%
%     % Add a parameter at runtime (display updates on next poll)
%     M.add_parameter(hw.Parameter(...));
%
%   Public read-only properties (SetAccess = private)
%     Parent           Parent graphics container.
%     Parameters       Cell array of hw.Parameter objects to monitor.
%     ParameterValues  Current polled values (cellstr), from ValueStr.
%     ParameterNames   Current polled names (cellstr), from Name.
%     pollPeriod       Timer period (seconds).
%     Timer            MATLAB timer object used for polling.
%     handle           Handle to the display UI control (uitable/uicontrol).
%     type             Display type ("text" or "table").
%
%   Public methods
%     add_parameter(param)   Append a hw.Parameter to the monitor list.
%     poll_parameters()     Poll parameters then update the display.
%     update_parameters()   Refresh ParameterNames/ParameterValues.
%     update_gui()          Render current values into the UI element.
%
%   Private methods
%     create_gui()          Create the UI element for the selected type.
%     create_timer()        Create and configure the polling timer.
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
            obj.ParameterValues = {obj.Parameters{:}.ValueStr};
            obj.ParameterNames = {obj.Parameters{:}.Name};    
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
                    textStr = '';
                    for i = 1:length(obj.Parameters)
                        textStr = sprintf('%s%s: %s\n', textStr, obj.Parameters(i).Name, num2str(obj.Parameters(i).Value));
                    end
                    obj.handle = uicontrol(obj.Parent, 'Style', 'text', ...
                        'String', textStr, ...
                        'Tag', 'ParameterTextBox', ...
                        'HorizontalAlignment', 'left', ...
                        'Position', [10, 10, 300, 200]);
                case "table"
                    % Create a table to display parameters
                    data = cell(length(obj.Parameters), 2);
                    for i = 1:length(obj.Parameters)
                        data{i, 1} = obj.Parameters(i).Name;
                        data{i, 2} = obj.Parameters(i).ValueStr;
                    end
                    obj.handle = uitable(obj.Parent, 'Data', data, ...
                        'ColumnName', {'Parameter', 'Value'}, ...
                        'Position', [10, 10, 300, 30*length(obj.Parameters)]);
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
