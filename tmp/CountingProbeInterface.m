classdef CountingProbeInterface < hw.Interface
    % Counting stand-in for a device, for tmp/bench_trial_boundary.m and the
    % tests that assert how many device calls a trial costs.
    %
    % It mirrors hw.TDT_RPcox in the three respects those counts depend on:
    %
    %   * a connection probe is itself a device call (GetStatus), and
    %     get_parameter, set_parameter and trigger each probe before they act;
    %   * a read or a write is one device call per parameter, whether the
    %     caller passed one hw.Parameter or an array;
    %   * a trigger is a write of 1, a hold, and a write of 0.
    %
    % Every device call is counted in Counts and can be made to cost time
    % (CallDelay, a busy wait). Values written are kept and read back, as a
    % device holding them would, optionally in single precision (CoerceSingle)
    % or refused (RefuseWrites).
    %
    % obj = CountingProbeInterface()
    % obj = CountingProbeInterface(CallDelay=200e-6, CoerceSingle=true)
    %
    % Test knobs (public properties):
    %   CallDelay      - seconds each device call busy-waits. Default 0
    %   CoerceSingle   - keep written numerics as double(single(v)), as a float32
    %                    tag reads back. Default false
    %   RefuseWrites   - cellstr of parameter names whose writes return false
    %                    and store nothing
    %   ProbeTTL       - seconds ioReady may serve a cached probe. 0 = probe
    %                    every time
    %   YieldInTrigger - true holds the trigger pulse with pause(0.001), which
    %                    drains the event queue; false busy-waits. Default false
    %   Connected      - what the probe reports
    %
    % Counters (Counts struct; resetCounts zeroes them):
    %   Probe     - connection probes that reached the device
    %   Read      - parameter values read from the device
    %   Write     - parameter values written to the device
    %   Skipped   - writes the backend was asked for and did not send
    %   TrigWrite - trigger edge writes (two per trigger)
    %   Trigger   - trigger() calls
    %   Status    - mode queries that reached the device
    %   GetCalls / SetCalls - get_parameter / set_parameter invocations
    %
    % TriggerLog is a struct array (Name, Time) with Time in seconds since the
    % interface was built, so a harness can place the pulses on its own clock.

    properties (SetAccess = protected)
        Module
        HW = []   % hw.Parameter probes this; no real device behind it
    end

    properties (Constant)
        Type = 'CountingProbe'
    end

    properties (SetObservable, AbortSet)
        mode
    end

    properties
        Store          (1,1) struct = struct()
        Connected      (1,1) logical = true
        CallDelay      (1,1) double = 0
        CoerceSingle   (1,1) logical = false
        RefuseWrites   (1,:) cell = {}
        ProbeTTL       (1,1) double = 0
        YieldInTrigger (1,1) logical = false
        Counts         (1,1) struct = CountingProbeInterface.zeroCounts()
        TriggerLog     = struct('Name', {}, 'Time', {})
    end

    properties (Dependent)
        IsConnected
    end

    properties (Access = private)
        epoch_
        probeTic_ = []
        probeCache_ (1,1) logical = false
        modeState_ = hw.DeviceState.Standby
    end

    methods (Access = protected)
        function setup_interface(~)
        end
        function close_interface(~)
        end
    end

    methods
        function obj = CountingProbeInterface(options)
            arguments
                options.CallDelay (1,1) double = 0
                options.CoerceSingle (1,1) logical = false
                options.ProbeTTL (1,1) double = 0
                options.YieldInTrigger (1,1) logical = false
            end
            obj.CallDelay = options.CallDelay;
            obj.CoerceSingle = options.CoerceSingle;
            obj.ProbeTTL = options.ProbeTTL;
            obj.YieldInTrigger = options.YieldInTrigger;
            obj.Module = hw.Module(obj, 'Probe', 'Dev', 1);
            obj.epoch_ = tic;
        end

        function tf = get.IsConnected(obj)
            % A probe is a device round trip, as GetStatus is on RPcox.
            obj.Counts.Probe = obj.Counts.Probe + 1;
            obj.deviceCall_();
            tf = obj.Connected;
        end

        function tf = ioReady(obj)
            % The I/O path's connection check: the probe, optionally cached
            % for ProbeTTL seconds (hw.Interface.ioReady).
            if obj.ProbeTTL > 0 && ~isempty(obj.probeTic_) && toc(obj.probeTic_) < obj.ProbeTTL
                tf = obj.probeCache_;
                return
            end
            tf = obj.IsConnected;
            obj.probeCache_ = tf;
            obj.probeTic_ = tic;
        end

        function connect(obj)
            obj.Connected = true;
            obj.probeTic_ = [];
        end

        function m = get.mode(obj)
            % One status query plus the probe, as hw.TDT_RPcox.queryModeState_.
            if obj.ioReady()
                obj.Counts.Status = obj.Counts.Status + 1;
                obj.deviceCall_();
            end
            m = obj.modeState_;
        end

        function set.mode(obj, m)
            obj.modeState_ = hw.DeviceState(m);
        end

        function t = trigger(obj, name)
            if isa(name, 'hw.Parameter')
                P = name;
            else
                P = obj.find_parameter(name);
            end
            obj.Counts.Trigger = obj.Counts.Trigger + 1;
            t = now;
            if ~obj.ioReady()
                return
            end
            obj.Counts.TrigWrite = obj.Counts.TrigWrite + 1;
            obj.deviceCall_();
            obj.TriggerLog(end+1) = struct('Name', P.Name, 'Time', toc(obj.epoch_));
            if obj.YieldInTrigger
                pause(0.001)
            else
                t0 = tic;
                while toc(t0) < 0.001, end
            end
            obj.Counts.TrigWrite = obj.Counts.TrigWrite + 1;
            obj.deviceCall_();
        end

        function result = set_parameter(obj, name, value)
            obj.Counts.SetCalls = obj.Counts.SetCalls + 1;
            result = true;
            if ~obj.ioReady()
                return
            end
            if isa(name, 'hw.Parameter')
                P = name;
            else
                P = obj.find_parameter(name);
            end
            if isempty(value)
                return
            end
            if isscalar(value) && ~isscalar(P)
                value = repmat(value, size(P));
            end
            for i = 1:numel(P)
                v = value(i);
                if iscell(v), v = v{1}; end
                result = obj.writeOne_(P(i), v) && result;
            end
        end

        function value = get_parameter(obj, name, options)
            arguments
                obj
                name
                options.includeInvisible (1,1) logical = false
                options.silenceParameterNotFound (1,1) logical = false
            end
            obj.Counts.GetCalls = obj.Counts.GetCalls + 1;

            if isa(name, 'hw.Parameter')
                P = name;
            else
                P = obj.find_parameter(name, ...
                    includeInvisible = options.includeInvisible, ...
                    silenceParameterNotFound = options.silenceParameterNotFound);
            end

            value = cell(size(P));
            if ~obj.ioReady()
                % Offline: the stored hw.Parameter value, which get.Value
                % serves without coming back here.
                for i = 1:numel(P)
                    value{i} = P(i).Value;
                end
            else
                for i = 1:numel(P)
                    obj.Counts.Read = obj.Counts.Read + 1;
                    obj.deviceCall_();
                    f = P(i).validName;
                    if isfield(obj.Store, f)
                        value{i} = obj.Store.(f);
                    elseif ~isempty(P(i).Values)
                        value{i} = P(i).Values{1};
                    else
                        value{i} = nan;
                    end
                end
            end
            if isscalar(value), value = value{1}; end
        end

        function put(obj, p, v)
            % put(param, value) - set what the device reports, without a write.
            obj.Store.(p.validName) = v;
        end

        function v = held(obj, p)
            % v = held(param) - what the device holds, without a read.
            v = [];
            if isfield(obj.Store, p.validName)
                v = obj.Store.(p.validName);
            end
        end

        function resetCounts(obj)
            obj.Counts = CountingProbeInterface.zeroCounts();
            obj.TriggerLog = struct('Name', {}, 'Time', {});
        end

        function n = deviceCalls(obj)
            % n = deviceCalls(obj) - every call that reached the device.
            c = obj.Counts;
            n = c.Probe + c.Read + c.Write + c.TrigWrite + c.Status;
        end
    end

    methods (Access = protected)
        function ok = writeOne_(obj, p, v)
            % One device write. Kept separate so a subclass can stand in for
            % a backend that may skip it.
            if any(strcmp(obj.RefuseWrites, p.Name))
                obj.Counts.Write = obj.Counts.Write + 1;
                obj.deviceCall_();
                ok = false;
                return
            end
            if isa(v, 'stimgen.StimType')
                ok = true;   % no waveform sink; the value stays host-side
                return
            end
            obj.Counts.Write = obj.Counts.Write + 1;
            obj.deviceCall_();
            if obj.CoerceSingle && isnumeric(v)
                v = double(single(v));
            end
            obj.Store.(p.validName) = v;
            ok = true;
        end

        function deviceCall_(obj)
            if obj.CallDelay > 0
                t0 = tic;
                while toc(t0) < obj.CallDelay, end
            end
        end
    end

    methods (Static)
        function c = zeroCounts()
            c = struct('Probe', 0, 'Read', 0, 'Write', 0, 'Skipped', 0, ...
                'TrigWrite', 0, 'Trigger', 0, 'Status', 0, 'GetCalls', 0, 'SetCalls', 0);
        end

        function spec = getCreationSpec()
            spec = hw.InterfaceSpec('CountingProbe', 'Counting probe', ...
                'Test double that counts device calls.', ...
                hw.InterfaceSpecOption.empty(1,0), ...
                @(~) CountingProbeInterface());
        end
    end
end
