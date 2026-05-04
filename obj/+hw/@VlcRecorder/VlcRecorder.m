classdef VlcRecorder < hw.Interface
    % obj = hw.VlcRecorder()
    % hw.Interface implementation for webcam recording using ffmpeg, with VLC for live display.
    %
    % connect() initialises the interface. Use set_parameter to configure the
    % device, output file, and media source, then trigger('Play') to start.
    % Recording uses ffmpeg (H.264/libx264) launched as a background process;
    % VLC is launched separately for the live preview window.
    %
    % Parameters exposed (via all_parameters):
    %   DeviceName    - (String, Any)    DirectShow video device name (default: 'Integrated Camera').
    %   RecordingFile - (File, Any)      Output file path for ffmpeg recording. Leave empty to
    %                                     display without recording.
    %   MediaFile     - (String, Write)  Media URI passed to VLC for display (e.g. 'dshow://').
    %
    % Triggers (via trigger()):
    %   Play        - Launch VLC display and start ffmpeg recording (if RecordingFile is set).
    %   Stop        - Kill ffmpeg and VLC processes started by this object.
    %   Pause       - No-op (VLC display only; ffmpeg recording is not pausable).
    %   StartRecord - Start ffmpeg recording independently (e.g. after Play).
    %   StopRecord  - Stop ffmpeg recording without stopping VLC display.
    %
    % Notes
    %   ffmpeg is expected at the path stored in ffmpegExePath_ (default:
    %   'C:\prgms_on_path\ffmpeg.exe'). Override by setting that property before connect().
    %
    %   VLC is expected at vlcExePath_ (default: 'C:\Program Files (x86)\VideoLAN\VLC\vlc.exe').
    %
    %   PIDs of the launched VLC and ffmpeg processes are cached and used for
    %   clean termination. Only processes started by THIS object are killed.
    %
    %   Codec settings (libx264 / ultrafast / CRF 28) are suitable for real-time
    %   capture. Change crf_ and preset_ properties before connect() to adjust.
    %
    % Example
    %   obj = hw.VlcRecorder();
    %   obj.connect();
    %   obj.set_parameter('DeviceName',    'Integrated Camera');
    %   obj.set_parameter('RecordingFile', 'C:\data\capture.ts');
    %   obj.set_parameter('MediaFile',     'dshow://');
    %   obj.trigger('Play');
    %   pause(30);
    %   obj.trigger('Stop');
    %
    % See also: documentation/hw/hw_VlcRecorder.md, documentation/hw/hw_Interface.md,
    %           hw.Module, hw.Parameter


    properties (SetAccess = protected)
        HW = []  % unused; retained for hw.Interface compatibility

        Module
    end

    properties
        IsConnected = false
    end

    properties (Constant)
        Type = 'VlcRecorder'
    end

    properties (SetObservable, AbortSet)
        mode
    end

    properties (Access = private)
        vlcExePath_    (1,1) string = "C:\Program Files (x86)\VideoLAN\VLC\vlc.exe"  % path to vlc.exe
        ffmpegExePath_ (1,1) string = "C:\prgms_on_path\ffmpeg.exe"                  % path to ffmpeg.exe
        deviceName_    (1,1) string = "Integrated Camera"  % DirectShow video device name
        recordingFile_ (1,1) string = ""                   % output file path for ffmpeg
        mediaUri_      (1,1) string = "dshow://"            % media URI for VLC display
        isRecording_   (1,1) logical = false                % true while ffmpeg is recording
        vlcPid_        (1,1) double  = 0                    % PID of VLC process we launched
        ffmpegPid_     (1,1) double  = 0                    % PID of ffmpeg process we launched
        crf_           (1,1) double  = 28                   % ffmpeg CRF quality (lower = better, larger file)
        preset_        (1,1) string  = "ultrafast"          % ffmpeg x264 preset
    end


    methods
        function obj = VlcRecorder()
            % obj = hw.VlcRecorder()
            % Construct a VlcRecorder without connecting.
            obj.Module = hw.Module.empty(1, 0);
        end

        function connect(obj)
            % obj.connect()
            % Initialise the interface parameters. No external process is launched here;
            % call trigger('Play') to start VLC display and ffmpeg recording.
            if obj.IsConnected
                return
            end
            obj.setup_interface();
            obj.IsConnected = true;
        end

        function disconnect(obj)
            % obj.disconnect()
            % Stop any running processes and release resources.
            if ~obj.IsConnected
                return
            end
            obj.close_interface();
        end

        function result = trigger(obj, name)
            % result = obj.trigger(name)
            % Execute a named trigger.
            % Inputs:
            %   name - 'Play', 'Stop', 'Pause', 'StartRecord', or 'StopRecord',
            %          or an hw.Parameter trigger object.
            % Returns:
            %   result - 1 on success, 0 on unrecognised name.
            if isa(name, 'hw.Parameter')
                name = name.Name;
            end
            result = 1;
            switch name
                case 'Play'
                    obj.launchVlc_();
                    if strlength(obj.recordingFile_) > 0
                        obj.launchFfmpeg_();
                    end

                case 'Stop'
                    obj.stopFfmpeg_();
                    obj.stopVlc_();

                case 'Pause'
                    % VLC display does not expose RC; ffmpeg cannot be paused.
                    vprintf(3, 'hw.VlcRecorder: Pause is a no-op in this backend.');

                case 'StartRecord'
                    if ~obj.isRecording_
                        obj.launchFfmpeg_();
                    end

                case 'StopRecord'
                    if obj.isRecording_
                        obj.stopFfmpeg_();
                    end

                otherwise
                    vprintf(0, 1, 'hw.VlcRecorder: unknown trigger "%s"', name);
                    result = 0;
            end
        end

        function result = set_parameter(obj, name, value)
            % result = obj.set_parameter(name, value)
            % Store a configuration parameter.
            % Inputs:
            %   name  - Parameter name string or hw.Parameter handle.
            %   value - New value.
            % Returns:
            %   result - 1 on success.
            if isa(name, 'hw.Parameter')
                paramName = name.Name;
            else
                paramName = char(name);
            end

            switch paramName
                case 'DeviceName'
                    obj.deviceName_ = string(value);
                    vprintf(3, 'hw.VlcRecorder: DeviceName = "%s"', char(value));

                case 'MediaFile'
                    obj.mediaUri_ = string(value);
                    vprintf(3, 'hw.VlcRecorder: MediaFile = "%s"', char(value));

                case 'RecordingFile'
                    obj.recordingFile_ = string(value);
                    vprintf(3, 'hw.VlcRecorder: RecordingFile = "%s"', char(value));

                otherwise
                    vprintf(3, 'hw.VlcRecorder: set_parameter called for "%s" (no-op)', paramName);
            end

            result = 1;
        end

        function value = get_parameter(obj, name) %#ok<INUSD>
            % get_parameter returns nan.
            % Parameter values are cached locally; this interface does not poll hardware.
            value = nan;
        end

        function selected = selectDevice(obj)
            % selected = obj.selectDevice()
            % Show a list dialog of available DirectShow video devices and set
            % DeviceName to the user's choice.
            % Queries available devices via: ffmpeg -list_devices true -f dshow -i dummy
            % Returns:
            %   selected - chosen device name string, or "" if cancelled.

            [~, raw] = system(sprintf('"%s" -list_devices true -f dshow -i dummy 2>&1', ...
                char(obj.ffmpegExePath_)));

            % ffmpeg prints video device names on lines like:
            %   [dshow @ ...] "Device Name" (video)
            tokens = regexp(raw, '"([^"]+)"\s*\(video\)', 'tokens');
            devices = cellfun(@(t) t{1}, tokens, 'UniformOutput', false);

            if isempty(devices)
                uiwait(warndlg( ...
                    sprintf('No DirectShow video devices found.\n\nffmpeg output:\n%s', raw), ...
                    'hw.VlcRecorder', 'modal'));
                selected = "";
                return
            end

            % Pre-select the currently configured device if it is in the list.
            currentIdx = find(strcmp(devices, char(obj.deviceName_)), 1);
            if isempty(currentIdx)
                currentIdx = 1;
            end

            [idx, ok] = listdlg( ...
                'ListString',    devices, ...
                'SelectionMode', 'single', ...
                'InitialValue',  currentIdx, ...
                'Name',          'Select Capture Device', ...
                'PromptString',  'Available DirectShow video devices:', ...
                'ListSize',      [320 160]);

            if ok
                selected = string(devices{idx});
                obj.set_parameter('DeviceName', selected);
            else
                selected = "";
            end
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
                'Webcam recording via ffmpeg with VLC live display.', ...
                [], ...
                @(~) hw.VlcRecorder());
        end
    end


    methods (Access = protected)
        function setup_interface(obj)
            % setup_interface()
            % Create the Module and populate parameters and triggers.
            M = hw.Module(obj, 'VlcRecorder', 'VLC', 1);
            obj.Module = M;

            obj.add_parameter('DeviceName', 'Integrated Camera', ...
                Type    = 'String', ...
                Access  = 'Any', ...
                Visible = true, ...
                Description = 'DirectShow video device name (as reported by ffmpeg -list_devices).');

            obj.add_parameter('RecordingFile', '', ...
                Type    = 'File', ...
                Access  = 'Any', ...
                Visible = true, ...
                Description = 'Output file path for ffmpeg recording. Leave empty to display without recording.');

            obj.add_parameter('MediaFile', 'dshow://', ...
                Type    = 'String', ...
                Access  = 'Any', ...
                Visible = true, ...
                Description = 'Media URI passed to VLC for live display (e.g. dshow://).');

            obj.add_parameter('Play', 0, ...
                isTrigger = true, ...
                Visible   = false, ...
                Description = 'Trigger: launch VLC display and start ffmpeg recording.');

            obj.add_parameter('Stop', 0, ...
                isTrigger = true, ...
                Visible   = false, ...
                Description = 'Trigger: stop ffmpeg recording and close VLC.');

            obj.add_parameter('Pause', 0, ...
                isTrigger = true, ...
                Visible   = false, ...
                Description = 'Trigger: no-op in this backend.');

            obj.add_parameter('StartRecord', 0, ...
                isTrigger = true, ...
                Visible   = false, ...
                Description = 'Trigger: start ffmpeg recording independently of VLC display.');

            obj.add_parameter('StopRecord', 0, ...
                isTrigger = true, ...
                Visible   = false, ...
                Description = 'Trigger: stop ffmpeg recording without closing VLC display.');
        end

        function close_interface(obj)
            % close_interface()
            % Stop any running processes and mark as disconnected.
            obj.stopFfmpeg_();
            obj.stopVlc_();
            obj.IsConnected = false;
        end
    end


    methods (Access = private)
        function launchVlc_(obj)
            % launchVlc_()
            % Launch VLC with the configured media URI for live display.
            % Stores the PID so it can be terminated later.
            if obj.vlcPid_ > 0
                return
            end
            device  = char(obj.deviceName_);
            argStr  = sprintf('dshow:// :dshow-vdev="%s" --no-audio --no-qt-notification', device);
            pid = obj.launchProcess_(obj.vlcExePath_, argStr, false);
            obj.vlcPid_ = pid;
            if pid <= 0
                vprintf(0, 1, 'hw.VlcRecorder: failed to launch VLC or read PID.');
            else
                vprintf(2, 'hw.VlcRecorder: VLC launched, PID=%d', pid);
            end
        end

        function stopVlc_(obj)
            % stopVlc_()
            % Terminate the VLC process launched by this object.
            if obj.vlcPid_ > 0
                system(sprintf('taskkill /PID %d /F /T 2>nul', obj.vlcPid_));
                vprintf(2, 'hw.VlcRecorder: VLC (PID=%d) terminated.', obj.vlcPid_);
                obj.vlcPid_ = 0;
            end
        end

        function launchFfmpeg_(obj)
            % launchFfmpeg_()
            % Launch ffmpeg to record from the DirectShow device to RecordingFile.
            % Stores the PID for later termination via stopFfmpeg_().
            if obj.isRecording_
                vprintf(2, 'hw.VlcRecorder: ffmpeg already recording — skipping duplicate launch.');
                return
            end
            recFile = char(obj.recordingFile_);
            if isempty(recFile)
                vprintf(0, 1, 'hw.VlcRecorder: RecordingFile is empty; cannot start ffmpeg.');
                return
            end
            device = char(obj.deviceName_);
            argStr = sprintf('-y -f dshow -i "video=%s" -vcodec libx264 -preset %s -crf %d "%s"', ...
                device, char(obj.preset_), obj.crf_, recFile);
            pid = obj.launchProcess_(obj.ffmpegExePath_, argStr, true);
            obj.ffmpegPid_ = pid;
            if pid <= 0
                vprintf(0, 1, 'hw.VlcRecorder: failed to launch ffmpeg or read PID.');
            else
                obj.isRecording_ = true;
                vprintf(2, 'hw.VlcRecorder: ffmpeg launched, PID=%d, recording to "%s"', pid, recFile);
            end
        end

        function stopFfmpeg_(obj)
            % stopFfmpeg_()
            % Terminate the ffmpeg recording process.
            % MPEG-TS output is streamable and remains valid even after a forced kill.
            if ~obj.isRecording_ || obj.ffmpegPid_ <= 0
                return
            end
            system(sprintf('taskkill /PID %d /F /T 2>nul', obj.ffmpegPid_));
            pause(0.5);  % allow OS to release file handle before caller checks the file
            vprintf(2, 'hw.VlcRecorder: ffmpeg (PID=%d) terminated.', obj.ffmpegPid_);
            obj.ffmpegPid_   = 0;
            obj.isRecording_ = false;
        end

        function pid = launchProcess_(~, exePath, argStr, hidden)
            % pid = launchProcess_(exePath, argStr, hidden)
            % Launch an external process via a temporary PS1 file and return its PID.
            %
            % Writing a .ps1 file and using 'powershell -File' avoids the
            % double-escaping problem that occurs when embedding quotes inside
            % 'powershell -Command "..."' (which goes through cmd.exe first).
            %
            % Inside the PS1 file, PowerShell single-quoted strings are fully
            % literal — double quotes within them are passed as-is to the process.
            %
            % Inputs:
            %   exePath - full path to the executable
            %   argStr  - argument string; use double-quotes for values with spaces
            %             (e.g. 'video="My Device"') — they will be literal in the PS1
            %   hidden  - true to launch with -WindowStyle Hidden
            % Returns:
            %   pid - process ID, or 0 on failure
            windowStyle = 'Normal';
            if hidden
                windowStyle = 'Hidden';
            end

            % Escape any single quotes in exe path or args for PS1 single-quoted strings.
            exeEsc = strrep(char(exePath), '''', '''''');
            argEsc = strrep(char(argStr),  '''', '''''');

            psFile = [tempname() '.ps1'];
            fid = fopen(psFile, 'w', 'n', 'UTF-8');
            fprintf(fid, '$p = Start-Process -PassThru -WindowStyle %s -FilePath ''%s'' -ArgumentList ''%s''\r\n', ...
                windowStyle, exeEsc, argEsc);
            fprintf(fid, 'if ($p) { Write-Output $p.Id } else { Write-Output 0 }\r\n');
            fclose(fid);

            [~, out] = system(sprintf('powershell -ExecutionPolicy Bypass -NoProfile -File "%s"', psFile));
            delete(psFile);

            pid = str2double(strtrim(out));
            if isnan(pid) || pid <= 0
                pid = 0;
            end
        end
    end

end
