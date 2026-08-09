classdef Intan_RHX_Mock < hw.Intan_RHX
    % Intan_RHX_Mock — scripted stand-in for the RHX TCP command server.
    %
    % Subclasses hw.Intan_RHX and overrides only the byte-level transport seam
    % (openSocket_/closeSocket_/writeRaw_/bytesAvailable_/readAvailable_) so the
    % full command logic runs with no socket and no Instrument Control Toolbox
    % (tcpserver is unavailable in this install). Every command written is
    % recorded in Log; "get" commands are answered from a scripted reply queue,
    % which is what makes the fire-and-forget "set"/"execute" contract and the
    % command grammar testable offline.
    %
    % Usage
    %   m = Intan_RHX_Mock();          % offline, sensible default replies
    %   m.connect();                   % consumes default 'get type'/'get runmode'
    %   m.resetLog();
    %   m.setReplies('get runmode', {'Return: RunMode Stop', ...
    %                                'Return: RunMode Record'});
    %   m.mode = hw.DeviceState.Record;
    %   assert(any(m.Log == "set runmode record"))
    %
    % Reply queues are sticky at the last element: once a queue is down to one
    % entry it repeats, mirroring hardware state that persists until changed.

    properties
        Log (1,:) string = strings(1,0)   % every command written, verbatim
    end

    properties (Access = private)
        replies_       % containers.Map: lower(command) -> cell queue of response strings
        pending_ char = ''  % bytes currently available for the client to read
    end

    methods

        function obj = Intan_RHX_Mock(host, port)
            arguments
                host (1,:) char = '127.0.0.1'
                port (1,1) double = 5000
            end
            % Always construct offline; the test scripts replies then connect().
            obj@hw.Intan_RHX(host, port, Connect = false);

            obj.replies_ = containers.Map('KeyType', 'char', 'ValueType', 'any');

            % Fast, deterministic timing for tests.
            obj.Timeout           = 0.3;    % fail fast if a reply was not scripted
            obj.ModeChangeTimeout = 0.5;
            obj.SettingsLoadWait  = 0;      % skip the multi-second settings pause
            obj.ModePollInterval  = 3600;   % suppress auto re-query; tests opt in per case

            % Default replies so connect() and Record flows work out of the box.
            obj.setReplies('get type',                        {'Return: Type ControllerStimRecord'});
            obj.setReplies('get sampleratehertz',             {'Return: SampleRateHertz 30000'});
            obj.setReplies('get runmode',                     {'Return: RunMode Stop'});
            obj.setReplies('get uploadinprogress',            {'Return: UploadInProgress False'});
            obj.setReplies('get filename.activefiletimestamp',{'Return: FileName.ActiveFileTimestamp 250101_120000'});
            obj.setReplies('get filename.basefilename',       {'Return: FileName.BaseFilename Subject'});
            obj.setReplies('get filename.path',               {'Return: FileName.Path C:/Data/Subject'});
        end

        % --- Scripting API -------------------------------------------------

        function setReplies(obj, cmd, responses)
            % setReplies(obj, cmd, responses)
            % Replace the reply queue for a command with the given cellstr.
            obj.replies_(lower(strtrim(cmd))) = responses(:).';
        end

        function queueReply(obj, cmd, response)
            % queueReply(obj, cmd, response)
            % Append one response to a command's reply queue.
            key = lower(strtrim(cmd));
            if isKey(obj.replies_, key)
                obj.replies_(key) = [obj.replies_(key), {response}];
            else
                obj.replies_(key) = {response};
            end
        end

        function queueUnsolicited(obj, response)
            % queueUnsolicited(obj, response)
            % Inject bytes as if the server sent them unprompted (desync test).
            obj.pending_ = [obj.pending_, char(response)];
        end

        function resetLog(obj)
            obj.Log = strings(1,0);
        end

        function forceModeExpiry(obj)
            % Invalidate the throttled mode cache so the next mode read queries.
            obj.modeCacheTic_ = [];
        end

        function n = logCount(obj, cmd)
            % n = logCount(obj, cmd) — number of logged commands equal to cmd.
            n = sum(obj.Log == string(cmd));
        end

    end

    methods (Access = protected)

        function openSocket_(~)
            % No socket in the mock.
        end

        function closeSocket_(~)
            % No socket in the mock.
        end

        function writeRaw_(obj, cmd)
            % Record the command and, for a "get", queue the scripted reply.
            obj.Log(end+1) = string(cmd);
            key = lower(strtrim(cmd));
            if startsWith(key, 'get ') && isKey(obj.replies_, key)
                q = obj.replies_(key);
                if ~isempty(q)
                    resp = q{1};
                    if numel(q) > 1          % sticky: keep the last reply
                        obj.replies_(key) = q(2:end);
                    end
                    obj.pending_ = [obj.pending_, char(resp)];
                end
            end
        end

        function n = bytesAvailable_(obj)
            n = numel(obj.pending_);
        end

        function s = readAvailable_(obj)
            s = strtrim(obj.pending_);
            obj.pending_ = '';
        end

    end

end
