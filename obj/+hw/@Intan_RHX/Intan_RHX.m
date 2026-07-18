classdef Intan_RHX < hw.Interface

    % obj = hw.Intan_RHX(host, port, Name=Value)
    % Hardware interface for Intan RHX software via TCP command interface.
    %
    % Communicates with the Intan RHX software TCP command server
    % (default localhost:5000) to control run mode, load a settings file,
    % name the recording, and read/write named parameters using the RHX
    % command grammar.
    %
    % RHX protocol notes (these shape the implementation):
    %   - "get" returns "Return: <Name> <value>"; "set" and "execute" reply
    %     ONLY on a syntax error and are otherwise silent. Waiting for a reply
    %     after a set/execute therefore blocks until timeout — so writes here
    %     are fire-and-forget and confirmation is done by polling "get" where
    %     it matters (e.g. runmode).
    %   - "set"/"execute" values may not contain spaces (exactly two words
    %     after "set"), so filename.path/basefilename and the settings-file
    %     path must be space-free. Paths use forward slashes.
    %   - filename.* and loadsettingsfile have no effect while the board is
    %     running; the board is forced to Stop before those are sent.
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
    %   Host, Port, Timeout - Connection settings.
    %   IsConnected         - True when TCP connection is open.
    %   Module              - Single hw.Module representing the RHX device.
    %   mode                - Current hw.DeviceState (maps to RHX runmode).
    %   RecordingRootDir    - Root directory for recordings (seeded by RunExpt
    %                         from the 'ep_RunExpt_Intan' pref group).
    %   SettingsFile        - RHX .xml settings file loaded at connect.
    %   ControllerType      - RHX controller type reported by "get type".
    %   ActiveRecordingFile - Best-effort full path of the active recording.
    %
    % Methods
    %   connect, disconnect, close_interface - Connection management.
    %   get_parameter, set_parameter - Named parameter I/O via RHX commands.
    %   trigger - Issue manualstimtriggerpulse (Stim/Record controllers only).
    %   prepareRecording - Point RHX at the session's data filename (called by
    %                      RunExpt just before the run enters Record mode).
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

        % Machine-level recording configuration, seeded by RunExpt from the
        % 'ep_RunExpt_Intan' preference group (see RunExpt.configureIntanRecorder_).
        % Deliberately plain properties, NOT hw.Parameters: they are per-machine
        % and must not serialize into a portable .eprot. The setters normalize
        % backslashes to forward slashes and reject embedded spaces, which the
        % RHX set/execute grammar cannot express.
        RecordingRootDir (1,:) char = ''  % Recording root; empty => RUNTIME.dfltDataPath
        SettingsFile (1,:) char = ''      % RHX .xml settings file; empty => load none

        % Timing knobs (exposed so tests can shorten them).
        ModeChangeTimeout (1,1) double = 2     % seconds to confirm a runmode change
        ModePollInterval  (1,1) double = 0.25  % min seconds between live runmode queries
        SettingsLoadWait  (1,1) double = 5     % seconds to wait after loadsettingsfile
    end

    properties (SetObservable, AbortSet)
        mode  % Current device run state (hw.DeviceState)
    end

    properties (SetAccess = protected)
        Module   % hw.Module array
        ControllerType (1,:) char = ''       % RHX controller type from "get type"
        ActiveFileTimestamp (1,:) char = ''  % RHX _YYMMDD_HHMMSS suffix of the active file
        ActiveRecordingFile (1,:) char = ''  % Best-effort full path of the active recording
    end

    properties (Constant)
        Type = "Intan_RHX"
    end

    properties (Access = private)
        client_  % tcpclient handle, or []
    end

    properties (Access = protected)
        % State reachable by test subclasses (tmp/Intan_RHX_Mock).
        modeCache_ (1,1) hw.DeviceState = hw.DeviceState.Idle  % last known mode when offline/throttled
        modeCacheTic_ = []                 % tic of last live runmode query; [] forces a query
        settingsFileLoaded_ (1,:) char = ''% path of the settings file already loaded this connection
        isStimRecord_ (1,1) logical = false% true for a Stim/Record controller (gates .rhs and triggers)
        warnedNoStim_ (1,1) logical = false% latch so trigger() warns once, not every trial
        recordingPath_ (1,:) char = ''     % last filename.path pushed
        recordingBase_ (1,:) char = ''     % last filename.basefilename pushed
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

        function disconnect(obj)
            % disconnect(obj)
            % Release the TCP connection. Safe to call when already offline.
            if ~obj.IsConnected
                return
            end
            obj.close_interface();
        end

        function set.mode(obj, newMode)
            obj.applyMode_(newMode);
        end

        function m = get.mode(obj)
            m = obj.queryMode_();
        end

        function set.RecordingRootDir(obj, val)
            obj.RecordingRootDir = hw.Intan_RHX.normalizePathValue_(val, 'Intan recording path');
        end

        function set.SettingsFile(obj, val)
            obj.SettingsFile = hw.Intan_RHX.normalizePathValue_(val, 'Intan settings file');
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
            %   includeInvisible / silenceParameterNotFound - Forwarded to
            %                find_parameter when name is a string.
            %
            % Returns
            %   value - Value or cell array of values matching name order.
            arguments
                obj
                name
                options.ReturnRaw (1,1) logical = false
                options.includeInvisible (1,1) logical = false
                options.silenceParameterNotFound (1,1) logical = false
            end

            if isa(name, 'hw.Parameter')
                params = name;
            else
                params = obj.find_parameter(name, ...
                    includeInvisible = options.includeInvisible, ...
                    silenceParameterNotFound = options.silenceParameterNotFound);
            end

            if ~obj.IsConnected
                value = cell(1, numel(params));
                if isscalar(value)
                    value = value{1};
                end
                return
            end

            value = cell(1, numel(params));
            for i = 1:numel(params)
                resp = obj.sendGet_(params(i).Name);
                if options.ReturnRaw
                    value{i} = resp;
                else
                    value{i} = obj.parseReturnValue_(resp);
                end
            end

            % Return scalar directly when only one parameter
            if isscalar(value)
                value = value{1};
            end
        end

        function result = set_parameter(obj, name, value)
            % result = set_parameter(obj, name, value)
            % Write value(s) to one or more named RHX parameters via TCP.
            %
            % RHX does not acknowledge a successful "set" (it replies only on a
            % syntax error), so the returned logical reflects "sent", not
            % "confirmed by the hardware". Values containing spaces cannot be
            % expressed in the RHX grammar and raise hw:Intan_RHX:MalformedSet.
            %
            % Parameters
            %   name  - Parameter name string, cell array, or hw.Parameter handle/array.
            %   value - Scalar or array matching numel(name).
            %
            % Returns
            %   result - Logical array; true per parameter that was sent.
            if isa(name, 'hw.Parameter')
                params = name;
            else
                params = obj.find_parameter(name);
            end

            result = true(1, numel(params));

            if ~obj.IsConnected
                return
            end

            % Normalize into one cell entry per parameter. A char/string value
            % is a single value, not one entry per character, so it must not be
            % passed through num2cell.
            if ~iscell(value)
                if ischar(value) || isscalar(value)
                    value = {value};
                else
                    value = num2cell(value);
                end
            end
            if isscalar(value) && numel(params) > 1
                value = repmat(value, 1, numel(params));
            end

            for i = 1:numel(params)
                obj.sendSet_(params(i).Name, value{i});
            end
        end

        function t = trigger(obj, name)
            % t = trigger(obj, name)
            % t = trigger(obj, P)
            % Issue a manualstimtriggerpulse for the given parameter.
            %
            % Manual stim triggers are a Stim/Record controller feature; on a
            % plain Recording controller the command is silently ignored by
            % RHX, so it is suppressed here (with a single warning) to avoid a
            % false belief that a trigger was delivered.
            %
            % The trigger key (f1-f8) is taken from P.UserData.TriggerKey,
            % defaulting to 'f1'.
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

            if ~obj.IsConnected
                return
            end

            if ~obj.isStimRecord_
                if ~obj.warnedNoStim_
                    vprintf(0, 1, ['Intan_RHX: manual stim triggers require a Stim/Record ' ...
                        'controller (this is "%s"); trigger ignored.'], obj.ControllerType);
                    obj.warnedNoStim_ = true;
                end
                return
            end

            key = 'f1';
            if isstruct(P.UserData) && isfield(P.UserData, 'TriggerKey') ...
                    && ~isempty(P.UserData.TriggerKey)
                key = lower(char(P.UserData.TriggerKey));
            end

            obj.sendExecute_('manualstimtriggerpulse', key);
        end

    end  % public methods


    methods
        % Implemented in a separate file (overrides hw.Interface.prepareRecording)
        prepareRecording(obj, runtime)
    end


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


    methods (Static, Access = private)

        function p = normalizePathValue_(p, label)
            % p = normalizePathValue_(p, label)
            % Normalize a filesystem path for use in RHX commands: forward
            % slashes, no trailing separator. Errors on embedded spaces, which
            % the RHX set/execute grammar cannot express.
            p = strtrim(char(p));
            if isempty(p)
                return
            end
            p = strrep(p, '\', '/');
            while endsWith(p, '/') && strlength(p) > 1
                p = p(1:end-1);
            end
            if any(isspace(p))
                error('hw:Intan_RHX:PathHasSpaces', ...
                    ['%s "%s" contains spaces, which the RHX TCP command grammar ' ...
                     'cannot express. Choose a space-free location or rename.'], label, p);
            end
        end

    end  % private static methods


    methods (Access = protected)

        function setup_interface(obj)
            % setup_interface(obj)
            % Open the RHX connection, discover the controller type, load the
            % configured settings file, and sync the current run mode.
            obj.openSocket_();

            % Create single module representing the RHX device
            if isempty(obj.Module)
                obj.Module = hw.Module(obj, 'RHX', 'RHX', uint8(1));
            end

            obj.IsConnected = true;

            % Cache controller type: gates .rhs/.rhd naming and the validity of
            % manual stim triggers.
            obj.ControllerType = obj.parseReturnValue_(obj.sendGet_('type'));
            obj.isStimRecord_ = strcmpi(strtrim(obj.ControllerType), 'ControllerStimRecord');
            vprintf(1, 'Intan_RHX: controller type "%s" (%s files)', obj.ControllerType, obj.fileExt_());

            % Load the machine-configured settings file (no-op if unset).
            obj.applySettingsFile_();

            % Sync cached mode from hardware
            obj.modeCache_ = obj.queryMode_();
            obj.modeCacheTic_ = tic;
        end

        function close_interface(obj)
            % close_interface(obj)
            % Close TCP connection and release resources.
            obj.closeSocket_();
            obj.IsConnected = false;
        end

        % --- Byte-level transport seam ------------------------------------
        % These wrap the tcpclient so a test subclass can script the RHX
        % server without a real socket (see tmp/Intan_RHX_Mock).

        function openSocket_(obj)
            % openSocket_(obj)
            % Open the tcpclient. No terminator is configured: RHX neither
            % sends nor expects one (its reference client compares replies by
            % exact equality), and this class reads/writes raw bytes.
            obj.client_ = tcpclient(obj.Host, obj.Port, 'Timeout', obj.Timeout);
        end

        function closeSocket_(obj)
            % closeSocket_(obj)
            % Delete the tcpclient handle if present.
            if ~isempty(obj.client_) && isvalid(obj.client_)
                delete(obj.client_);
            end
            obj.client_ = [];
        end

        function writeRaw_(obj, cmd)
            % writeRaw_(obj, cmd)
            % Write a command as raw bytes with no terminator (matching Intan's
            % reference client; a trailing newline risks being tokenized into a
            % "set" value).
            write(obj.client_, uint8(cmd), 'uint8');
        end

        function n = bytesAvailable_(obj)
            % n = bytesAvailable_(obj)
            n = obj.client_.NumBytesAvailable;
        end

        function s = readAvailable_(obj)
            % s = readAvailable_(obj)
            % Read and return all currently available bytes, trimmed.
            s = strtrim(char(read(obj.client_, obj.bytesAvailable_(), 'uint8')));
        end

    end  % protected methods


    methods (Access = private)

        % --- Command helpers ----------------------------------------------

        function drainStale_(obj)
            % drainStale_(obj)
            % Discard any unsolicited bytes before issuing a command. Because
            % "set"/"execute" reply only on a syntax error, a rejected command
            % leaves an error response that the next "get" would otherwise
            % misread as its own answer. Draining resynchronizes the socket and
            % surfaces the rejected command (one command late).
            if ~obj.IsConnected || obj.bytesAvailable_() == 0
                return
            end
            stale = obj.readAvailable_();
            if ~isempty(stale)
                vprintf(0, 1, 'Intan_RHX: discarding unsolicited response (likely a rejected command): %s', stale);
            end
        end

        function response = sendGet_(obj, param)
            % response = sendGet_(obj, param)
            % Send "get <param>" and return the trimmed response, or '' on
            % timeout / offline. A "get" is the only command RHX always answers.
            response = '';
            if ~obj.IsConnected
                return
            end
            obj.drainStale_();
            obj.writeRaw_(sprintf('get %s', lower(param)));

            deadline = tic;
            while obj.bytesAvailable_() == 0
                if toc(deadline) > obj.Timeout
                    vprintf(0, 1, 'Intan_RHX: timed out waiting for "get %s"', param);
                    return
                end
                pause(0.001);
            end
            response = obj.readAvailable_();
        end

        function sendSet_(obj, param, value)
            % sendSet_(obj, param, value)
            % Fire-and-forget "set <param> <value>". RHX replies to "set" ONLY
            % on a syntax error; reading for a reply here is what previously made
            % every set block for Timeout seconds.
            if ~obj.IsConnected
                return
            end
            valStr = char(string(value));
            assert(~any(isspace(valStr)) && ~any(isspace(strtrim(param))), ...
                'hw:Intan_RHX:MalformedSet', ...
                'RHX "set" accepts exactly two words; "set %s %s" would be a syntax error.', ...
                param, valStr);
            obj.drainStale_();
            obj.writeRaw_(sprintf('set %s %s', lower(param), valStr));
            vprintf(3, 'Intan_RHX: set %s %s', param, valStr);
        end

        function sendExecute_(obj, action, param)
            % sendExecute_(obj, action, param)
            % Fire-and-forget "execute <action> [param]".
            arguments
                obj
                action (1,:) char
                param (1,:) char = ''
            end
            if ~obj.IsConnected
                return
            end
            obj.drainStale_();
            if isempty(param)
                cmd = sprintf('execute %s', action);
            else
                assert(~any(isspace(strtrim(param))), 'hw:Intan_RHX:MalformedExecute', ...
                    'RHX "execute %s" parameter must not contain spaces: "%s".', action, param);
                cmd = sprintf('execute %s %s', action, param);
            end
            obj.writeRaw_(cmd);
            vprintf(3, 'Intan_RHX: %s', cmd);
        end

        % --- Response parsing ---------------------------------------------

        function value = parseReturnValue_(~, response)
            % value = parseReturnValue_(obj, response)
            % Parse a 'Return: <ParameterName> <value>' response string.
            % Returns the value portion as char, or '' on unexpected format.
            if isempty(response)
                value = '';
                return
            end
            tokens = regexp(response, '^Return:\s+\S+\s+(.+)$', 'tokens', 'once');
            if isempty(tokens)
                value = '';
            else
                value = strtrim(tokens{1});
            end
        end

        % --- Run mode ------------------------------------------------------

        function applyMode_(obj, newMode)
            % applyMode_(obj, newMode)
            % Translate hw.DeviceState to an RHX runmode command, send it, and
            % confirm the change took (RHX runmode changes are not immediate).
            obj.modeCache_ = newMode;
            obj.modeCacheTic_ = tic;
            if ~obj.IsConnected
                return
            end

            switch newMode
                case hw.DeviceState.Record
                    target = 'record';
                case hw.DeviceState.Preview
                    target = 'run';
                case {hw.DeviceState.Idle, hw.DeviceState.Standby, ...
                        hw.DeviceState.Stop, hw.DeviceState.Pause, hw.DeviceState.Error}
                    target = 'stop';
                otherwise
                    vprintf(0, 1, 'Intan_RHX: unmapped DeviceState (%d); runmode unchanged.', double(newMode));
                    return
            end

            % Docs: runmode is aborted with an error if a USB upload is in flight.
            if ~obj.waitForUploadIdle_()
                vprintf(0, 1, 'Intan_RHX: USB upload in progress; runmode "%s" not sent.', target);
                return
            end

            obj.sendSet_('runmode', target);

            if ~obj.waitForMode_(target)
                vprintf(0, 1, 'Intan_RHX: RunMode did not reach "%s" within %g s.', target, obj.ModeChangeTimeout);
                return
            end

            if strcmp(target, 'record')
                obj.captureActiveFile_();
            end
        end

        function m = queryMode_(obj)
            % m = queryMode_(obj)
            % Return the current run state as hw.DeviceState. Throttled: the
            % run-time watchdog reads this every timer tick, and a blocking TCP
            % round-trip per tick would dominate the trial loop. 250 ms of
            % staleness is irrelevant to a check whose only action is to stop.
            if ~obj.IsConnected
                m = obj.modeCache_;
                return
            end
            if ~isempty(obj.modeCacheTic_) && toc(obj.modeCacheTic_) < obj.ModePollInterval
                m = obj.modeCache_;
                return
            end

            switch obj.queryRunModeRaw_()
                case 'record'
                    m = hw.DeviceState.Record;
                case 'run'
                    m = hw.DeviceState.Preview;   % round-trips with applyMode_'s Preview->run
                case 'trigger'
                    m = hw.DeviceState.Standby;
                case 'stop'
                    m = hw.DeviceState.Idle;
                otherwise
                    % Never invent Idle from a garbled/empty reply: the watchdog
                    % treats Idle as "stop the session".
                    m = obj.modeCache_;
                    return
            end
            obj.modeCache_ = m;
            obj.modeCacheTic_ = tic;
        end

        function tok = queryRunModeRaw_(obj)
            % tok = queryRunModeRaw_(obj)
            % Query "get runmode" and return the lowercased mode token
            % (record|run|trigger|stop), or '' if unavailable/unparseable.
            tok = '';
            if ~obj.IsConnected
                return
            end
            resp = obj.sendGet_('runmode');
            m = regexp(resp, 'Return:\s+RunMode\s+(\w+)', 'tokens', 'once');
            if ~isempty(m)
                tok = lower(m{1});
            end
        end

        function tf = waitForMode_(obj, target)
            % tf = waitForMode_(obj, target)
            % Poll "get runmode" until it reads target (docs: runmode changes
            % are not immediate) or ModeChangeTimeout elapses.
            t0 = tic;
            tf = false;
            while toc(t0) < obj.ModeChangeTimeout
                if strcmpi(obj.queryRunModeRaw_(), target)
                    tf = true;
                    return
                end
                pause(0.02);
            end
        end

        function tf = waitForUploadIdle_(obj)
            % tf = waitForUploadIdle_(obj)
            % Wait until "get uploadinprogress" is False. Uploads are a
            % Stim/Record feature; on other controllers this is a no-op so the
            % runmode command is not needlessly delayed.
            tf = true;
            if ~obj.isStimRecord_
                return
            end
            t0 = tic;
            while toc(t0) < obj.ModeChangeTimeout
                tokv = obj.parseReturnValue_(obj.sendGet_('uploadinprogress'));
                if isempty(tokv) || strcmpi(tokv, 'false')
                    return
                end
                pause(0.05);
            end
            tf = false;
        end

        function ensureStopped_(obj)
            % ensureStopped_(obj)
            % Force the board to Stop, required before filename.* or
            % loadsettingsfile take effect.
            if ~obj.IsConnected
                return
            end
            if strcmp(obj.queryRunModeRaw_(), 'stop')
                return
            end
            obj.sendSet_('runmode', 'stop');
            obj.waitForMode_('stop');
        end

        % --- Settings file & recording target -----------------------------

        function applySettingsFile_(obj)
            % applySettingsFile_(obj)
            % Load SettingsFile into RHX if set and not already loaded this
            % connection. Reloading is a no-op unless the pref changed, so
            % "load once at connect" holds while still honoring a mid-session
            % change (loadsettingsfile requires the board stopped).
            sf = obj.SettingsFile;
            if isempty(sf) || ~obj.IsConnected
                return
            end
            if strcmp(sf, obj.settingsFileLoaded_)
                return
            end
            obj.ensureStopped_();
            obj.sendExecute_('loadsettingsfile', sf);
            % Docs: loading may take a few seconds; pause before further commands.
            pause(obj.SettingsLoadWait);
            obj.settingsFileLoaded_ = sf;
            vprintf(1, 'Intan_RHX: loaded settings file %s', sf);
        end

        function [path, base] = deriveRecordingTarget_(~, root, dataFilename)
            % [path, base] = deriveRecordingTarget_(obj, root, dataFilename)
            % Mirror the video recorder's layout (videoRecordingFilename):
            % <root>/<subjectFolder>/, basefilename = the data file's stem, so
            % the .rhd pairs by prefix with the .mat and .ts.
            [dataDir, name] = fileparts(char(dataFilename));
            [~, subjectFolder] = fileparts(dataDir);
            base = char(name);
            path = strrep(char(fullfile(char(root), subjectFolder)), '\', '/');
        end

        function setRecordingTarget_(obj, path, base)
            % setRecordingTarget_(obj, path, base)
            % Push filename.path/basefilename and remember them for building
            % ActiveRecordingFile once RHX assigns the timestamp.
            obj.recordingPath_ = path;
            obj.recordingBase_ = base;
            obj.sendSet_('filename.path', path);
            obj.sendSet_('filename.basefilename', base);
        end

        function captureActiveFile_(obj)
            % captureActiveFile_(obj)
            % After a Record confirm, read the timestamp RHX assigned to the
            % file and log the reconstructed on-disk name. The timestamp may lag
            % the runmode confirmation briefly, so poll for it.
            ts = '';
            t0 = tic;
            while toc(t0) < obj.ModeChangeTimeout
                ts = obj.parseReturnValue_(obj.sendGet_('filename.activefiletimestamp'));
                if ~isempty(ts) && ~strcmpi(ts, 'RecordingNotStarted')
                    break
                end
                pause(0.05);
            end
            obj.ActiveFileTimestamp = ts;
            if isempty(ts) || strcmpi(ts, 'RecordingNotStarted')
                return
            end

            base = obj.recordingBase_;
            path = obj.recordingPath_;
            if isempty(base)
                base = obj.parseReturnValue_(obj.sendGet_('filename.basefilename'));
                path = obj.parseReturnValue_(obj.sendGet_('filename.path'));
            end
            % Note: with createnewdirectory=True (RHX default) the file is
            % additionally nested under a timestamped directory; this is the
            % file leaf name, sufficient for pairing/logging.
            obj.ActiveRecordingFile = sprintf('%s/%s_%s%s', path, base, ts, obj.fileExt_());
            vprintf(0, 'Intan_RHX: recording to %s', obj.ActiveRecordingFile);
        end

        function ext = fileExt_(obj)
            % ext = fileExt_(obj)
            % '.rhs' for a Stim/Record controller, otherwise '.rhd'.
            if obj.isStimRecord_
                ext = '.rhs';
            else
                ext = '.rhd';
            end
        end

        function tf = isLocalHost_(obj)
            % tf = isLocalHost_(obj)
            % True when Host refers to this machine, so local filesystem checks
            % (e.g. creating the recording directory) are meaningful.
            h = lower(strtrim(obj.Host));
            local = {'127.0.0.1', 'localhost', '::1'};
            cn = lower(strtrim(getenv('COMPUTERNAME')));
            if ~isempty(cn)
                local{end+1} = cn;
            end
            tf = ismember(h, local);
        end

    end  % private methods

end
