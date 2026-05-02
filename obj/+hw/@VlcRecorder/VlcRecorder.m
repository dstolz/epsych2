classdef VlcRecorder < hw.Interface
    % obj = hw.VlcRecorder(host, port, timeout)
    % hw.Interface implementation for VLC webcam recording via the RC socket.
    %
    % Connects to a running VLC instance using the RC (remote control) TCP
    % interface and exposes playback and recording controls as hw.Parameters
    % and triggers. VLC must already be running with the RC interface
    % enabled, e.g.:
    %   vlc --extraintf rc --rc-host 127.0.0.1:4212 --rc-quiet
    %
    % Parameters
    %   host    - IP address or hostname of the VLC RC interface (default: '127.0.0.1').
    %   port    - TCP port of the VLC RC interface (default: 4212).
    %   timeout - Connection timeout in seconds (default: 5).
    %
    % Properties
    %   Module      - Single hw.Module containing all interface parameters.
    %   Type        - Constant identifier 'VlcRecorder'.
    %   IsConnected - True when the RC socket connection is open.
    %
    % Parameters exposed (via all_parameters):
    %   MediaFile     - (String, Write)   Media URI or file path to add to VLC.
    %   Volume        - (Integer, Any)    Playback volume 0–200 (100 = unity gain).
    %   RecordingFile - (File, Write)     Output file path injected as :sout when
    %                                     MediaFile is set. Leave empty for no file output.
    %
    % Triggers (via trigger()):
    %   Play, Stop, Pause, StartRecord, StopRecord
    %
    % Notes
    %   VLC volume is on a 0–512 scale where 256 = 100%. Setting Volume=100
    %   sends VLC command 'volume 256'.
    %   VLC's record command is a toggle. StartRecord and StopRecord are
    %   idempotent — they track state internally and only send the command
    %   when the state needs to change.
    %   RecordingFile injects a per-item :sout MRL option when MediaFile is
    %   set. It has no effect on the current media; set it before setting
    %   MediaFile.
    %
    % Example
    %   obj = hw.VlcRecorder('127.0.0.1', 4212);
    %   obj.connect();
    %   obj.set_parameter('RecordingFile', 'C:\data\capture.ts');
    %   obj.set_parameter('MediaFile', 'dshow://');
    %   obj.trigger('Play');
    %   obj.trigger('StartRecord');
    %   pause(30);
    %   obj.trigger('StopRecord');
    %   obj.trigger('Stop');
    %
    % See also: documentation/hw/hw_Interface.md, hw.Module, hw.Parameter


    properties (SetAccess = protected)
        HW = []  % tcpclient handle for the VLC RC socket

        Module
    end

    properties
        IsConnected (1,1) logical = false
    end

    properties (Constant)
        Type = 'VlcRecorder'
    end

    properties (SetObservable, AbortSet)
        mode
    end

    properties (Access = private)
        host_    (1,1) string  = "127.0.0.1"  % RC interface host address
        port_    (1,1) double  = 4212          % RC interface TCP port
        timeout_ (1,1) double  = 5             % connection timeout in seconds
        isRecording_ (1,1) logical = false     % cached record-toggle state
    end


    methods
        function obj = VlcRecorder(host, port, timeout)
            % obj = hw.VlcRecorder(host, port, timeout)
            % Construct a VLC RC interface without connecting.
            % Inputs:
            %   host    - Optional RC host address (default '127.0.0.1').
            %   port    - Optional RC TCP port (default 4212).
            %   timeout - Optional connection timeout in seconds (default 5).
            arguments
                host    {mustBeTextScalar} = "127.0.0.1"
                port    (1,1) double {mustBePositive, mustBeInteger} = 4212
                timeout (1,1) double {mustBePositive} = 5
            end

            obj.host_    = string(host);
            obj.port_    = port;
            obj.timeout_ = timeout;
            obj.Module   = hw.Module.empty(1, 0);
        end

        function connect(obj)
            % obj.connect()
            % Open a TCP connection to the VLC RC interface and set up parameters.
            % Sets IsConnected to true on success.
            if obj.IsConnected
                return
            end

            obj.setup_interface();

            obj.HW = tcpclient(char(obj.host_), obj.port_, ...
                'Timeout', obj.timeout_);
            configureTerminator(obj.HW, 'LF');

            pause(0.2);
            obj.readAvailable_();

            obj.IsConnected = true;
        end

        function disconnect(obj)
            % obj.disconnect()
            % Close the TCP connection to the VLC RC interface.
            if ~obj.IsConnected
                return
            end
            obj.close_interface();
        end

        function result = trigger(obj, name)
            % result = obj.trigger(name)
            % Send a named trigger event to VLC via the RC interface.
            % Inputs:
            %   name - Trigger name: 'Play', 'Stop', 'Pause', 'StartRecord', or 'StopRecord'.
            % Returns:
            %   result - 1 on success, 0 on unrecognised trigger name.
            result = 1;
            switch name
                case 'Play'
                    obj.sendCommand_('play');
                case 'Stop'
                    obj.sendCommand_('stop');
                    obj.isRecording_ = false;
                case 'Pause'
                    obj.sendCommand_('pause');
                case 'StartRecord'
                    if ~obj.isRecording_
                        obj.sendCommand_('record');
                        obj.isRecording_ = true;
                    end
                case 'StopRecord'
                    if obj.isRecording_
                        obj.sendCommand_('record');
                        obj.isRecording_ = false;
                    end
                otherwise
                    vprintf(0, 1, 'hw.VlcRecorder: unknown trigger "%s"', name);
                    result = 0;
            end
        end

        function result = set_parameter(obj, name, value)
            % result = obj.set_parameter(name, value)
            % Apply a parameter update to VLC via the RC interface.
            % Inputs:
            %   name  - Parameter name or hw.Parameter handle.
            %   value - New value to apply.
            % Returns:
            %   result - 1 on success.
            if isa(name, 'hw.Parameter')
                paramName = name.Name;
            else
                paramName = char(name);
            end

            switch paramName
                case 'Volume'
                    vlcVol = round(double(value) * 2.56);  % 100% -> 256 on VLC scale
                    vlcVol = max(0, min(512, vlcVol));
                    obj.sendCommand_(sprintf('volume %d', vlcVol));

                case 'MediaFile'
                    recFile = '';
                    P = obj.find_parameter('RecordingFile', ...
                        silenceParameterNotFound = true);
                    if ~isempty(P) && ~isempty(P.Value) && strlength(string(P.Value)) > 0
                        recFile = char(string(P.Value));
                    end

                    mediaUri = char(string(value));
                    if ~isempty(recFile)
                        cmd = sprintf('add %s :sout=#file{dst=%s}', mediaUri, recFile);
                    else
                        cmd = sprintf('add %s', mediaUri);
                    end
                    obj.sendCommand_(cmd);

                case 'RecordingFile'
                    % Value is cached in Parameter.Value; used next time MediaFile is set.
                    vprintf(3, 'hw.VlcRecorder: RecordingFile set to "%s"', char(string(value)));

                otherwise
                    vprintf(3, 'hw.VlcRecorder: set_parameter called for "%s"', paramName);
            end

            result = 1;
        end

        function value = get_parameter(obj, name) %#ok<INUSD>
            % get_parameter returns nan.
            % VLC RC is write-oriented. Parameter values are cached in
            % Parameter.Value and not polled from VLC. See hw.Software for
            % the same pattern.
            value = nan;
        end

        function set.mode(obj, mode)
            obj.mode = mode;
        end
    end


    methods (Static)
        function spec = getCreationSpec()
            % spec = hw.VlcRecorder.getCreationSpec()
            % Return the hw.InterfaceSpec describing options for creating this interface.
            spec = hw.InterfaceSpec( ...
                char(hw.VlcRecorder.Type), ...
                'VLC Recorder', ...
                'Connect to a running VLC instance via its RC socket for webcam recording.', ...
                [ ...
                hw.InterfaceSpecOption( ...
                    'name', 'host', 'label', 'Host', ...
                    'defaultValue', '127.0.0.1', ...
                    'required', false, 'inputType', 'text', 'choices', {}, ...
                    'isList', false, 'scope', 'interface', 'allowScalarExpansion', false, ...
                    'controlType', 'text', 'getFile', false, 'getFolder', false, ...
                    'fileFilter', {{'*.*', 'All Files (*.*)'}}, ...
                    'fileDialogTitle', '', ...
                    'description', 'IP address or hostname of the VLC RC interface.'), ...
                hw.InterfaceSpecOption( ...
                    'name', 'port', 'label', 'Port', ...
                    'defaultValue', 4212, ...
                    'required', false, 'inputType', 'numeric', 'choices', {}, ...
                    'isList', false, 'scope', 'interface', 'allowScalarExpansion', false, ...
                    'controlType', 'numeric', 'getFile', false, 'getFolder', false, ...
                    'fileFilter', {{'*.*', 'All Files (*.*)'}}, ...
                    'fileDialogTitle', '', ...
                    'description', 'TCP port of the VLC RC interface (default: 4212).'), ...
                hw.InterfaceSpecOption( ...
                    'name', 'timeout', 'label', 'Timeout (s)', ...
                    'defaultValue', 5, ...
                    'required', false, 'inputType', 'numeric', 'choices', {}, ...
                    'isList', false, 'scope', 'interface', 'allowScalarExpansion', false, ...
                    'controlType', 'numeric', 'getFile', false, 'getFolder', false, ...
                    'fileFilter', {{'*.*', 'All Files (*.*)'}}, ...
                    'fileDialogTitle', '', ...
                    'description', 'Connection timeout in seconds.')], ...
                @(opts) hw.VlcRecorder(opts.host, opts.port, opts.timeout));
        end
    end


    methods (Access = protected)
        function setup_interface(obj)
            % setup_interface()
            % Create the Module and populate parameters and triggers.
            M = hw.Module(obj, 'VlcRecorder', 'VLC', 1);
            obj.Module = M;

            obj.add_parameter('MediaFile', '', ...
                Type    = 'String', ...
                Access  = 'Write', ...
                Visible = true, ...
                Description = 'Media URI or file path to open in VLC (e.g. dshow://).');

            obj.add_parameter('Volume', 100, ...
                Type    = 'Integer', ...
                Access  = 'Any', ...
                Min     = 0, ...
                Max     = 200, ...
                Visible = true, ...
                Description = 'VLC playback volume (0–200; 100 = unity gain, maps to VLC scale 256).');

            obj.add_parameter('RecordingFile', '', ...
                Type    = 'File', ...
                Access  = 'Write', ...
                Visible = true, ...
                Description = 'Output file path for VLC recording. Set before applying MediaFile. Injected as :sout=#file{dst=...}.');

            obj.add_parameter('Play', 0, ...
                isTrigger = true, ...
                Visible   = false, ...
                Description = 'Trigger: send play command to VLC.');

            obj.add_parameter('Stop', 0, ...
                isTrigger = true, ...
                Visible   = false, ...
                Description = 'Trigger: send stop command to VLC.');

            obj.add_parameter('Pause', 0, ...
                isTrigger = true, ...
                Visible   = false, ...
                Description = 'Trigger: toggle VLC pause state.');

            obj.add_parameter('StartRecord', 0, ...
                isTrigger = true, ...
                Visible   = false, ...
                Description = 'Trigger: begin recording (idempotent; tracks toggle state internally).');

            obj.add_parameter('StopRecord', 0, ...
                isTrigger = true, ...
                Visible   = false, ...
                Description = 'Trigger: end recording (idempotent; tracks toggle state internally).');
        end

        function close_interface(obj)
            % close_interface()
            % Release the RC socket and reset internal state.
            obj.isRecording_ = false;
            if ~isempty(obj.HW)
                obj.HW = [];
            end
            obj.IsConnected = false;
        end
    end


    methods (Access = private)
        function sendCommand_(obj, cmd)
            % sendCommand_(obj, cmd)
            % Write a command string to the VLC RC socket followed by a newline.
            % Inputs:
            %   cmd - VLC RC command string (e.g. 'play', 'volume 256').
            if ~obj.IsConnected || isempty(obj.HW)
                vprintf(0, 1, 'hw.VlcRecorder: cannot send command "%s" — not connected.', cmd);
                return
            end
            write(obj.HW, uint8([cmd newline]));
            obj.readAvailable_();
            vprintf(3, 'hw.VlcRecorder -> %s', cmd);
        end

        function readAvailable_(obj)
            % readAvailable_(obj)
            % Drain any buffered bytes from the VLC RC socket response.
            if isempty(obj.HW)
                return
            end
            pause(0.05);
            if obj.HW.NumBytesAvailable > 0
                read(obj.HW, obj.HW.NumBytesAvailable, 'uint8');
            end
        end
    end

end
