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
    %       'FrameRate', 30, ...
    %       'StreamPort', 8080, ...
    %       'ShowPreview', true);
    %   vlc.connect();
    %   disp(streamUrl)
    %   pause(10);
    %   vlc.quit();
    %
    % Webcam recording/HTTP outputs are transcoded to a transport-stream-
    % compatible format before being duplicated to disk/network targets.
    %
    % For coordinated multi-camera capture, use VlcRecorderGroup to manage
    % one VLC instance per webcam.

    properties
        vlcPath (1,1) string = "C:\Program Files\VideoLAN\VLC\vlc.exe"
        host (1,1) string = "127.0.0.1"
        port (1,1) double = 4212
        timeout (1,1) double = 5
        windowWidth (1,1) double = 500
        windowHeight (1,1) double = 400
        windowX (1,1) double = 80
        windowY (1,1) double = 80
    end

    properties (Access = private)
        client_ = [] % Active tcpclient handle for VLC RC communication.
        isRecording_ (1,1) logical = false % Cached VLC record-toggle state.
        isConnected_ (1,1) logical = false % Tracks whether the RC socket is connected.
    end

    methods
        function obj = VlcRecorder(vlcPath, host, port)
            % obj = VlcRecorder(vlcPath, host, port)
            % Construct VLC recorder controller.
            % Inputs:
            %   vlcPath - Optional VLC executable path.
            %   host    - Optional RC interface host.
            %   port    - Optional RC interface port.
            % Output:
            %   obj     - Configured VlcRecorder instance.
            arguments
                vlcPath {mustBeTextScalar} = ""
                host {mustBeTextScalar} = ""
                port (1,1) double {mustBePositive} = NaN
            end

            sp = matlabshared.supportpkg.getSupportPackageRoot;
            wp = fullfile(sp, "toolbox", "matlab", "webcam", "supportpackages");
            if isfolder(wp) && ~contains(path, wp)
                addpath(wp)
            end
            rehash toolboxcache

            vlcPath = string(vlcPath);
            host = string(host);

            if strlength(vlcPath) > 0
                obj.vlcPath = vlcPath;
            end
            if strlength(host) > 0
                obj.host = host;
            end
            if ~isnan(port)
                obj.port = port;
            end
        end

        function launch(obj, extraArgs, mediaTarget)
            % obj.launch(extraArgs, mediaTarget)
            % Launch VLC process with RC interface enabled.
            % Inputs:
            %   extraArgs   - Optional additional VLC CLI switches.
            %   mediaTarget - Optional media URI or capture source.
            arguments
                obj
                extraArgs {mustBeTextScalar} = ""
                mediaTarget {mustBeTextScalar} = ""
            end

            if ~isfile(obj.vlcPath)
                error("VlcRecorder:VlcNotFound", ...
                    "VLC executable not found: %s", obj.vlcPath);
            end

            obj.assertRcEndpointAvailable();

            rcArgs = sprintf('--extraintf rc --rc-host %s:%d --rc-quiet', obj.host, obj.port);
            windowArgs = obj.buildWindowArgs();
            extraArgs = strtrim(string(extraArgs));
            mediaTarget = strtrim(string(mediaTarget));

            launchParts = ["""" + obj.vlcPath + """", string(rcArgs)];
            if ~isempty(windowArgs)
                launchParts = [launchParts, windowArgs];
            end
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
            obj.applyWindowGeometry();
        end

        function streamUrl = launchWebcam(obj, webcamName, options)
            % streamUrl = obj.launchWebcam(webcamName, Name=Value)
            % Launch webcam capture with optional recording/streaming outputs.
            % Inputs:
            %   webcamName - DirectShow webcam device name.
            %   options    - Name/value capture options for recording, stream, and preview.
            % Output:
            %   streamUrl  - HTTP stream URL when StreamPort is configured; otherwise "".
            arguments
                obj
                webcamName {mustBeTextScalar}
                options.AudioDevice {mustBeTextScalar} = ""
                options.RecordingFile {mustBeTextScalar} = ""
                options.RecordingMux {mustBeTextScalar} = "ts"
                options.FrameRate = []
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
            % obj.connect()
            % Open TCP connection to the VLC RC interface.
            if obj.isConnected_
                return;
            end

            obj.client_ = tcpclient(char(obj.host), obj.port, "Timeout", obj.timeout);
            configureTerminator(obj.client_, "LF");

            pause(0.2);
            obj.readAvailable();

            obj.isConnected_ = true;
        end

        function disconnect(obj)
            % obj.disconnect()
            % Close the TCP connection to the VLC RC interface.
            if ~obj.isConnected_
                return;
            end

            obj.client_ = [];
            obj.isConnected_ = false;
        end

        function add(obj, mediaUri)
            % obj.add(mediaUri)
            % Add a media item and begin playback.
            % Inputs:
            %   mediaUri - URI or file path supported by VLC.
            obj.requireConnection();
            obj.sendCommand(sprintf('add %s', char(string(mediaUri))));
        end

        function enqueue(obj, mediaUri)
            % obj.enqueue(mediaUri)
            % Queue a media item without forcing immediate playback.
            % Inputs:
            %   mediaUri - URI or file path supported by VLC.
            obj.requireConnection();
            obj.sendCommand(sprintf('enqueue %s', char(string(mediaUri))));
        end

        function play(obj)
            % obj.play()
            % Send the play command to VLC.
            obj.requireConnection();
            obj.sendCommand("play");
        end

        function pausePlayback(obj)
            % obj.pausePlayback()
            % Toggle VLC pause state.
            obj.requireConnection();
            obj.sendCommand("pause");
        end

        function stop(obj)
            % obj.stop()
            % Stop playback and clear the cached recording toggle state.
            obj.requireConnection();
            obj.sendCommand("stop");
            obj.isRecording_ = false;
        end

        function clearPlaylist(obj)
            % obj.clearPlaylist()
            % Clear the VLC playlist and reset the cached recording state.
            obj.requireConnection();
            obj.sendCommand("clear");
            obj.isRecording_ = false;
        end

        function startRecording(obj)
            % obj.startRecording()
            % Start recording via VLC RC toggle command.
            % Note:
            %   VLC implements record as a toggle, so state is tracked locally.
            obj.requireConnection();

            if ~obj.isRecording_
                obj.sendCommand("record");
                obj.isRecording_ = true;
            end
        end

        function stopRecording(obj)
            % obj.stopRecording()
            % Stop recording via VLC RC toggle command.
            % Note:
            %   VLC implements record as a toggle, so state is tracked locally.
            obj.requireConnection();

            if obj.isRecording_
                obj.sendCommand("record");
                obj.isRecording_ = false;
            end
        end

        function tf = recording(obj)
            % tf = obj.recording()
            % Query the cached recording state.
            % Output:
            %   tf - True when recording is believed active.
            tf = obj.isRecording_;
        end

        function out = status(obj)
            % out = obj.status()
            % Request VLC status text.
            % Output:
            %   out - Raw response from the VLC RC interface.
            obj.requireConnection();
            out = obj.sendCommand("status");
        end

        function out = info(obj)
            % out = obj.info()
            % Request VLC stream and media information.
            % Output:
            %   out - Raw response from the VLC RC interface.
            obj.requireConnection();
            out = obj.sendCommand("info");
        end

        function out = raw(obj, command)
            % out = obj.raw(command)
            % Send an arbitrary RC command string to VLC.
            % Inputs:
            %   command - RC command text.
            % Output:
            %   out     - Raw response text.
            obj.requireConnection();
            out = obj.sendCommand(command);
        end

        function quit(obj)
            % obj.quit()
            % Request VLC to quit and reset local connection state.
            if obj.isConnected_
                try
                    obj.sendCommand("quit");
                catch me
                    vprintf(0, 1, me);
                end
            end

            obj.client_ = [];
            obj.isConnected_ = false;
            obj.isRecording_ = false;
        end

        function delete(obj)
            % delete(obj)
            % Perform best-effort cleanup of VLC connection and process state.
            try
                obj.quit();
            catch me
                vprintf(0, 1, me);
            end
        end
    end

    methods (Static)
        function webcams = listWebcams()
            % webcams = VlcRecorder.listWebcams()
            % Enumerate available webcam device names.
            % Output:
            %   webcams - Unique device-name list from webcamlist and Windows cameras.
            webcamNames = strings(0, 1);

            if exist('webcamlist', 'file') == 2 && exist('webcam', 'file') == 2
                webcamNames = string(webcamlist);
            end

            % Prefer MATLAB's webcamlist when available so duplicate model
            % names are preserved without being doubled by the Windows
            % fallback enumeration.
            if isempty(webcamNames) && ispc
                windowsNames = VlcRecorder.listWindowsCameraDevices();
                webcamNames = [webcamNames; windowsNames(:)];
            end

            webcamNames = strtrim(webcamNames(:));
            webcamNames = webcamNames(strlength(webcamNames) > 0);
            if isempty(webcamNames)
                webcams = strings(0, 1);
            else
                webcams = webcamNames;
            end
        end
    end

    methods (Access = private)
        function options = normalizeWebcamOptions(~, options)
            % options = obj.normalizeWebcamOptions(options)
            % Normalize webcam launch option field types and ranges.
            % Input:
            %   options - Struct created by launchWebcam arguments parsing.
            % Output:
            %   options - Normalized struct with string/numeric canonical forms.
            arguments
                ~
                options struct
            end

            options.AudioDevice = string(options.AudioDevice);
            options.RecordingFile = string(options.RecordingFile);
            options.RecordingMux = lower(string(options.RecordingMux));

            if isempty(options.FrameRate)
                options.FrameRate = [];
            else
                validateattributes(options.FrameRate, {"numeric"}, {"scalar", "finite", "positive"}, ...
                    "VlcRecorder.launchWebcam", "FrameRate");
                options.FrameRate = double(options.FrameRate);
            end

            options.StreamPath = string(options.StreamPath);
            options.StreamMux = lower(string(options.StreamMux));
            options.StreamBind = string(options.StreamBind);
            options.ShowPreview = logical(options.ShowPreview);
            options.LiveCaching = round(options.LiveCaching);
            options.ExtraArgs = string(options.ExtraArgs);

            if isempty(options.StreamPort)
                options.StreamPort = [];
            else
                validateattributes(options.StreamPort, {"numeric"}, {"scalar", "finite", "positive"}, ...
                    "VlcRecorder.launchWebcam", "StreamPort");
                options.StreamPort = round(options.StreamPort);
            end

            if ~options.ShowPreview && strlength(options.RecordingFile) == 0 && isempty(options.StreamPort)
                error("VlcRecorder:NoWebcamOutputs", ...
                    "At least one webcam output is required. Enable ShowPreview, RecordingFile, or StreamPort.");
            end
        end

        function [extraArgs, mediaTarget, streamUrl] = buildWebcamLaunchArguments(obj, webcamName, options)
            % [extraArgs, mediaTarget, streamUrl] = obj.buildWebcamLaunchArguments(webcamName, options)
            % Build VLC launch arguments for webcam capture mode.
            % Inputs:
            %   webcamName - DirectShow webcam device name.
            %   options    - Normalized webcam capture options.
            % Outputs:
            %   extraArgs   - VLC CLI switches for RC, preview, record, and stream outputs.
            %   mediaTarget - DirectShow capture target string.
            %   streamUrl   - Public HTTP stream URL when streaming is enabled.
            arguments
                obj
                webcamName {mustBeTextScalar, mustBeNonzeroLengthText}
                options struct
            end

            mediaArgs = ["dshow://", ...
                ":dshow-vdev=" + obj.quoteCliValue(webcamName), ...
                ":live-caching=" + string(options.LiveCaching)];

            if ~isempty(options.FrameRate)
                mediaArgs(end+1) = ":dshow-fps=" + string(options.FrameRate);
            end

            if strlength(options.AudioDevice) > 0
                mediaArgs(end+1) = ":dshow-adev=" + obj.quoteCliValue(options.AudioDevice);
            else
                % Prevent VLC from auto-selecting a default capture audio device.
                mediaArgs(end+1) = ":dshow-adev=none";
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
                    publicHost = obj.host;
                end
                streamUrl = "http://" + publicHost + ":" + string(options.StreamPort) + streamPath;
            end

            extraParts = strings(0, 1);
            if strlength(options.ExtraArgs) > 0
                extraParts(end+1) = strtrim(options.ExtraArgs);
            end

            if ~isempty(soutTargets)
                if (strlength(options.RecordingFile) > 0 || ~isempty(options.StreamPort))
                    extraParts = [extraParts, obj.buildWebcamEncoderArgs()];
                end

                soutChain = obj.buildWebcamSoutChain(soutTargets, ...
                    (strlength(options.RecordingFile) > 0 || ~isempty(options.StreamPort)), ...
                    strlength(options.AudioDevice) > 0, ...
                    options.FrameRate);
                extraParts(end+1) = string(sprintf('--sout="%s"', char(soutChain)));
            end

            extraArgs = strjoin(extraParts, " ");
        end

        function out = sendCommand(obj, command)
            % out = obj.sendCommand(command)
            % Send one RC command and collect currently available response text.
            % Inputs:
            %   command - VLC RC command text.
            % Output:
            %   out     - Available response text from the RC socket.
            arguments
                obj
                command {mustBeTextScalar}
            end

            write(obj.client_, uint8([char(command), newline]), "uint8");
            pause(0.15);
            out = obj.readAvailable();
        end

        function out = readAvailable(obj)
            % out = obj.readAvailable()
            % Read buffered RC output until the socket receive queue is empty.
            % Output:
            %   out - Buffered RC response text with surrounding whitespace removed.
            out = "";
            if isempty(obj.client_)
                return;
            end

            pause(0.05);
            while obj.client_.NumBytesAvailable > 0
                chunk = read(obj.client_, obj.client_.NumBytesAvailable, "uint8");
                out = out + string(char(chunk(:).'));
                pause(0.02);
            end

            out = strtrim(out);
        end

        function requireConnection(obj)
            % obj.requireConnection()
            % Guard helper to enforce an active RC connection.
            if ~obj.isConnected_ || isempty(obj.client_)
                error("VlcRecorder:NotConnected", ...
                    "Not connected to VLC. Call launch/connect first.");
            end
        end

        function assertRcEndpointAvailable(obj)
            try
                tcpclient(char(obj.host), obj.port, "Timeout", 0.2);
                error("VlcRecorder:RcPortInUse", ...
                    ["Cannot launch VLC because %s:%d is already accepting TCP connections. ", ...
                    "An existing VLC RC instance may still be running. Quit the old instance or use a different port."], ...
                    obj.host, obj.port);
            catch me
                if strcmp(me.identifier, "VlcRecorder:RcPortInUse")
                    rethrow(me)
                end
            end
        end

        function out = buildWindowArgs(obj)
            out = strings(0, 1);

            hasWindowGeometry = obj.hasWindowGeometry();

            if hasWindowGeometry
                out(end+1) = "--intf dummy";
                out(end+1) = "--dummy-quiet";
                out(end+1) = "--no-embedded-video";
                out(end+1) = "--no-qt-video-autoresize";
            end

            if isfinite(obj.windowWidth) && obj.windowWidth > 0
                out(end+1) = "--width=" + string(round(obj.windowWidth));
            end
            if isfinite(obj.windowHeight) && obj.windowHeight > 0
                out(end+1) = "--height=" + string(round(obj.windowHeight));
            end
            if isfinite(obj.windowX)
                out(end+1) = "--video-x=" + string(round(obj.windowX));
            end
            if isfinite(obj.windowY)
                out(end+1) = "--video-y=" + string(round(obj.windowY));
            end
        end

        function tf = hasWindowGeometry(obj)
            tf = ...
                (isfinite(obj.windowWidth) && obj.windowWidth > 0) || ...
                (isfinite(obj.windowHeight) && obj.windowHeight > 0) || ...
                isfinite(obj.windowX) || ...
                isfinite(obj.windowY);
        end

        function applyWindowGeometry(obj)
            if ~ispc || ~obj.hasWindowGeometry()
                return;
            end

            processId = obj.findLaunchedProcessId();
            if isempty(processId)
                return;
            end

            width = round(obj.windowWidth);
            height = round(obj.windowHeight);
            xpos = round(obj.windowX);
            ypos = round(obj.windowY);

            if ~isfinite(width) || width <= 0
                width = 0;
            end
            if ~isfinite(height) || height <= 0
                height = 0;
            end
            if ~isfinite(xpos)
                xpos = 80;
            end
            if ~isfinite(ypos)
                ypos = 80;
            end

            commandText = sprintf([ ...
                'powershell -NoProfile -Command ', ...
                '"Add-Type @''''', ...
                'using System; ', ...
                'using System.Runtime.InteropServices; ', ...
                'public static class Win32 { ', ...
                '[DllImport(\"user32.dll\")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam); ', ...
                'public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam); ', ...
                '[DllImport(\"user32.dll\")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId); ', ...
                '[DllImport(\"user32.dll\")] public static extern bool IsWindowVisible(IntPtr hWnd); ', ...
                '[DllImport(\"user32.dll\")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect); ', ...
                '[DllImport(\"user32.dll\")] public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint); ', ...
                '[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left; public int Top; public int Right; public int Bottom; } ', ...
                '} ', ...
                '''''@; ', ...
                '$targetPid = %d; $target = [IntPtr]::Zero; ', ...
                'for ($attempt = 0; $attempt -lt 40 -and $target -eq [IntPtr]::Zero; $attempt++) { ', ...
                '  [Win32]::EnumWindows({ param($hWnd, $lParam) ', ...
                '    $pid = 0; [Win32]::GetWindowThreadProcessId($hWnd, [ref]$pid) | Out-Null; ', ...
                '    if ($pid -eq $targetPid -and [Win32]::IsWindowVisible($hWnd)) { $script:target = $hWnd; return $false } ', ...
                '    return $true }, [IntPtr]::Zero) | Out-Null; ', ...
                '  if ($target -eq [IntPtr]::Zero) { Start-Sleep -Milliseconds 100 } ', ...
                '} ', ...
                'if ($target -ne [IntPtr]::Zero) { ', ...
                '  $rect = New-Object Win32+RECT; ', ...
                '  for ($attempt = 0; $attempt -lt 20; $attempt++) { ', ...
                '    [Win32]::GetWindowRect($target, [ref]$rect) | Out-Null; ', ...
                '    $targetWidth = %d; if ($targetWidth -le 0) { $targetWidth = $rect.Right - $rect.Left } ', ...
                '    $targetHeight = %d; if ($targetHeight -le 0) { $targetHeight = $rect.Bottom - $rect.Top } ', ...
                '    [Win32]::MoveWindow($target, %d, %d, $targetWidth, $targetHeight, $true) | Out-Null; ', ...
                '    Start-Sleep -Milliseconds 150 ', ...
                '  } ', ...
                '}"'], ...
                processId, width, height, xpos, ypos);
            system(commandText);
        end

        function processId = findLaunchedProcessId(obj)
            processId = [];
            queryText = sprintf([ ...
                'powershell -NoProfile -Command ', ...
                '"Get-CimInstance Win32_Process | ', ...
                'Where-Object { $_.Name -eq ''vlc.exe'' -and $_.CommandLine -like ''*--rc-host %s:%d*'' } | ', ...
                'Select-Object -ExpandProperty ProcessId"'], ...
                char(obj.host), obj.port);
            [status, output] = system(queryText);
            if status ~= 0
                return;
            end

            matches = regexp(strtrim(output), '\d+', 'match');
            if ~isempty(matches)
                processId = str2double(matches{end});
            end
        end

        function out = quoteCliValue(~, value)
            % out = obj.quoteCliValue(value)
            % Quote a value for standard VLC CLI argument parsing.
            % Inputs:
            %   value - Unquoted CLI argument text.
            % Output:
            %   out   - CLI-safe quoted text.
            textValue = strrep(char(string(value)), '"', '""');
            out = '"' + string(textValue) + '"';
        end

        function out = quoteSoutValue(~, value)
            % out = obj.quoteSoutValue(value)
            % Quote a destination value inside a VLC --sout expression.
            % Inputs:
            %   value - Unquoted destination text.
            % Output:
            %   out   - Quoted destination text for --sout.
            textValue = strrep(char(string(value)), '''', '''''');
            out = "'" + string(textValue) + "'";
        end

        function out = normalizeFileDestination(~, value)
            % out = obj.normalizeFileDestination(value)
            % Convert file destination separators to a VLC-friendly form.
            % Inputs:
            %   value - File path text.
            % Output:
            %   out   - File path with forward slashes for VLC.
            out = string(strrep(char(string(value)), '\', '/'));
        end

        function out = normalizeHttpPath(~, value)
            % out = obj.normalizeHttpPath(value)
            % Ensure HTTP stream path is non-empty and starts with '/'.
            % Inputs:
            %   value - Requested HTTP path text.
            % Output:
            %   out   - Normalized HTTP path beginning with '/'.
            out = string(value);
            if strlength(out) == 0
                out = "/webcam";
            elseif ~startsWith(out, "/")
                out = "/" + out;
            end
        end

        function out = buildWebcamSoutChain(obj, soutTargets, hasEncodedOutput, hasAudioInput, frameRate)
            duplicateChain = "duplicate{" + strjoin(soutTargets, ",") + "}";
            if ~hasEncodedOutput
                out = "#" + duplicateChain;
                return;
            end

            out = "#" + obj.buildWebcamTranscodeSpec(hasAudioInput, frameRate) + ":" + duplicateChain;
        end

        function out = buildWebcamTranscodeSpec(~, hasAudioInput, frameRate)
            transcodeParts = ["vcodec=h264", "vb=2500"];
            if ~isempty(frameRate)
                transcodeParts(end+1) = "fps=" + string(frameRate);
            end
            if hasAudioInput
                transcodeParts(end+1) = "acodec=mp4a";
                transcodeParts(end+1) = "ab=128";
            else
                transcodeParts(end+1) = "acodec=none";
            end

            out = "transcode{" + strjoin(transcodeParts, ",") + "}";
        end

        function out = buildWebcamEncoderArgs(~)
            out = [ ...
                "--sout-x264-keyint=30", ...
                "--sout-x264-min-keyint=30", ...
                "--sout-x264-bframes=0", ...
                "--sout-x264-tune=zerolatency"];
        end
    end

    methods (Static, Access = private)
        function webcamNames = listWindowsCameraDevices()
            % webcamNames = VlcRecorder.listWindowsCameraDevices()
            % Enumerate Windows camera device names via CIM query.
            % Output:
            %   webcamNames - Camera device names reported by the Windows CIM query.
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