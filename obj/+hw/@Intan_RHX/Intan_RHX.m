classdef Intan_RHX < hw.Interface

    % obj = hw.Intan_RHX(host, port, Name=Value)
    % Hardware interface for Intan RHX software via TCP command interface.
    %
    % Communicates with the Intan RHX software TCP command server
    % (default localhost:5000) to control run mode and read/write named
    % parameters using the RHX command grammar.
    %
    % Parameters
    %   host    - RHX server host name or IP address. Default: '127.0.0.1'
    %   port    - RHX command server TCP port. Default: 5000
    %
    % Name=Value options
    %   Timeout (double) - TCP read/write timeout in seconds. Default: 5
    %   Connect (logical) - Connect on construction. Default: true
    %
    % Properties
    %   Host        - RHX server host.
    %   Port        - RHX command server port.
    %   Timeout     - TCP operation timeout (seconds).
    %   IsConnected - True when TCP connection is open.
    %   Module      - Single hw.Module representing the RHX device.
    %   mode        - Current hw.DeviceState.
    %
    % Methods
    %   connect, close_interface - Connection management.
    %   get_parameter, set_parameter - Named parameter I/O via RHX commands.
    %   trigger - Issue manualstimtriggerpulse for a parameter whose
    %             UserData.TriggerKey contains the key (f1-f8).
    %   setModules - Replace Module array while offline.
    %
    % Usage
    %   % Connect to default localhost server
    %   iface = hw.Intan_RHX();
    %
    %   % Offline construction for serialization round-trip
    %   iface = hw.Intan_RHX('localhost', 5000, Connect=false);
    %
    % See also: documentation/hw/hw_Intan_RHX.md, documentation/hw/hw_Interface.md, hw.Module, hw.Parameter


    properties
        IsConnected = false              % true when TCP connection is open
        Host (1,:) char = '127.0.0.1'   % RHX server hostname or IP
        Port (1,1) double = 5000         % RHX command server TCP port (default 5000)
        Timeout (1,1) double = 5         % TCP read/write timeout in seconds
        HW = []                          % Reserved; unused by Intan_RHX (required by hw.Parameter)
    end

    properties (SetObservable, AbortSet)
        mode  % Current device run state (hw.DeviceState)
    end

    properties (SetAccess = protected)
        Module   % hw.Module array
    end

    properties (Constant)
        Type = "Intan_RHX"
    end

    properties (Access = private)
        client_  % tcpclient handle, or []
        modeCache_ (1,1) hw.DeviceState = hw.DeviceState.Idle  % last known mode when offline
    end


    methods

        function obj = Intan_RHX(host, port, options)
            % obj = hw.Intan_RHX(host, port, Name=Value)
            % Construct an Intan_RHX interface and optionally connect.
            %
            % Parameters
            %   host    - RHX server hostname or IP. Default '127.0.0.1'
            %   port    - TCP port. Default 5000
            % Name=Value
            %   Timeout (double) - TCP timeout (s). Default 5
            %   Connect (logical) - Connect on construction. Default true
            arguments
                host (1,:) char = '127.0.0.1'
                port (1,1) double = 5000
                options.Timeout (1,1) double = 5
                options.Connect (1,1) logical = true
            end
            obj.Host = host;
            obj.Port = port;
            obj.Timeout = options.Timeout;
            obj.Module = hw.Module.empty(1, 0);
            if options.Connect
                obj.connect();
            end
        end

        function delete(obj)
            obj.close_interface();
        end

        function connect(obj)
            % connect(obj)
            % Open TCP connection to RHX server and initialize modules.
            % Sets IsConnected=true on success.
            if obj.IsConnected
                return
            end
            obj.setup_interface();
        end

        function set.mode(obj, newMode)
            obj.applyMode_(newMode);
        end

        function m = get.mode(obj)
            m = obj.queryMode_();
        end

        function setModules(obj, modules)
            % setModules(obj, modules)
            % Replace Module array. Only permitted while offline.
            %
            % Parameters
            %   modules - hw.Module array to assign
            if obj.IsConnected
                error('hw:Intan_RHX:ConnectedModuleEdit', ...
                    'Modules can only be reassigned while the interface is offline.');
            end
            obj.Module = modules;
        end

        function value = get_parameter(obj, name, options)
            % value = get_parameter(obj, name)
            % value = get_parameter(obj, name, ReturnRaw=true)
            % Read current value for one or more named RHX parameters via TCP.
            %
            % Parameters
            %   name       - Parameter name string, cell array of names, or
            %                hw.Parameter handle / array.
            %   ReturnRaw  - When true, return the raw RHX response string(s)
            %                instead of the parsed numeric/char value.
            %
            % Returns
            %   value - Value or cell array of values matching name order.
            arguments
                obj
                name
                options.ReturnRaw (1,1) logical = false
            end

            if isa(name, 'hw.Parameter')
                params = name;
            else
                params = obj.find_parameter(name);
            end

            if ~obj.IsConnected || isempty(obj.client_)
                value = cell(1, numel(params));
                if numel(value) == 1
                    value = value{1};
                end
                return
            end

            value = cell(1, numel(params));

            for i = 1:numel(params)
                cmd = sprintf('get %s', lower(params(i).Name));
                resp = obj.sendCommand_(cmd);
                if options.ReturnRaw
                    value{i} = resp;
                else
                    value{i} = obj.parseReturnValue_(resp);
                end
            end

            % Return scalar directly when only one parameter
            if numel(value) == 1
                value = value{1};
            end
        end

        function result = set_parameter(obj, name, value)
            % result = set_parameter(obj, name, value)
            % Write value(s) to one or more named RHX parameters via TCP.
            %
            % Parameters
            %   name  - Parameter name string, cell array, or hw.Parameter handle/array.
            %   value - Scalar or array matching numel(name). Numeric values
            %           are formatted as strings; char/string values are sent as-is.
            %
            % Returns
            %   result - Logical array; true per parameter on success.
            if isa(name, 'hw.Parameter')
                params = name;
            else
                params = obj.find_parameter(name);
            end

            if ~obj.IsConnected || isempty(obj.client_)
                result = true(1, numel(params));
                return
            end

            if isscalar(value) && numel(params) > 1
                value = repmat({value}, 1, numel(params));
            elseif ~iscell(value)
                value = num2cell(value);
            end

            result = false(1, numel(params));
            for i = 1:numel(params)
                v = value{i};
                if isnumeric(v)
                    valStr = num2str(v);
                else
                    valStr = char(v);
                end
                cmd = sprintf('set %s %s', lower(params(i).Name), valStr);
                resp = obj.sendCommand_(cmd);
                result(i) = obj.isSuccessResponse_(resp);
                if result(i)
                    vprintf(3, 'Intan_RHX: set %s = %s', params(i).Name, valStr);
                else
                    vprintf(0, 1, 'Intan_RHX: failed to set %s — %s', params(i).Name, resp);
                end
            end
        end

        function t = trigger(obj, name)
            % t = trigger(obj, name)
            % t = trigger(obj, P)
            % Issue a manualstimtriggerpulse for the given parameter.
            %
            % The trigger key (f1–f8) must be stored in P.UserData.TriggerKey.
            % If not set, defaults to 'f1'.
            %
            % Parameters
            %   name - Parameter name string or hw.Parameter handle.
            %
            % Returns
            %   t - datetime of trigger delivery.
            if isa(name, 'hw.Parameter')
                P = name;
            else
                P = obj.find_parameter(name);
            end

            t = datetime('now');

            if ~obj.IsConnected || isempty(obj.client_)
                return
            end

            key = 'f1';
            if isstruct(P.UserData) && isfield(P.UserData, 'TriggerKey') ...
                    && ~isempty(P.UserData.TriggerKey)
                key = lower(char(P.UserData.TriggerKey));
            end

            cmd = sprintf('execute manualstimtriggerpulse %s', key);
            resp = obj.sendCommand_(cmd);
            if ~obj.isSuccessResponse_(resp)
                vprintf(0, 1, 'Intan_RHX: trigger %s failed — %s', key, resp);
            end
        end

    end  % public methods


    methods (Static)

        function spec = getCreationSpec()
            % spec = hw.Intan_RHX.getCreationSpec()
            % Return hw.InterfaceSpec describing construction options for Intan_RHX.
            spec = hw.InterfaceSpec( ...
                char(hw.Intan_RHX.Type), ...
                'Intan RHX', ...
                'Connect to Intan RHX software via its TCP command interface.', ...
                [hw.InterfaceSpecOption( ...
                    'name', 'host', ...
                    'label', 'Host', ...
                    'defaultValue', '127.0.0.1', ...
                    'required', false, ...
                    'inputType', 'text', ...
                    'choices', {}, ...
                    'isList', false, ...
                    'scope', 'interface', ...
                    'allowScalarExpansion', false, ...
                    'controlType', 'text', ...
                    'getFile', false, ...
                    'getFolder', false, ...
                    'fileFilter', {{'*.*', 'All Files (*.*)'}}, ...
                    'fileDialogTitle', '', ...
                    'description', 'Hostname or IP address of the Intan RHX command server.'), ...
                hw.InterfaceSpecOption( ...
                    'name', 'port', ...
                    'label', 'Port', ...
                    'defaultValue', 5000, ...
                    'required', false, ...
                    'inputType', 'numeric', ...
                    'choices', {}, ...
                    'isList', false, ...
                    'scope', 'interface', ...
                    'allowScalarExpansion', false, ...
                    'controlType', 'numeric', ...
                    'getFile', false, ...
                    'getFolder', false, ...
                    'fileFilter', {{'*.*', 'All Files (*.*)'}}, ...
                    'fileDialogTitle', '', ...
                    'description', 'TCP port for the Intan RHX command server (default 5000).')], ...
                @(opts) hw.Intan_RHX(char(opts.host), double(opts.port)));
        end

    end  % Static methods


    methods (Access = protected)

        function setup_interface(obj)
            % setup_interface(obj)
            % Open TCP connection to RHX server, create the RHX module, and
            % sync the current run mode.
            obj.client_ = tcpclient(obj.Host, obj.Port, 'Timeout', obj.Timeout);
            configureTerminator(obj.client_, 'LF');

            % Create single module representing the RHX device
            if isempty(obj.Module)
                obj.Module = hw.Module(obj, 'RHX', 'RHX', uint8(1));
            end

            obj.IsConnected = true;

            % Sync cached mode from hardware
            obj.modeCache_ = obj.queryMode_();
        end

        function close_interface(obj)
            % close_interface(obj)
            % Close TCP connection and release resources.
            if ~isempty(obj.client_) && isvalid(obj.client_)
                delete(obj.client_);
            end
            obj.client_ = [];
            obj.IsConnected = false;
        end

    end  % protected methods


    methods (Access = private)

        function response = sendCommand_(obj, cmd)
            % response = sendCommand_(obj, cmd)
            % Send a single RHX TCP command and return the response string.
            % Returns empty string on timeout or disconnected state.
            %
            % Parameters
            %   cmd - Command string (without terminator)
            %
            % Returns
            %   response - Response string from RHX (trimmed), or ''
            if isempty(obj.client_) || ~isvalid(obj.client_)
                response = '';
                return
            end

            write(obj.client_, uint8([cmd, newline]), 'uint8');

            % Wait for response bytes with simple poll loop
            deadline = tic;
            while obj.client_.NumBytesAvailable == 0
                if toc(deadline) > obj.Timeout
                    response = '';
                    return
                end
                pause(0.001);
            end

            raw = read(obj.client_, obj.client_.NumBytesAvailable, 'uint8');
            response = strtrim(char(raw));
        end

        function value = parseReturnValue_(~, response)
            % value = parseReturnValue_(obj, response)
            % Parse a 'Return: <ParameterName> <value>' response string.
            % Returns the value portion as char, or '' on unexpected format.
            %
            % Parameters
            %   response - Raw response string from RHX
            %
            % Returns
            %   value - Parsed value string (char)
            if isempty(response)
                value = '';
                return
            end
            % Response format: 'Return: <ParameterName> <value>'
            tokens = regexp(response, '^Return:\s+\S+\s+(.+)$', 'tokens', 'once');
            if isempty(tokens)
                value = '';
            else
                value = strtrim(tokens{1});
            end
        end

        function ok = isSuccessResponse_(~, response)
            % ok = isSuccessResponse_(obj, response)
            % Return true when response is a 'Return:' success message.
            % Returns false for empty, 'Error', or 'Warning' responses.
            %
            % Parameters
            %   response - Raw response string
            %
            % Returns
            %   ok - true when the command succeeded
            ok = ~isempty(response) && startsWith(response, 'Return:');
        end

        function applyMode_(obj, newMode)
            % applyMode_(obj, newMode)
            % Translate hw.DeviceState to RHX runmode command and send.
            %
            % Parameters
            %   newMode - hw.DeviceState value
            obj.modeCache_ = newMode;
            if ~obj.IsConnected || isempty(obj.client_)
                return
            end
            switch newMode
                case hw.DeviceState.Record
                    cmd = 'set runmode record';
                case {hw.DeviceState.Idle, hw.DeviceState.Standby}
                    cmd = 'set runmode stop';
                otherwise
                    cmd = 'set runmode run';
            end
            obj.sendCommand_(cmd);
        end

        function m = queryMode_(obj)
            % m = queryMode_(obj)
            % Query current RHX run mode via TCP; return hw.DeviceState.
            % Returns cached value when offline.
            %
            % Returns
            %   m - hw.DeviceState
            if ~obj.IsConnected || isempty(obj.client_)
                m = obj.modeCache_;
                return
            end
            resp = obj.sendCommand_('get runmode');
            % Expected: 'Return: RunMode Stop|Run|Record|Trigger'
            token = regexp(resp, 'Return:\s+RunMode\s+(\w+)', 'tokens', 'once');
            if isempty(token)
                m = obj.modeCache_;
                return
            end
            switch lower(token{1})
                case 'record'
                    m = hw.DeviceState.Record;
                case {'run', 'trigger'}
                    m = hw.DeviceState.Standby;
                otherwise
                    m = hw.DeviceState.Idle;
            end
            obj.modeCache_ = m;
        end

    end  % private methods

end
