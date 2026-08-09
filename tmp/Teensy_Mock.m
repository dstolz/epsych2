classdef Teensy_Mock < hw.Teensy
% Teensy_Mock - In-process EPsychTeensy firmware simulator for hw.Teensy.
%
% Overrides ONLY hw.Teensy's byte-level transport seam, so every line of
% protocol logic — handshake, descriptor parsing, the snapshot read cache,
% write coalescing, trigger pulses, mode caching — runs exactly as it would
% against a real board, with no serial port and no hardware support package.
%
% Mirrors tmp/Intan_RHX_Mock, which does the same for the TCP backend.
%
% Usage
%   iface = Teensy_Mock();              % connects immediately
%   iface.completeTrial(RespCode=1, RespLatency=250);
%   disp(iface.get_parameter('RespCode'))
%
% Properties
%   Log - Every command line the simulated firmware received, in order. The
%         main thing a test asserts on, because it is what proves reads were
%         batched into one SNAP and writes into one SETM.
%
% See also: hw.Teensy, tmp/smoke_test_teensy.m, firmware/EPsychTeensy

    properties
        Log (1,:) cell = {}    % commands received by the simulated firmware
        TickHz (1,1) double = 10000
    end

    properties (Access = private)
        names_   (1,:) cell = {}
        access_  (1,:) cell = {}
        types_   (1,:) cell = {}
        flags_   (1,:) cell = {}
        units_   (1,:) cell = {}
        values_                       % containers.Map: wire name -> value
        pending_ (1,:) cell = {}      % reply lines waiting to be read
        modeVal_ (1,1) double = 0
        micros_  (1,1) double = 0
        events_                       % Nx3 [micros, nameIndex, value]
        portOpen_ (1,1) logical = false
    end

    methods

        function obj = Teensy_Mock(options)
            % obj = Teensy_Mock(Name=Value)
            % Construct the simulator and connect.
            %
            % Name=Value
            %   BoxID (double)    - Box identifier used in the x_*_<BoxID> names. Default 1
            %   Connect (logical) - Connect on construction. Default true
            arguments
                options.BoxID (1,1) double = 1
                options.Connect (1,1) logical = true
            end

            obj@hw.Teensy('MOCK', Connect = false);

            obj.BootDelay = 0;
            obj.Timeout = 0.1;
            obj.defineParameters_(options.BoxID);

            if options.Connect
                obj.connect();
            end
        end

        function completeTrial(obj, options)
            % completeTrial(obj, Name=Value)
            % Simulate the board finishing a trial.
            %
            % Raises TrialComplete the way the firmware's trial state machine
            % would, so a test can drive the runtime's poll-then-read loop.
            %
            % Name=Value
            %   RespCode (double)    - uint32 epsych.BitMask value. Default 1 (Hit)
            %   RespLatency (double) - Response latency in ms. Default 250
            arguments
                obj
                options.RespCode (1,1) double = 1
                options.RespLatency (1,1) double = 250
            end
            obj.values_('RespCode') = options.RespCode;
            obj.values_('RespLatency') = options.RespLatency;
            obj.values_('InTrial') = 0;
            obj.values_('x_TrialComplete_1') = 1;
        end

        function pushEvent(obj, name, value)
            % pushEvent(obj, name, value)
            % Queue a timestamped input event, as a debounced edge would.
            idx = find(strcmp(obj.names_, name), 1);
            if isempty(idx)
                idx = 0;
            end
            obj.micros_ = obj.micros_ + 1234;
            obj.events_(end + 1, :) = [obj.micros_, idx, value];
        end

    end  % public methods


    methods (Access = protected)

        % --- Transport seam overrides --------------------------------------

        function openPort_(obj)
            % HW must be a scalar: hw.Parameter declares HW (1,1) and copies it
            % from the parent interface when a parameter is constructed.
            obj.HW = struct('Mock', true);
            obj.portOpen_ = true;
            obj.pending_ = {};
        end

        function closePort_(obj)
            obj.HW = [];
            obj.portOpen_ = false;
            obj.pending_ = {};
        end

        function writeLine_(obj, s)
            if ~obj.portOpen_
                error('Teensy_Mock:PortClosed', 'Write to a closed mock port.');
            end
            obj.Log{end + 1} = char(s);
            obj.micros_ = obj.micros_ + 500;
            obj.pending_ = [obj.pending_, obj.respond_(char(s))];
        end

        function n = bytesAvailable_(obj)
            n = numel(obj.pending_);
        end

        function s = readLine_(obj)
            if isempty(obj.pending_)
                s = '';
                return
            end
            s = obj.pending_{1};
            obj.pending_(1) = [];
        end

        function flushInput_(obj)
            obj.pending_ = {};
        end

    end  % protected transport seam


    methods (Access = private)

        function defineParameters_(obj, boxID)
            % defineParameters_(obj, boxID)
            % Build the parameter table this simulated board publishes.
            %
            % Deliberately includes the three names epsych.Runtime requires and
            % the conventional names the shipped GUIs look for, so the mock
            % exercises the same code paths a real session does.
            obj.values_ = containers.Map('KeyType', 'char', 'ValueType', 'any');
            obj.events_ = zeros(0, 3);

            %              name                        access type flags unit  default
            spec = {
                sprintf('x_NewTrial_%d', boxID),      'RW', 'B', 'T', '-',  0
                sprintf('x_ResetTrig_%d', boxID),     'RW', 'B', 'T', '-',  0
                sprintf('x_TrialComplete_%d', boxID), 'R',  'B', '-', '-',  0
                'RespCode',                           'R',  'I', '-', '-',  0
                'RespLatency',                        'R',  'F', '-', 'ms', 0
                'InTrial',                            'R',  'B', '-', '-',  0
                'Lick_1',                             'R',  'B', '-', '-',  0
                'TrialType',                          'RW', 'I', '-', '-',  0
                'RewardDur',                          'RW', 'F', '-', 'ms', 50
                'CueLevel',                           'RW', 'F', '-', 'dB', 60
                sprintf('_TrigState~%d', boxID),      'R',  'B', 'H', '-',  0
                sprintf('_TrialNum~%d', boxID),       'R',  'I', 'H', '-',  0
                };

            for i = 1:size(spec, 1)
                obj.names_{end + 1} = spec{i, 1};
                obj.access_{end + 1} = spec{i, 2};
                obj.types_{end + 1} = spec{i, 3};
                obj.flags_{end + 1} = spec{i, 4};
                obj.units_{end + 1} = spec{i, 5};
                obj.values_(spec{i, 1}) = spec{i, 6};
            end
        end

        function reply = respond_(obj, cmd)
            % reply = respond_(obj, cmd)
            % Produce the reply line(s) for one command, as the firmware would.
            tok = strsplit(strtrim(cmd));
            switch tok{1}
                case 'ID?'
                    reply = {sprintf(['ID EPsychTeensy PROTO=%d FW=1.0.0 ' ...
                        'BOARD=Teensy4.1-Mock SN=MOCK0001 BOXES=1 TICKHZ=%d'], ...
                        obj.PROTOCOL_VERSION, obj.TickHz)};

                case 'DESC?'
                    reply = obj.describe_();

                case 'GET'
                    reply = obj.doGet_(tok);

                case 'SET'
                    reply = obj.doSet_(tok);

                case 'SETM'
                    reply = obj.doSetM_(tok);

                case 'SNAP'
                    reply = obj.doSnap_();

                case 'TRG'
                    reply = obj.doTrigger_(tok);

                case 'MODE'
                    obj.modeVal_ = str2double(tok{2});
                    reply = {'OK'};

                case 'MODE?'
                    reply = {sprintf('MODE %d', obj.modeVal_)};

                case 'EVT?'
                    reply = obj.doEvents_();

                case 'SYNC'
                    reply = {sprintf('SYNC %d', obj.micros_)};

                case 'RESET'
                    obj.events_ = zeros(0, 3);
                    reply = {'OK'};

                otherwise
                    reply = {sprintf('ERR 1 parse "%s"', tok{1})};
            end
        end

        function lines = describe_(obj)
            lines = {'DESC BEGIN'};
            for i = 1:numel(obj.names_)
                lines{end + 1} = sprintf('P %s %s %s %s -inf inf %s', ...
                    obj.names_{i}, obj.access_{i}, obj.types_{i}, ...
                    obj.flags_{i}, obj.units_{i});
            end
            lines{end + 1} = 'DESC END';
        end

        function reply = doGet_(obj, tok)
            if numel(tok) < 2 || ~obj.values_.isKey(tok{2})
                reply = {sprintf('ERR 2 unknown parameter "%s"', obj.tokenOrEmpty_(tok, 2))};
                return
            end
            reply = {sprintf('VAL %s %s', tok{2}, obj.fmt_(obj.values_(tok{2})))};
        end

        function reply = doSet_(obj, tok)
            if numel(tok) < 3 || ~obj.values_.isKey(tok{2})
                reply = {sprintf('ERR 2 unknown parameter "%s"', obj.tokenOrEmpty_(tok, 2))};
                return
            end
            obj.values_(tok{2}) = str2double(strsplit(tok{3}, ','));
            reply = {'OK'};
        end

        function reply = doSetM_(obj, tok)
            for i = 2:numel(tok)
                kv = strsplit(tok{i}, '=');
                if numel(kv) ~= 2 || ~obj.values_.isKey(kv{1})
                    reply = {sprintf('ERR 2 unknown parameter "%s"', kv{1})};
                    return
                end
                obj.values_(kv{1}) = str2double(strsplit(kv{2}, ','));
            end
            reply = {'OK'};
        end

        function reply = doSnap_(obj)
            parts = sprintf('SNAP %d MODE=%d NEVT=%d', ...
                obj.micros_, obj.modeVal_, size(obj.events_, 1));
            for i = 1:numel(obj.names_)
                if strcmp(obj.access_{i}, 'W')
                    continue
                end
                parts = [parts sprintf(' %s=%s', obj.names_{i}, obj.fmt_(obj.values_(obj.names_{i})))];
            end
            reply = {parts};
        end

        function reply = doTrigger_(obj, tok)
            if numel(tok) < 2 || ~obj.values_.isKey(tok{2})
                reply = {sprintf('ERR 2 unknown parameter "%s"', obj.tokenOrEmpty_(tok, 2))};
                return
            end

            % Mimic the firmware's trial state machine closely enough that the
            % runtime's reset -> write -> trigger -> poll loop behaves correctly.
            if startsWith(tok{2}, 'x_ResetTrig_')
                obj.values_('x_TrialComplete_1') = 0;
                obj.values_('InTrial') = 0;
                obj.setIfPresent_('_TrigState~1', 0);
                obj.events_ = zeros(0, 3);
            elseif startsWith(tok{2}, 'x_NewTrial_')
                obj.values_('InTrial') = 1;
                obj.values_('x_TrialComplete_1') = 0;
                obj.setIfPresent_('_TrigState~1', 1);
                obj.bumpIfPresent_('_TrialNum~1');
            end

            reply = {sprintf('OK %d', obj.micros_)};
        end

        function lines = doEvents_(obj)
            lines = {'EVT BEGIN'};
            for i = 1:size(obj.events_, 1)
                idx = obj.events_(i, 2);
                if idx >= 1 && idx <= numel(obj.names_)
                    name = obj.names_{idx};
                else
                    name = '?';
                end
                lines{end + 1} = sprintf('E %d %s %g', obj.events_(i, 1), name, obj.events_(i, 3));
            end
            lines{end + 1} = 'EVT END';
            obj.events_ = zeros(0, 3);
        end

        function setIfPresent_(obj, name, value)
            if obj.values_.isKey(name)
                obj.values_(name) = value;
            end
        end

        function bumpIfPresent_(obj, name)
            if obj.values_.isKey(name)
                obj.values_(name) = obj.values_(name) + 1;
            end
        end

    end  % private methods


    methods (Static, Access = private)

        function s = fmt_(v)
            % s = fmt_(v)
            % Render a stored value the way the firmware would.
            if ischar(v)
                s = v;
            elseif isscalar(v)
                s = sprintf('%.6g', double(v));
            else
                s = strjoin(arrayfun(@(x) sprintf('%.6g', double(x)), v(:)', ...
                    UniformOutput = false), ',');
            end
        end

        function s = tokenOrEmpty_(tok, idx)
            if numel(tok) >= idx
                s = tok{idx};
            else
                s = '';
            end
        end

    end  % private static methods

end
