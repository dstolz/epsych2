classdef BatchProbeInterface < hw.Interface
    % Minimal hw.Interface that counts get_parameter calls, for
    % tmp/smoke_test_onlineplot.m.
    %
    % It stands in for a real backend in the one respect the test cares about:
    % a read costs a round trip, and reading an array of hw.Parameter costs ONE
    % of them. Values live in a name -> value map that the test writes directly,
    % so nothing here touches hardware.
    %
    % obj = BatchProbeInterface()
    % obj = BatchProbeInterface(RefuseBatch=true)  % throws on an array read,
    %                                              % as hw.VlcRecorder would

    properties (SetAccess = protected)
        Module
        HW = []   % hw.Parameter probes this; no real device behind it
    end

    properties (Constant)
        Type = 'BatchProbe'
    end

    properties (SetObservable,AbortSet)
        mode
    end

    properties
        Store       (1,1) struct = struct()  % validName -> value
        GetCalls    (1,1) double = 0         % get_parameter invocations
        GetValues   (1,1) double = 0         % individual values served
        RefuseBatch (1,1) logical = false    % simulate a scalar-only backend
        Connected   (1,1) logical = true
    end

    properties (Dependent)
        IsConnected
    end

    methods (Access = protected)
        function setup_interface(~)
        end
        function close_interface(~)
        end
    end

    methods
        function obj = BatchProbeInterface(options)
            arguments
                options.RefuseBatch (1,1) logical = false
            end
            obj.RefuseBatch = options.RefuseBatch;
            obj.Module = hw.Module(obj,'Probe','Params',1);
        end

        function tf = get.IsConnected(obj)
            tf = obj.Connected;
        end

        function connect(obj)
            obj.Connected = true;
        end

        function result = trigger(~,~)
            result = 1;
        end

        function result = set_parameter(~,~,~)
            result = 1;
        end

        function value = get_parameter(obj,name,options)
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

            if ~isscalar(P) && obj.RefuseBatch
                error('BatchProbeInterface:scalarOnly', ...
                    'This backend reads one parameter at a time.');
            end

            obj.GetCalls = obj.GetCalls + 1;
            obj.GetValues = obj.GetValues + numel(P);

            value = cell(size(P));
            for i = 1:numel(P)
                f = P(i).validName;
                if isfield(obj.Store,f)
                    value{i} = obj.Store.(f);
                else
                    value{i} = nan;
                end
            end
            if isscalar(value), value = value{1}; end
        end

        function put(obj,p,v)
            % put(param, value) - set the value this backend will report.
            obj.Store.(p.validName) = v;
        end

        function reset_counts(obj)
            obj.GetCalls = 0;
            obj.GetValues = 0;
        end
    end

    methods (Static)
        function spec = getCreationSpec()
            spec = hw.InterfaceSpec('BatchProbe','Batch probe', ...
                'Test double that counts reads.', ...
                hw.InterfaceSpecOption.empty(1,0), ...
                @(~) BatchProbeInterface());
        end
    end
end
