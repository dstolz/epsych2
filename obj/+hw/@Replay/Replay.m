classdef Replay < hw.Interface
    % obj = hw.Replay(records)
    % Backend that answers parameter reads from a saved session record.
    %
    % A review of a finished session needs the paradigm's own controls and
    % monitors to resolve, and to show what the rig actually held on the trial
    % being looked at. hw.Replay is the backend that makes that possible: it
    % owns the protocol's parameter tree, rebuilt from the session snapshot,
    % and every read is a lookup in the saved DATA array at Position.
    %
    % It reports IsConnected = true on purpose. hw.Parameter.get.Value
    % short-circuits to the locally cached value for an hw.Software parent or a
    % disconnected one, which would return the protocol's DESIGN-TIME value
    % rather than the trial's; reporting connected is what routes the read here
    % instead. Nothing is ever written: set_parameter and trigger no-op, so a
    % control that somehow escapes being disabled cannot alter the record.
    %
    % Properties
    %   Records  - The saved per-trial DATA struct array being reviewed.
    %   Position - 1-based index into Records; 0 means "before the first trial",
    %              where reads fall back to the design-time value.
    %   Module   - Modules rebuilt from the snapshot.
    %   Type     - Constant interface identifier 'Replay'.
    %
    % Usage
    %   ifaces = hw.Replay.fromProtocolStruct(snapshot.Protocol, Data);
    %   [ifaces.Position] = deal(17);   % every read now reports trial 17
    %
    % See also: epsych.ReviewSession, epsych.SessionSnapshot, hw.Software

    properties (SetAccess = protected)
        % Left empty: there is no device handle behind a review. It exists
        % because hw.Parameter's constructor reads Parent.HW, as it does on
        % every backend.
        HW

        Module
    end

    properties
        IsConnected = true % see the class note: deliberately true

        % The saved DATA array. Fields are hw.Parameter validNames, which is
        % what ep_TimerFcn_RunTime records (Runtime.all_parameters asStruct).
        Records struct = struct.empty(1,0)

        % Trial being reported. Outside 1:numel(Records) every read falls back
        % to the design-time value, which is what an unpositioned review shows.
        Position (1,1) double {mustBeNonnegative,mustBeInteger} = 0
    end

    properties (Constant)
        Type = 'Replay'
    end

    properties (SetObservable,AbortSet)
        mode
    end

    properties (Access = private)
        % validName -> design-time value, captured from the snapshot at build
        % time. It CANNOT be read back off the parameter: hw.Parameter.get.Value
        % calls get_parameter, so touching p.Value from in here would recurse
        % (the same trap hw.Software.get_parameter documents).
        DefaultValues_ (1,1) struct = struct()
    end


    methods (Access = protected)
        function setup_interface(~)
            % Nothing to allocate; the parameter tree is installed by
            % fromProtocolStruct.
        end

        function close_interface(~)
        end
    end


    methods
        function obj = Replay(records)
            % obj = hw.Replay(records)
            %  records - saved DATA struct array (optional).
            arguments
                records struct = struct.empty(1,0)
            end
            obj.Module = hw.Module(obj, 'Replay', 'Replay', 1);
            obj.Records = records;
        end

        function connect(obj)
            obj.IsConnected = true;
        end

        function disconnect(obj)
            % A review has nothing to disconnect from, but the method exists so
            % teardown paths written against a real backend do not have to
            % special-case this one.
            obj.IsConnected = false;
        end

        function result = trigger(~,~)
            % No hardware to fire. The timestamp keeps hw.Parameter.Trigger's
            % lastUpdated stamp meaningful, as on every other backend.
            result = now;
        end

        function result = set_parameter(~,~,~)
            % A review is read-only. hw.Parameter.set.Value has already stored
            % the value locally by the time this is called; throwing here would
            % throw out of a property setter, so the write is ignored and the
            % next read comes back off the record regardless.
            vprintf(4, 'hw.Replay: write ignored (session review is read-only)')
            result = 1;
        end

        function value = get_parameter(obj, name, options)
            % value = get_parameter(obj, name)
            % Value(s) recorded for these parameters on the positioned trial.
            %
            % A parameter with no field in the record -- write-only, invisible,
            % and trigger parameters never reach DATA -- falls back to its
            % design-time value.
            %
            % Returns the value itself for a single parameter, and a cell array
            % for several, since recorded values need not share a type.
            arguments
                obj
                name
                options.includeInvisible (1,1) logical = false
                options.silenceParameterNotFound (1,1) logical = false
            end

            if isa(name,'hw.Parameter')
                P = name;
            else
                P = obj.find_parameter(name, ...
                    includeInvisible = options.includeInvisible, ...
                    silenceParameterNotFound = options.silenceParameterNotFound);
            end

            if isempty(P)
                value = [];
                return
            end

            if isscalar(P)
                value = obj.recordedValue_(P);
                return
            end

            value = arrayfun(@(p) obj.recordedValue_(p), P, UniformOutput = false);
        end

        function results = selfTest(obj, options)
            % results = selfTest(obj)
            % Report what the review has to work with. Nothing here can be
            % unreachable, so this only surfaces the record inventory.
            %
            % See also: hw.Interface.selfTest
            arguments
                obj
                options.Invasive (1,1) logical = false
            end

            nParams = numel(obj.all_parameters(Access='All', includeInvisible=true));

            if isempty(obj.Records)
                results = hw.Interface.selfTestResult('Session record', 'warn', ...
                    sprintf('No trials loaded; %d parameter(s) will read their design-time values.', nParams), ...
                    Remedy = "Open a session file that contains at least one completed trial.");
                return
            end

            results = hw.Interface.selfTestResult('Session record', 'pass', ...
                sprintf('%d trial(s) over %d parameter(s); positioned at trial %d.', ...
                numel(obj.Records), nParams, obj.Position));
        end
    end


    methods (Hidden)
        function set_module(obj, M)
            obj.Module = M;
        end

        function setDefaultValue_(obj, validName, value)
            % Record the design-time fallback for one parameter. Hidden rather
            % than private so fromProtocolStruct can fill it in.
            obj.DefaultValues_.(validName) = value;
        end
    end


    methods (Access = private)
        function v = recordedValue_(obj, p)
            vn = p.validName;

            if obj.Position >= 1 && obj.Position <= numel(obj.Records) ...
                    && isfield(obj.Records, vn)
                v = obj.Records(obj.Position).(vn);
                return
            end

            if isfield(obj.DefaultValues_, vn)
                v = obj.DefaultValues_.(vn);
                return
            end

            v = [];
        end
    end


    methods (Static)
        function spec = getCreationSpec()
            % A review builds these itself from a session snapshot; the spec
            % exists to satisfy hw.Interface and is deliberately absent from
            % RunExpt's backend registry, so it never appears in
            % ProtocolDesigner as something to add to a protocol.
            spec = hw.InterfaceSpec( ...
                char(hw.Replay.Type), ...
                'Session Replay', ...
                'Read-only backend that answers parameter reads from a saved session.', ...
                hw.InterfaceSpecOption.empty(1, 0), ...
                @(~) hw.Replay());
        end

        interfaces = fromProtocolStruct(protocolStruct, records) % Rebuild a protocol parameter tree as read-only replay backends.
    end
end
