classdef ParameterDebuggerMock < hw.Interface
    % obj = ParameterDebuggerMock()
    % In-process backend for tmp/smoke_test_parameter_debugger.m.
    %
    % gui.ParameterDebugger is mostly interesting in the cases hw.Software
    % cannot produce: hw.Parameter.get.Value short-circuits for a Software
    % parent and never calls get_parameter, so a Software-only test can never
    % exercise a read that fails, a read that returns something other than what
    % was written, or the difference between a connected and a disconnected
    % backend. This mock is a real hw.Interface with a value store of its own,
    % so every one of those paths is reachable without hardware.
    %
    % Properties:
    %   FailOn     - Parameter names whose read throws
    %   QuantizeOn - Parameter names whose written value is rounded on the way
    %                in, so the read-back legitimately differs from the write
    %   Fired      - Names passed to trigger, in order
    %
    % See also: tmp/smoke_test_parameter_debugger.m, gui.ParameterDebugger

    properties (SetAccess = protected)
        HW
        Module
    end

    properties
        % No size or class validator: IsConnected is declared abstract on
        % hw.Interface, and MATLAB refuses validation on an inherited property.
        IsConnected = false

        Store       % containers.Map of parameter name -> stored value
        Fired = {}  % names passed to trigger, in order

        FailOn (1,:) string = "Broken"
        QuantizeOn (1,:) string = "Coarse"

        % Called on every read, after the value is resolved. The hook exists so
        % a test can make something happen DURING a sweep -- closing the window
        % mid-read is otherwise unreachable synchronously, and it is exactly
        % what an operator does when a backend stops answering.
        OnRead = []
        ReadCount (1,1) double = 0
    end

    properties (Constant)
        Type = 'MockRig'
    end

    properties (SetObservable, AbortSet)
        mode
    end

    methods
        function obj = ParameterDebuggerMock()
            obj.Module = hw.Module(obj, 'MOCK', 'Rig', 1);
            obj.Store = containers.Map('KeyType','char','ValueType','any');
        end

        function connect(obj)
            obj.IsConnected = true;
        end

        function disconnect(obj)
            obj.IsConnected = false;
        end

        function value = get_parameter(obj, name, options)
            arguments
                obj
                name
                options.includeInvisible (1,1) logical = false
                options.silenceParameterNotFound (1,1) logical = false
            end

            if isa(name, 'hw.Parameter')
                P = name;
            else
                P = obj.find_parameter(name, includeInvisible = options.includeInvisible);
            end

            if any(strcmp(P.Name, obj.FailOn))
                error('ParameterDebuggerMock:ReadFailed', ...
                    'the device did not answer for "%s"', P.Name);
            end

            if obj.Store.isKey(P.Name)
                value = obj.Store(P.Name);
            else
                value = nan;
            end

            obj.ReadCount = obj.ReadCount + 1;
            if isa(obj.OnRead, 'function_handle')
                obj.OnRead(obj, P);
            end
        end

        function result = set_parameter(obj, name, value)
            if isa(name, 'hw.Parameter')
                P = name;
            else
                P = obj.find_parameter(name);
            end

            % Array-valued writes arrive wrapped in a scalar cell; see
            % hw.Parameter.set.Value.
            if iscell(value) && isscalar(value)
                value = value{1};
            end

            % A coarse device quantises what it is given, which is the honest
            % reason a read-back can differ from a write.
            if any(strcmp(P.Name, obj.QuantizeOn)) && isnumeric(value)
                value = round(value);
            end

            obj.Store(P.Name) = value;
            result = true;
        end

        function result = trigger(obj, name)
            if isa(name, 'hw.Parameter')
                name = name.Name;
            end
            obj.Fired{end+1} = char(name);
            % datenum, not datetime: hw.Parameter.Trigger assigns this straight
            % to lastUpdated, which every backend fills with `now`.
            result = now; %#ok<TNOW1> matches the hw.Interface.trigger contract
        end
    end

    methods (Access = protected)
        function setup_interface(~)
        end

        function close_interface(~)
        end
    end

    methods (Static)
        function spec = getCreationSpec()
            spec = hw.InterfaceSpec( ...
                char(ParameterDebuggerMock.Type), ...
                'Mock Rig', ...
                'In-process backend used by the parameter debugger smoke test.', ...
                hw.InterfaceSpecOption.empty(1, 0), ...
                @(~) ParameterDebuggerMock());
        end
    end
end
