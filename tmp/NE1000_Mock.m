classdef NE1000_Mock < hw.NE1000
    % mock = NE1000_Mock(Name=Value)
    % In-process simulation of an NE-1000 pump for smoke tests.
    %
    % Overrides ONLY the transport-seam methods of hw.NE1000 (openPort_,
    % closePort_, writeLine_, writeRaw_, readPacket_, flushInput_), so every
    % protocol path exercised through it — the Basic-mode framing, the alarm
    % acknowledgment, the RAT units fallback, the DIS cache — is the same code
    % a real pump runs.
    %
    % The simulated pump powers up with a pending reset alarm (A?R), exactly as
    % a real pump does after a power cycle, so connect() must survive its first
    % reply being an alarm rather than data.
    %
    % See also: tmp/smoke_test_ne1000.m, hw.NE1000

    properties
        % Simulated pump state, public so tests can assert against it. The
        % power-up diameter deliberately differs from the interface default so
        % the connect-time DIA push is observable.
        SimDiameter (1,1) double = 10
        SimRate (1,1) double = 10
        SimRateUnits (1,2) char = 'MH'
        SimVolume (1,1) double = 0
        SimDir (1,3) char = 'INF'
        SimInfused (1,1) double = 0
        SimWithdrawn (1,1) double = 0
        SimStatus (1,1) char = 'S'      % I/W/S/P/T/U/X
        PendingAlarm (1,:) char = 'R'   % answered (and cleared) on the next command

        Log = {}                        % every command line writeLine_ saw
        RawLog = {}                     % every raw byte packet writeRaw_ saw

        % Fault injection for the degraded-link paths.
        DropReplies (1,1) double = 0    % swallow this many replies, then resume
        ReentrantProbe = []             % called once from INSIDE readPacket_
    end

    properties (Access = private)
        rxQueue_ = {}                   % replies waiting for readPacket_
    end

    methods
        function obj = NE1000_Mock(options)
            arguments
                options.SyringeDiameter (1,1) double = 21.59
                options.RateUnits (1,2) char = 'MH'
                options.Connect (1,1) logical = true
            end
            obj@hw.NE1000('MOCK', Connect = false, ...
                SyringeDiameter = options.SyringeDiameter, ...
                RateUnits = options.RateUnits, Timeout = 0.1);
            if options.Connect
                obj.connect();
            end
        end
    end

    methods (Access = protected)

        function openPort_(obj)
            % Park a non-handle SCALAR sentinel where the serialport would
            % live: hw.NE1000.get.IsConnected tolerates a non-handle, and
            % hw.Parameter.HW requires a scalar.
            obj.HW = struct(mock = true);
        end

        function closePort_(obj)
            obj.HW = [];
        end

        function writeRaw_(obj, bytes)
            % The Safe-mode escape packet. The simulated pump is already in
            % Basic mode, where the packet parses as a valid SAF0 command; the
            % reply it would produce is discarded by the flush that follows in
            % setup_interface, so none is queued. The pending power-up alarm is
            % NOT cleared here: the manual acknowledges alarms through the
            % status carried on a Basic-mode reply, which this write never reads.
            obj.RawLog{end + 1} = bytes;
        end

        function writeLine_(obj, s)
            obj.Log{end + 1} = char(s);
            obj.rxQueue_{end + 1} = obj.respond_(char(s));
        end

        function s = readPacket_(obj)
            % Serve the oldest queued reply, already STX-stripped the way the
            % real readPacket_ returns it.
            %
            % ReentrantProbe stands in for a timer callback firing while the
            % real readline blocks — MATLAB dispatches timers during serial
            % reads, which is exactly the hazard hw.NE1000's transaction guard
            % exists to stop. It runs once, from inside the read.
            if ~isempty(obj.ReentrantProbe)
                f = obj.ReentrantProbe;
                obj.ReentrantProbe = [];
                f();
            end

            % A dropped reply. The queue is cleared with it: a pump that never
            % answered has nothing waiting behind it either.
            if obj.DropReplies > 0
                obj.DropReplies = obj.DropReplies - 1;
                obj.rxQueue_ = {};
                s = '';
                return
            end

            if isempty(obj.rxQueue_)
                s = '';
                return
            end
            s = obj.rxQueue_{1};
            obj.rxQueue_(1) = [];
        end

        function flushInput_(obj)
            obj.rxQueue_ = {};
        end

    end

    methods (Access = private)

        function reply = respond_(obj, line)
            % reply = respond_(obj, line)
            % Produce one Basic-mode reply payload '<addr><status>[data]' for
            % one command line, mutating the simulated pump.

            % Strip the network address the interface prefixes.
            cmd = regexprep(strtrim(line), '^\d+', '');
            cmd = upper(strrep(cmd, ' ', ''));

            % A pending alarm preempts the command: the reply carries the alarm
            % status (which acknowledges it) and the command is not performed.
            if ~isempty(obj.PendingAlarm)
                reply = ['0A?' obj.PendingAlarm];
                obj.PendingAlarm = '';
                return
            end

            st = obj.SimStatus;
            data = '';
            pumping = any(st == 'IWX');

            if isempty(cmd)
                % Status-only query.
            elseif strcmp(cmd, 'VER')
                data = 'NE1000V3.928';
            elseif strcmp(cmd, 'DIA')
                data = sprintf('%.2f', obj.SimDiameter);
            elseif startsWith(cmd, 'DIA')
                v = str2double(cmd(4:end));
                if pumping || ~isfinite(v) || v < 0.1 || v > 50
                    data = '?OOR';
                else
                    obj.SimDiameter = v;
                end
            elseif strcmp(cmd, 'RAT')
                data = sprintf('%.4g%s', obj.SimRate, obj.SimRateUnits);
            elseif startsWith(cmd, 'RAT')
                tok = regexp(cmd(4:end), '^([\d.]+)(UM|MM|UH|MH)?$', 'tokens', 'once');
                if isempty(tok)
                    data = '?';
                elseif pumping && ~isempty(tok{2})
                    % Rate units cannot be set while pumping (manual 6.6.1).
                    data = '?NA';
                else
                    obj.SimRate = str2double(tok{1});
                    if ~isempty(tok{2})
                        obj.SimRateUnits = tok{2};
                    end
                end
            elseif strcmp(cmd, 'VOL')
                data = sprintf('%.3f ML', obj.SimVolume);
            elseif startsWith(cmd, 'VOL')
                obj.SimVolume = str2double(cmd(4:end));
            elseif strcmp(cmd, 'DIR')
                data = obj.SimDir;
            elseif startsWith(cmd, 'DIR')
                obj.SimDir = cmd(4:6);
            elseif strcmp(cmd, 'DIS')
                data = sprintf('I%.3fW%.3fML', obj.SimInfused, obj.SimWithdrawn);
            elseif strcmp(cmd, 'RUN')
                if strcmp(obj.SimDir, 'WDR')
                    obj.SimStatus = 'W';
                else
                    obj.SimStatus = 'I';
                end
            elseif strcmp(cmd, 'STP')
                if pumping
                    % Stopping mid-dispense: bank the dispensed volume and pause.
                    if obj.SimStatus == 'W'
                        obj.SimWithdrawn = obj.SimWithdrawn + max(obj.SimVolume, 0.1);
                    else
                        obj.SimInfused = obj.SimInfused + max(obj.SimVolume, 0.1);
                    end
                    obj.SimStatus = 'P';
                else
                    obj.SimStatus = 'S';
                end
            elseif strcmp(cmd, 'CLDINF')
                obj.SimInfused = 0;
            elseif strcmp(cmd, 'CLDWDR')
                obj.SimWithdrawn = 0;
            else
                data = '?';
            end

            % Status in the reply reflects the state AFTER the command, the way
            % the real pump prompts.
            reply = ['0' obj.SimStatus data];
        end

    end
end
