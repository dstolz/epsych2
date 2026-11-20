classdef BenchLoopbackInterface < hw.Software
    % Test double for tmp/smoke_test_hw_benchmark_io.m: an hw.Software whose
    % set_parameter keeps what it was given and whose get_parameter returns
    % it, so a buffer round trip has something to compare.
    %
    % hw.Software itself stores nothing in set_parameter and answers every
    % read with NaN -- hw.Parameter keeps the values, and get.Value special-
    % cases the class -- so it cannot stand in for a device that holds data.
    % Everything here stays in memory; nothing touches hardware.
    %
    % obj = BenchLoopbackInterface()
    % obj = BenchLoopbackInterface(Simulated=false)   % a "device" for the
    %                                                 % disconnected-refusal
    %                                                 % and floor tests
    %
    % Test knobs (public properties):
    %   CorruptReads - add 1e-3 to the first element of every array read.
    %   ClobberRun   - [first count]: every array read returns 5 in elements
    %                  first..first+count-1 (wrapping past the end), as a
    %                  circuit writing into the buffer leaves it. [0 0] = off.
    %   ReadWhole    - element count every array read returns, padding with
    %                  zeros what was written, as a backend that reads a
    %                  tag's whole storage back does. 0 = off.
    %   Capacities   - validName -> element count, served by parameterCapacity.
    %   DelayModel   - [a b]: each write busy-waits a + b*N seconds, so a
    %                  known overhead and per-sample cost can be recovered.
    %   NameDelay    - extra seconds each write given a NAME busy-waits.
    %   HandleDelay  - extra seconds each write given an hw.Parameter waits.
    %   AlternateDelay - extra seconds every second write waits, counted
    %                  across all writes, so two blocks of an even number of
    %                  calls draw from one and the same two-valued spread.
    %   Context      - what transferContext returns.
    %   ThrowContext - make transferContext throw instead.
    %   Simulated    - what isSimulated reports.

    properties
        Store        (1,1) struct = struct()
        CorruptReads (1,1) logical = false
        ClobberRun   (1,2) double = [0 0]
        ReadWhole    (1,1) double = 0
        Capacities   (1,1) struct = struct()
        DelayModel   (1,2) double = [0 0]
        NameDelay    (1,1) double = 0
        HandleDelay  (1,1) double = 0
        AlternateDelay (1,1) double = 0
        Context      struct = hw.Interface.transferContextRecord()
        ThrowContext (1,1) logical = false
        Simulated    (1,1) logical = true
    end

    properties (Access = private)
        Writes_ (1,1) double = 0
    end

    methods
        function obj = BenchLoopbackInterface(options)
            arguments
                options.Simulated (1,1) logical = true
            end
            obj@hw.Software();
            obj.Simulated = options.Simulated;
        end

        function tf = isSimulated(obj)
            tf = obj.Simulated;
        end

        function ctx = transferContext(obj)
            if obj.ThrowContext
                error('BenchLoopbackInterface:Context', 'transferContext was told to throw');
            end
            ctx = obj.Context;
        end

        function n = parameterCapacity(obj, P)
            n = NaN;
            if isfield(obj.Capacities, P.validName)
                n = obj.Capacities.(P.validName);
            end
        end

        function result = set_parameter(obj, name, value)
            P = obj.resolve_(name);
            if iscell(value) && isscalar(value)
                value = value{1};
            end
            obj.Store.(P.validName) = value;
            obj.wait_(numel(value), ~isa(name, 'hw.Parameter'));
            result = true;
        end

        function value = get_parameter(obj, name, options)
            arguments
                obj
                name
                options.includeInvisible (1,1) logical = false
                options.silenceParameterNotFound (1,1) logical = false
            end
            P = obj.resolve_(name);
            value = NaN;
            if isfield(obj.Store, P.validName)
                value = obj.Store.(P.validName);
            end
            if obj.ReadWhole > 0 && numel(value) > 1 && numel(value) < obj.ReadWhole
                value(end+1:obj.ReadWhole) = 0;
            end
            if obj.CorruptReads && numel(value) > 1
                value(1) = value(1) + 1e-3;
            end
            if obj.ClobberRun(2) > 0 && numel(value) > 1
                idx = mod(obj.ClobberRun(1) - 1 + (0:obj.ClobberRun(2) - 1), numel(value)) + 1;
                value(idx) = 5;
            end
        end

        function put(obj, name, value)
            % put(name, value) - set what this backend will report for name.
            P = obj.find_parameter(name, includeInvisible = true);
            obj.Store.(P.validName) = value;
        end
    end

    methods (Access = private)
        function P = resolve_(obj, name)
            if isa(name, 'hw.Parameter')
                P = name;
            else
                P = obj.find_parameter(name);
            end
        end

        function wait_(obj, n, byName)
            % Busy-wait rather than pause: pause is quantized to the
            % scheduler and would blur the per-sample term being recovered.
            obj.Writes_ = obj.Writes_ + 1;
            d = obj.DelayModel(1) + obj.DelayModel(2) * n;
            if byName
                d = d + obj.NameDelay;
            else
                d = d + obj.HandleDelay;
            end
            if mod(obj.Writes_, 2) == 0
                d = d + obj.AlternateDelay;
            end
            if d <= 0
                return
            end
            t0 = tic;
            while toc(t0) < d
            end
        end
    end
end
