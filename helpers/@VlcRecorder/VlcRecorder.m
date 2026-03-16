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
        VlcPath (1,1) string = "C:\Program Files (x86)\VideoLAN\VLC\vlc.exe"
        Host (1,1) string = "127.0.0.1"
        Port (1,1) double = 4212
        Timeout (1,1) double = 5
    end

    properties (Access = private)
        Client = []
        IsRecording (1,1) logical = false
        IsConnected (1,1) logical = false
    end

    methods
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

        function disconnect(obj)
            if ~obj.IsConnected
                return;
            end

            obj.Client = [];
            obj.IsConnected = false;
        end

        function add(obj, mediaUri)
            obj.requireConnection();
            obj.sendCommand(sprintf('add %s', char(string(mediaUri))));
        end

        function enqueue(obj, mediaUri)
            obj.requireConnection();
            obj.sendCommand(sprintf('enqueue %s', char(string(mediaUri))));
        end

        function play(obj)
            obj.requireConnection();
            obj.sendCommand("play");
        end

        function pausePlayback(obj)
            obj.requireConnection();
            obj.sendCommand("pause");
        end

        function stop(obj)
            obj.requireConnection();
            obj.sendCommand("stop");
            obj.IsRecording = false;
        end

        function clearPlaylist(obj)
            obj.requireConnection();
            obj.sendCommand("clear");
            obj.IsRecording = false;
        end

        function startRecording(obj)
            obj.requireConnection();

            if ~obj.IsRecording
                obj.sendCommand("record");
                obj.IsRecording = true;
            end
        end

        function stopRecording(obj)
            obj.requireConnection();

            if obj.IsRecording
                obj.sendCommand("record");
                obj.IsRecording = false;
            end
        end

        function tf = recording(obj)
            tf = obj.IsRecording;
        end

        function out = status(obj)
            obj.requireConnection();
            out = obj.sendCommand("status");
        end

        function out = info(obj)
            obj.requireConnection();
            out = obj.sendCommand("info");
        end

        function out = raw(obj, command)
            obj.requireConnection();
            out = obj.sendCommand(command);
        end

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

        function delete(obj)
            try
                obj.quit();
            catch
            end
        end
    end

    methods (Static)
        function webcams = listWebcams()
            webcamNames = strings(0, 1);

            if exist('webcamlist', 'file') == 2 && exist('webcam', 'file') == 2
                try
                    webcamNames = string(webcamlist);
                catch
                end
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

        function out = sendCommand(obj, command)
            arguments
                obj
                command {mustBeTextScalar}
            end

            write(obj.Client, uint8([char(command), newline]), "uint8");
            pause(0.15);
            out = obj.readAvailable();
        end

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

        function requireConnection(obj)
            if ~obj.IsConnected || isempty(obj.Client)
                error("VlcRecorder:NotConnected", ...
                    "Not connected to VLC. Call launch/connect first.");
            end
        end

        function out = quoteCliValue(~, value)
            textValue = strrep(char(string(value)), '"', '""');
            out = '"' + string(textValue) + '"';
        end

        function out = quoteSoutValue(~, value)
            textValue = strrep(char(string(value)), '''', '''''');
            out = "'" + string(textValue) + "'";
        end

        function out = normalizeFileDestination(~, value)
            out = string(strrep(char(string(value)), '\', '/'));
        end

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