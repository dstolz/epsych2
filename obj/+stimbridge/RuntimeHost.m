classdef RuntimeHost < stimgen.HardwareHost
    % host = stimbridge.RuntimeHost()
    % host = stimbridge.RuntimeHost(protocolInput)
    %
    % EPsych implementation of the stimgen.HardwareHost contract.
    %
    % Wraps an epsych.Runtime and epsych.Protocol so stimgen GUIs
    % (stimgen.StimPlayer, stimgen.calibration.CalibrationGui) can drive
    % EPsych hardware without referencing any epsych.* or hw.* type. This is
    % the only place that translates between the two.
    %
    % Parameters:
    %   protocolInput - epsych.Protocol object or protocol filepath (optional)
    %
    % Example:
    %   host = stimbridge.RuntimeHost('MyExperiment.eprot');
    %   player = stimgen.StimPlayer(host);
    %
    % See also: stimgen.HardwareHost, stimbridge.InterfaceAdapter,
    %           epsych.Runtime, epsych.Protocol

    properties (SetAccess = private)
        Runtime epsych.Runtime = epsych.Runtime.empty(0,1)  % Runtime holding the connected interfaces
        Protocol epsych.Protocol = epsych.Protocol.empty(0,1) % Loaded protocol defining the interfaces
        ProtocolFile (1,1) string = ""                       % Source path when loaded from file
    end

    methods
        function obj = RuntimeHost(protocolInput)
            if nargin > 0 && ~isempty(protocolInput)
                obj.loadProtocol(protocolInput);
            end
        end

        % -----------------------------------------------------------------
        function loadProtocol(obj, protocolInput)
            % loadProtocol(obj, protocolInput)
            % Accept an epsych.Protocol object or a path to a protocol file.
            obj.release();

            if isa(protocolInput, 'epsych.Protocol')
                obj.Protocol = protocolInput;
                obj.ProtocolFile = "";
            elseif ischar(protocolInput) || isstring(protocolInput)
                pfn = string(protocolInput);
                if ~isfile(pfn)
                    error('stimbridge:RuntimeHost:protocolFileNotFound', ...
                        'Protocol file was not found: %s', pfn);
                end
                obj.Protocol = epsych.Protocol.load(char(pfn));
                obj.ProtocolFile = pfn;
            else
                error('stimbridge:RuntimeHost:invalidProtocolInput', ...
                    'Expected an epsych.Protocol object or a protocol filepath.');
            end
        end

        % -----------------------------------------------------------------
        function tf = hasProtocol(obj)
            tf = ~isempty(obj.Protocol) && isvalid(obj.Protocol);
        end

        % -----------------------------------------------------------------
        function name = protocolName(obj)
            if ~obj.hasProtocol()
                name = "";
            elseif strlength(obj.ProtocolFile) > 0
                [~, fn, ext] = fileparts(char(obj.ProtocolFile));
                name = string(fn) + string(ext);
            else
                name = string(class(obj.Protocol));
            end
        end

        % -----------------------------------------------------------------
        function connect(obj)
            % connect(obj)
            % Build the runtime from the loaded protocol and connect every
            % interface. Throws if any interface fails to connect.
            if ~obj.hasProtocol()
                error('stimbridge:RuntimeHost:noProtocol', ...
                    'Load a protocol before connecting hardware.');
            end

            obj.Runtime = epsych.Runtime;
            obj.Runtime.Interfaces = obj.Protocol.Interfaces;

            for k = 1:numel(obj.Runtime.Interfaces)
                iface = obj.Runtime.Interfaces(k);
                if ~iface.IsConnected
                    iface.connect();
                    assert(iface.IsConnected, ...
                        'stimbridge:RuntimeHost:connectFailed', ...
                        'Hardware interface "%s" failed to connect.', class(iface));
                end
            end
        end

        % -----------------------------------------------------------------
        function release(obj)
            obj.Runtime = epsych.Runtime.empty(0,1);
        end

        % -----------------------------------------------------------------
        function setMode(obj, modeName)
            % setMode(obj, modeName)
            % Map the host-neutral mode name onto hw.DeviceState.
            arguments
                obj
                modeName (1,1) string {mustBeMember(modeName,["Preview","Idle"])}
            end

            if isempty(obj.Runtime) || ~isvalid(obj.Runtime) || isempty(obj.Runtime.Interfaces)
                return
            end

            switch modeName
                case "Preview", state = hw.DeviceState.Preview;
                case "Idle",    state = hw.DeviceState.Idle;
            end
            set(obj.Runtime.Interfaces, 'mode', state);
        end

        % -----------------------------------------------------------------
        function p = findParameter(obj, name)
            % p = findParameter(obj, name)
            % Resolve a parameter across all interfaces; [] when absent.
            p = [];
            if isempty(obj.Runtime) || ~isvalid(obj.Runtime)
                return
            end
            p = obj.Runtime.find_parameter(name, silenceParameterNotFound=true);
        end

        % -----------------------------------------------------------------
        function state = connectionState(obj)
            if isempty(obj.Runtime) || ~isvalid(obj.Runtime) || isempty(obj.Runtime.Interfaces)
                state = "None";
                return
            end

            connected = [obj.Runtime.Interfaces.IsConnected];
            if all(connected)
                state = "Ready";
            elseif any(connected)
                state = "Partial";
            else
                state = "NotConnected";
            end
        end

        % -----------------------------------------------------------------
        function adapter = calibrationAdapter(obj)
            % adapter = calibrationAdapter(obj)
            % Return a calibration adapter for the first interface exposing
            % the required buffer/trigger tags.
            candidates = obj.adapter_candidates_();

            lastError = [];
            for k = 1:numel(candidates)
                try
                    adapter = stimbridge.InterfaceAdapter(candidates(k));
                    return
                catch ME
                    lastError = ME;
                end
            end

            if isempty(lastError)
                error('stimbridge:RuntimeHost:noAdapterSource', ...
                    'No runtime interface could be adapted for calibration.');
            else
                error('stimbridge:RuntimeHost:attachAdapterFailed', ...
                    ['Could not attach calibration adapter from runtime interfaces. ' ...
                    'Verify required tags (BufferSize, BufferOut, !Trigger or x_Trigger, BufferIndex, BufferIn). ' ...
                    'Original error: %s'], lastError.message);
            end
        end
    end

    methods (Access = private)
        function candidates = adapter_candidates_(obj)
            % Prefer this host's own runtime; fall back to a RUNTIME left in
            % the base workspace by the legacy EPsych session workflow.
            runtimeObj = obj.Runtime;
            if isempty(runtimeObj) || ~isvalid(runtimeObj)
                % stimgen GUIs surface ME.message verbatim, so an unguarded
                % evalin would show a bare "Undefined variable RUNTIME".
                if ~evalin('base', 'exist(''RUNTIME'',''var'')')
                    error('stimbridge:RuntimeHost:noRuntimeInterfaces', ...
                        ['No hardware runtime is available. Load a protocol and ' ...
                        'connect before requesting a calibration adapter, or start ' ...
                        'a session so that RUNTIME exists in the base workspace.']);
                end
                runtimeObj = evalin('base', 'RUNTIME');
                if ~isa(runtimeObj, 'epsych.Runtime')
                    error('stimbridge:RuntimeHost:badRuntime', ...
                        'Base workspace RUNTIME must be an epsych.Runtime object.');
                end
            end

            if ~isempty(runtimeObj.Interfaces)
                candidates = runtimeObj.Interfaces;
            elseif ~isempty(runtimeObj.HW)
                candidates = runtimeObj.HW;
            else
                error('stimbridge:RuntimeHost:noRuntimeInterfaces', ...
                    'Runtime has no interfaces. Initialize runtime from a protocol first.');
            end
        end
    end
end
