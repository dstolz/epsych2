classdef VlcRecorder < handle
    %VLCRECORDER Control VLC playback/recording from MATLAB via RC socket.
    %
    % Requirements:
    % 1. VLC must be installed.
    % 2. VLC must expose the RC interface on a TCP port.
    % 3. The VLC "record" command is a toggle, so this class tracks the
    %    recording state internally. If you toggle recording outside MATLAB,
    %    the cached state can become inaccurate.
    %
    % Example:
    %   vlc = VlcRecorder();
    %   vlc.launch("--no-video-title-show");
    %   vlc.connect();
    %   vlc.add("https://example.com/live-stream");
    %   vlc.play();
    %   pause(5);
    %   vlc.startRecording();
    %   pause(30);
    %   vlc.stopRecording();
    %   vlc.quit();
    %
    % Webcam capture example:
    %   webcams = VlcRecorder.listWebcams();
    %   vlc = VlcRecorder();
    %   streamUrl = vlc.launchWebcam(webcams(1), ...
    %       'RecordingFile', fullfile(tempdir, 'vlc_webcam_capture.ts'), ...
    %       'StreamPort', 8080, ...
    %       'ShowPreview', true);
    %   vlc.connect();
    %   disp(streamUrl)
    %   pause(10);
    %   vlc.quit();

    properties
        % Full path to VLC executable.
        VlcPath (1,1) string = "C:\Program Files (x86)\VideoLAN\VLC\vlc.exe"
        % RC socket host for VLC remote control interface.
        Host (1,1) string = "127.0.0.1"
        % RC socket port for VLC remote control interface.
        Port (1,1) double = 4212
        % TCP timeout in seconds for RC communication.
        Timeout (1,1) double = 5
    end

    properties (Access = private)
        Client = []
        IsRecording (1,1) logical = false
        IsConnected (1,1) logical = false
    end

    methods
        % Construct VLC recorder controller.
        % Inputs:
        %   vlcPath - Optional VLC executable path.
        %   host    - Optional RC interface host.
        %   port    - Optional RC interface port.
        % Output:
        %   obj     - Configured VlcRecorder instance.
        function obj = VlcRecorder(vlcPath, host, port)
            arguments
                vlcPath {mustBeTextScalar} = ""
                host {mustBeTextScalar} = ""
                port (1,1) double {mustBePositive} = NaN
            end

            vlcPath = string(vlcPath);
            host = string(host);

            if strlength(vlcPath) > 0
                obj.VlcPath = vlcPath;
            end
            if strlength(host) > 0
                obj.Host = host;
            end
            if ~isnan(port)
                obj.Port = port;
            end
        end

        % Launch VLC process with RC interface enabled.
        % Inputs:
        %   extraArgs   - Optional additional VLC CLI switches.
        %   mediaTarget - Optional media URI or capture source.
        function launch(obj, extraArgs, mediaTarget)
            arguments
                obj
                extraArgs {mustBeTextScalar} = ""
                mediaTarget {mustBeTextScalar} = ""
            end

            if ~isfile(obj.VlcPath)
                error("VlcRecorder:VlcNotFound", ...
                    "VLC executable not found: %s", obj.VlcPath);
            end

            rcArgs = sprintf('--extraintf rc --rc-host %s:%d', obj.Host, obj.Port);
            extraArgs = strtrim(string(extraArgs));
            mediaTarget = strtrim(string(mediaTarget));

            launchParts = ["""" + obj.VlcPath + """", string(rcArgs)];
            if strlength(extraArgs) > 0
                launchParts(end+1) = extraArgs;
            end
            if strlength(mediaTarget) > 0
                launchParts(end+1) = mediaTarget;
            end

            launchCmd = sprintf('start "" %s', char(strjoin(launchParts, " ")));
            [status, cmdout] = system(launchCmd);

            if status ~= 0
                error("VlcRecorder:LaunchFailed", ...
                    "Failed to launch VLC: %s", strtrim(cmdout));
            end

            pause(1.5);
        end

        % Launch webcam capture with optional recording/streaming outputs.
        % Inputs:
        %   webcamName - DirectShow webcam device name.
        %   options    - Name/value capture options (recording, stream, preview).
        % Output:
        %   streamUrl  - HTTP stream URL when StreamPort is configured; otherwise "".
        function streamUrl = launchWebcam(obj, webcamName, options)
            arguments
                obj
                webcamName {mustBeTextScalar}
                options.AudioDevice {mustBeTextScalar} = ""
                options.RecordingFile {mustBeTextScalar} = ""
                options.RecordingMux {mustBeTextScalar} = "ts"
                options.StreamPort = []
                options.StreamPath {mustBeTextScalar} = "/webcam"
                options.StreamMux {mustBeTextScalar} = "ts"
                options.StreamBind {mustBeTextScalar} = "0.0.0.0"
                options.ShowPreview (1,1) logical = true
                options.LiveCaching (1,1) double {mustBeNonnegative} = 300
                options.ExtraArgs {mustBeTextScalar} = "--no-video-title-show"
            end

            webcamName = string(webcamName);
            if strlength(webcamName) == 0
                error("VlcRecorder:InvalidWebcam", ...
                    "A webcam device name is required.");
            end

            options = obj.normalizeWebcamOptions(options);
            [extraArgs, mediaTarget, streamUrl] = obj.buildWebcamLaunchArguments(webcamName, options);
            obj.launch(extraArgs, mediaTarget);
        end

        % Open TCP connection to VLC RC interface.
        function connect(obj)
            if obj.IsConnected
                return;
            end

            obj.Client = tcpclient(char(obj.Host), obj.Port, "Timeout", obj.Timeout);
            configureTerminator(obj.Client, "LF");

            pause(0.2);
            obj.readAvailable();

            obj.IsConnected = true;
        end

        % Close TCP connection to VLC RC interface.
        function disconnect(obj)
            if ~obj.IsConnected
                return;
            end

            obj.Client = [];
            obj.IsConnected = false;
        end

        % Add media item and begin playback.
        % Input:
        %   mediaUri - URI/path supported by VLC.
        function add(obj, mediaUri)
            obj.requireConnection();
            obj.sendCommand(sprintf('add %s', char(string(mediaUri))));
        end

        % Queue media item without forcing immediate playback.
        % Input:
        %   mediaUri - URI/path supported by VLC.
        function enqueue(obj, mediaUri)
            obj.requireConnection();
            obj.sendCommand(sprintf('enqueue %s', char(string(mediaUri))));
        end

        % Send play command to VLC.
        function play(obj)
            obj.requireConnection();
            obj.sendCommand("play");
        end

        % Toggle VLC pause state.
        function pausePlayback(obj)
            obj.requireConnection();
            obj.sendCommand("pause");
        end

        % Stop playback and clear cached recording toggle state.
        function stop(obj)
            obj.requireConnection();
            obj.sendCommand("stop");
            obj.IsRecording = false;
        end

        % Clear VLC playlist and reset cached recording toggle state.
        function clearPlaylist(obj)
            obj.requireConnection();
            obj.sendCommand("clear");
            obj.IsRecording = false;
        end

        % Start recording via VLC RC toggle command.
        % Note: VLC implements record as a toggle; state is tracked locally.
        function startRecording(obj)
            obj.requireConnection();

            if ~obj.IsRecording
                obj.sendCommand("record");
                obj.IsRecording = true;
            end
        end

        % Stop recording via VLC RC toggle command.
        % Note: VLC implements record as a toggle; state is tracked locally.
        function stopRecording(obj)
            obj.requireConnection();

            if obj.IsRecording
                obj.sendCommand("record");
                obj.IsRecording = false;
            end
        end

        % Query cached recording state.
        % Output:
        %   tf - True when recording is believed active.
        function tf = recording(obj)
            tf = obj.IsRecording;
        end

        % Request VLC status text.
        % Output:
        %   out - Raw response from VLC RC interface.
        function out = status(obj)
            obj.requireConnection();
            out = obj.sendCommand("status");
        end

        % Request VLC stream/media information.
        % Output:
        %   out - Raw response from VLC RC interface.
        function out = info(obj)
            obj.requireConnection();
            out = obj.sendCommand("info");
        end

        % Send arbitrary RC command string to VLC.
        % Inputs:
        %   command - RC command text.
        % Output:
        %   out     - Raw response text.
        function out = raw(obj, command)
            obj.requireConnection();
            out = obj.sendCommand(command);
        end

        % Request VLC to quit and reset local connection state.
        function quit(obj)
            if obj.IsConnected
                try
                    obj.sendCommand("quit");
                catch
                end
            end

            obj.Client = [];
            obj.IsConnected = false;
            obj.IsRecording = false;
        end

        % Destructor: best-effort cleanup of VLC connection/process state.
        function delete(obj)
            try
                obj.quit();
            catch
            end
        end
    end

    methods (Static)
        % Enumerate available webcam device names.
        % Output:
        %   webcams - Unique device-name list from webcamlist/Windows cameras.
        function webcams = listWebcams()
            webcamNames = strings(0, 1);

            if exist('webcamlist', 'file') == 2 && exist('webcam', 'file') == 2
                webcamNames = string(webcamlist);
            end

            if ispc
                windowsNames = VlcRecorder.listWindowsCameraDevices();
                webcamNames = [webcamNames; windowsNames(:)]; %#ok<AGROW>
            end

            webcamNames = strtrim(webcamNames(:));
            webcamNames = webcamNames(strlength(webcamNames) > 0);
            if isempty(webcamNames)
                webcams = strings(0, 1);
            else
                webcams = unique(webcamNames, 'stable');
            end
        end
    end

    methods (Access = private)
        % Normalize/validate webcam options after argument parsing.
        % This centralizes checks shared across capture configurations.
        function options = normalizeWebcamOptions(obj, options)
            arguments
                obj
                options.AudioDevice {mustBeTextScalar} = ""
                options.RecordingFile {mustBeTextScalar} = ""
                options.RecordingMux {mustBeTextScalar} = "ts"
                options.StreamPort = []
                options.StreamPath {mustBeTextScalar} = "/webcam"
                options.StreamMux {mustBeTextScalar} = "ts"
                options.StreamBind {mustBeTextScalar} = "0.0.0.0"
                options.ShowPreview (1,1) logical = true
                options.LiveCaching (1,1) double {mustBeNonnegative} = 300
                options.ExtraArgs {mustBeTextScalar} = "--no-video-title-show"
            end

            if isempty(obj)
                return;
            end


            if isempty(options.StreamPort)
                options.StreamPort = [];
            else
                options.StreamPort = round(options.StreamPort);
            end

            if ~options.ShowPreview && strlength(options.RecordingFile) == 0 && isempty(options.StreamPort)
                error("VlcRecorder:NoWebcamOutputs", ...
                    "At least one webcam output is required. Enable ShowPreview, RecordingFile, or StreamPort.");
            end
        end

        % Build VLC launch argument strings for webcam capture mode.
        % Produces both RC launch args and optional public stream URL.
        function [extraArgs, mediaTarget, streamUrl] = buildWebcamLaunchArguments(obj, webcamName, options)
            arguments
                obj
                webcamName {mustBeTextScalar, mustBeNonzeroLengthText}
                options struct
            end

            mediaArgs = ["dshow://", ...
                ":dshow-vdev=" + obj.quoteCliValue(webcamName), ...
                ":live-caching=" + string(options.LiveCaching)];

            if strlength(options.AudioDevice) > 0
                mediaArgs(end+1) = ":dshow-adev=" + obj.quoteCliValue(options.AudioDevice);
            end

            mediaTarget = strjoin(mediaArgs, " ");
            streamUrl = "";
            soutTargets = strings(0, 1);

            if options.ShowPreview
                soutTargets(end+1) = "dst=display";
            end

            if strlength(options.RecordingFile) > 0
                recordingFile = options.RecordingFile;
                recordingDir = fileparts(char(recordingFile));
                if ~isempty(recordingDir) && ~isfolder(recordingDir)
                    mkdir(recordingDir);
                end

                recordingDst = obj.quoteSoutValue(obj.normalizeFileDestination(recordingFile));
                soutTargets(end+1) = "dst=std{access=file,mux=" + options.RecordingMux + ",dst=" + recordingDst + "}";
            end

            if ~isempty(options.StreamPort)
                streamPath = obj.normalizeHttpPath(options.StreamPath);
                streamDst = options.StreamBind + ":" + string(options.StreamPort) + streamPath;
                soutTargets(end+1) = "dst=std{access=http,mux=" + options.StreamMux + ",dst=" + obj.quoteSoutValue(streamDst) + "}";

                publicHost = options.StreamBind;
                if publicHost == "0.0.0.0"
                    publicHost = obj.Host;
                end
                streamUrl = "http://" + publicHost + ":" + string(options.StreamPort) + streamPath;
            end

            extraParts = strings(0, 1);
            if strlength(options.ExtraArgs) > 0
                extraParts(end+1) = strtrim(options.ExtraArgs);
            end

            if ~isempty(soutTargets)
                soutArg = "--sout=""#duplicate{" + strjoin(soutTargets, ",") + "}""";
                extraParts(end+1) = soutArg;
            end

            extraArgs = strjoin(extraParts, " ");
        end

        % Send one RC command and collect currently available response text.
        function out = sendCommand(obj, command)
            arguments
                obj
                command {mustBeTextScalar}
            end

            write(obj.Client, uint8([char(command), newline]), "uint8");
            pause(0.15);
            out = obj.readAvailable();
        end

        % Read buffered RC output until socket receive queue is empty.
        function out = readAvailable(obj)
            out = "";
            if isempty(obj.Client)
                return;
            end

            pause(0.05);
            while obj.Client.NumBytesAvailable > 0
                chunk = read(obj.Client, obj.Client.NumBytesAvailable, "uint8");
                out = out + string(char(chunk(:).'));
                pause(0.02);
            end

            out = strtrim(out);
        end

        % Guard helper to enforce an active RC connection.
        function requireConnection(obj)
            if ~obj.IsConnected || isempty(obj.Client)
                error("VlcRecorder:NotConnected", ...
                    "Not connected to VLC. Call launch/connect first.");
            end
        end

        % Quote value for standard VLC CLI argument parsing.
        function out = quoteCliValue(~, value)
            textValue = strrep(char(string(value)), '"', '""');
            out = '"' + string(textValue) + '"';
        end

        % Quote destination value inside VLC --sout expression.
        function out = quoteSoutValue(~, value)
            textValue = strrep(char(string(value)), '''', '''''');
            out = "'" + string(textValue) + "'";
        end

        % Convert file destination separators to VLC-friendly form.
        function out = normalizeFileDestination(~, value)
            out = string(strrep(char(string(value)), '\', '/'));
        end

        % Ensure HTTP stream path is non-empty and starts with '/'.
        function out = normalizeHttpPath(~, value)
            out = string(value);
            if strlength(out) == 0
                out = "/webcam";
            elseif ~startsWith(out, "/")
                out = "/" + out;
            end
        end
    end

    methods (Static, Access = private)
        % Enumerate Windows camera device names via CIM query.
        function webcamNames = listWindowsCameraDevices()
            commandText = [ ...
                'powershell -NoProfile -Command ', ...
                '"Get-CimInstance Win32_PnPEntity | ', ...
                'Where-Object { $_.PNPClass -eq ''Camera'' -or $_.Service -eq ''usbvideo'' } | ', ...
                'Select-Object -ExpandProperty Name"'];
            [status, output] = system(commandText);

            if status ~= 0
                webcamNames = strings(0, 1);
                return;
            end

            lines = regexp(strtrim(output), '\r\n|\n|\r', 'split');
            webcamNames = string(lines(:));
            webcamNames = strtrim(webcamNames);
            webcamNames = webcamNames(strlength(webcamNames) > 0);
        end
    end
end