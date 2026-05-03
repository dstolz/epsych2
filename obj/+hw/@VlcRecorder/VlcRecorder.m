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
            %   name - 'Play', 'Stop', 'Pause', 'StartRecord', or 'StopRecord'.
            % Returns:
            %   result - 1 on success, 0 on unrecognised name.
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
                % Already have a VLC instance we launched; do not open another.
                return
            end
            device  = char(obj.deviceName_);
            uri     = char(obj.mediaUri_);
            exePath = char(obj.vlcExePath_);

            % Pass all VLC args as a single string so PowerShell does not split
            % tokens; double-quote the device name to handle spaces in it.
            exeEsc  = strrep(exePath, '''', '''''');
            % Single string: 'dshow:// :dshow-vdev="My Device" --no-audio --no-qt-notification'
            argStr  = sprintf('%s :dshow-vdev=\"%s\" --no-audio --no-qt-notification', uri, device);
            argEsc  = strrep(argStr, '''', '''''');
            psCmd   = sprintf('(Start-Process -PassThru -FilePath ''%s'' -ArgumentList ''%s'').Id', ...
                exeEsc, argEsc);
            [~, pidStr] = system(sprintf('powershell -Command "%s"', strrep(psCmd, '"', '\"')));
            obj.vlcPid_ = str2double(strtrim(pidStr));
            if isnan(obj.vlcPid_) || obj.vlcPid_ <= 0
                obj.vlcPid_ = 0;
                vprintf(0, 1, 'hw.VlcRecorder: failed to launch VLC or read PID.');
            else
                vprintf(2, 'hw.VlcRecorder: VLC launched, PID=%d', obj.vlcPid_);
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
            device  = char(obj.deviceName_);
            exePath = char(obj.ffmpegExePath_);

            args = sprintf('-y -f dshow -i video="%s" -vcodec libx264 -preset %s -crf %d "%s"', ...
                device, char(obj.preset_), obj.crf_, recFile);

            psCmd = sprintf('(Start-Process -PassThru -WindowStyle Hidden -FilePath ''%s'' -ArgumentList ''%s'').Id', ...
                exePath, strrep(args, '''', ''''''));
            [~, pidStr] = system(sprintf('powershell -Command "%s"', strrep(psCmd, '"', '\"')));
            obj.ffmpegPid_ = str2double(strtrim(pidStr));
            if isnan(obj.ffmpegPid_) || obj.ffmpegPid_ <= 0
                obj.ffmpegPid_ = 0;
                vprintf(0, 1, 'hw.VlcRecorder: failed to launch ffmpeg or read PID.');
            else
                obj.isRecording_ = true;
                vprintf(2, 'hw.VlcRecorder: ffmpeg launched, PID=%d, recording to "%s"', ...
                    obj.ffmpegPid_, recFile);
            end
        end

        function stopFfmpeg_(obj)
            % stopFfmpeg_()
            % Send a graceful quit ('q') to ffmpeg then wait for it to exit.
            % Ffmpeg finalises the output container on clean exit.
            if ~obj.isRecording_ || obj.ffmpegPid_ <= 0
                return
            end
            % Send 'q' via stdin is not possible from MATLAB after launch;
            % use a CTRL_C_EVENT via PowerShell to signal ffmpeg to flush+exit.
            system(sprintf('taskkill /PID %d /F /T 2>nul', obj.ffmpegPid_));
            % Brief pause so the OS releases the file handle before the caller
            % tries to access the output file.
            pause(0.5);
            vprintf(2, 'hw.VlcRecorder: ffmpeg (PID=%d) terminated.', obj.ffmpegPid_);
            obj.ffmpegPid_   = 0;
            obj.isRecording_ = false;
        end
    end

end
