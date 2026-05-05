classdef VlcRecorder < hw.Interface
    % obj = hw.VlcRecorder()
    % hw.Interface implementation for webcam preview and recording using VLC.
    %
    % connect() initialises the interface. Use set_parameter to configure the
    % device and optional output file, then trigger('Play') to start.
    %
    % When RecordingFile is empty, VLC opens in display-only mode.
    % When RecordingFile is set, VLC duplicates the stream to both the
    % display window and the output file simultaneously using --sout.
    %
    % Parameters exposed (via all_parameters):
    %   DeviceName    - (String, Any)  DirectShow video device name.
    %                                  Default: 'Integrated Camera'.
    %   RecordingFile - (File, Any)    Output file path. Leave empty for display only.
    %   MediaFile     - (String, Any)  Media URI passed to VLC (default: 'dshow://').
    %
    % Triggers (via trigger()):
    %   Play        - Launch VLC. Records to RecordingFile if one is set.
    %   Stop        - Close VLC and finalise any recording.
    %   Pause       - No-op (not supported over command line).
    %   StartRecord - Restart VLC with recording enabled (if not already recording).
    %   StopRecord  - Restart VLC in display-only mode (stops recording).
    %
    % Notes
    %   VLC is expected at vlcExePath_ (default:
    %   'C:\Program Files (x86)\VideoLAN\VLC\vlc.exe').
    %
    %   StartRecord / StopRecord briefly restart the VLC window because the
    %   sout chain cannot be changed on a running instance.
    %
    % Example
    %   obj = hw.VlcRecorder();
    %   obj.connect();
    %   obj.set_parameter('DeviceName',    'Integrated Camera');
    %   obj.set_parameter('RecordingFile', 'C:\data\capture.ts');
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
        deviceName_    (1,1) string = "Integrated Camera"  % DirectShow video device name
        recordingFile_ (1,1) string = ""                   % output file path; empty = display only
        mediaUri_      (1,1) string = "dshow://"            % media URI for VLC
        isRecording_   (1,1) logical = false                % true when VLC was launched with --sout recording
        vlcPid_        (1,1) double  = 0                    % 0=stopped, -1=running (PID not tracked)
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
            % call trigger('Play') to start VLC.
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
                    obj.stopVlc_();
                    obj.launchVlc_();

                case 'Stop'
                    obj.stopVlc_();

                case 'Pause'
                    vprintf(3, 'hw.VlcRecorder: Pause is a no-op for command-line VLC.');

                case 'StartRecord'
                    if ~obj.isRecording_
                        obj.stopVlc_();
                        obj.launchVlc_();
                    end

                case 'StopRecord'
                    if obj.isRecording_
                        % Restart without recording by temporarily clearing the file path.
                        recFile = obj.recordingFile_;
                        obj.recordingFile_ = "";
                        obj.stopVlc_();
                        obj.launchVlc_();
                        obj.recordingFile_ = recFile;
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

        function value = get_parameter(obj, name)
            % value = obj.get_parameter(name)
            % Return cached parameter values for interface parameters.
            if isa(name, 'hw.Parameter')
                paramName = name.Name;
            else
                paramName = char(name);
            end

            switch paramName
                case 'DeviceName'
                    value = char(obj.deviceName_);

                case 'RecordingFile'
                    value = char(obj.recordingFile_);

                case 'MediaFile'
                    value = char(obj.mediaUri_);

                otherwise
                    % Triggers and unknown names do not map to readable hardware state.
                    value = nan;
            end
        end

        function selected = selectDevice(obj)
            % selected = obj.selectDevice()
            % Show a list dialog of available DirectShow video capture devices and
            % set DeviceName to the user's choice.
            % Enumerates devices via PowerShell Get-PnpDevice.
            % Returns:
            %   selected - chosen device name string, or "" if cancelled.

            [st, raw] = system(['powershell -NoProfile -Command "' ...
                'Get-PnpDevice -Class Camera -Status OK | ' ...
                'Select-Object -ExpandProperty FriendlyName"']);

            devices = {};
            if st == 0 && ~isempty(strtrim(raw))
                lines = strtrim(splitlines(strtrim(raw)));
                devices = lines(~cellfun('isempty', lines));
            end

            if isempty(devices)
                uiwait(warndlg( ...
                    'No DirectShow video devices found via Get-PnpDevice.', ...
                    'hw.VlcRecorder', 'modal'));
                selected = "";
                return
            end

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
                'Webcam preview and recording via VLC command line.', ...
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
                Description = 'DirectShow video device name.');

            obj.add_parameter('RecordingFile', '', ...
                Type    = 'File', ...
                Access  = 'Any', ...
                Visible = true, ...
                Description = 'Output file path for VLC recording. Leave empty for display only.');

            obj.add_parameter('MediaFile', 'dshow://', ...
                Type    = 'String', ...
                Access  = 'Any', ...
                Visible = true, ...
                Description = 'Media URI passed to VLC (e.g. dshow://).');

            obj.add_parameter('Play', 0, ...
                isTrigger = true, ...
                Visible   = false, ...
                Description = 'Trigger: launch VLC preview and recording (if RecordingFile is set).');

            obj.add_parameter('Stop', 0, ...
                isTrigger = true, ...
                Visible   = false, ...
                Description = 'Trigger: close VLC and finalise any recording.');

            obj.add_parameter('Pause', 0, ...
                isTrigger = true, ...
                Visible   = false, ...
                Description = 'Trigger: no-op.');

            obj.add_parameter('StartRecord', 0, ...
                isTrigger = true, ...
                Visible   = false, ...
                Description = 'Trigger: restart VLC with recording enabled.');

            obj.add_parameter('StopRecord', 0, ...
                isTrigger = true, ...
                Visible   = false, ...
                Description = 'Trigger: restart VLC in display-only mode.');
        end

        function close_interface(obj)
            % close_interface()
            % Stop any running processes and mark as disconnected.
            obj.stopVlc_();
            obj.IsConnected = false;
        end
    end


    methods (Access = private)
        function launchVlc_(obj)
            % launchVlc_()
            % Launch VLC. If RecordingFile is set, uses --sout to simultaneously
            % display and record. Otherwise opens in display-only mode.
            if obj.vlcPid_ ~= 0
                return
            end
            device  = char(obj.deviceName_);
            uri     = char(obj.mediaUri_);
            recFile = char(obj.recordingFile_);

            if isempty(recFile)
                % Display only.
                argStr = sprintf('%s --one-instance --dshow-vdev="%s" --no-audio', ...
                    uri, device);
                obj.isRecording_ = false;
            else
                % Record and preview simultaneously using duplicate stream output.
                % The file branch transcodes to H264 for robust webcam capture.
                recVlc = strrep(recFile, '\\', '/');
                recVlc = strrep(recVlc, '''', '''''');

                [~, ~, ext] = fileparts(recFile);
                mux = 'ts';
                if strcmpi(ext, '.mp4')
                    mux = 'mp4';
                end

                sout = sprintf('#duplicate{dst=display,dst=transcode{vcodec=h264,vb=1200,fps=30,acodec=none}:standard{access=file,mux=%s,dst=''%s''}}', ...
                    mux, recVlc);
                argStr = sprintf('%s --one-instance --dshow-vdev="%s" --no-audio --sout "%s" --sout-keep', ...
                    uri, device, sout);
                obj.isRecording_ = true;
            end

            launched = obj.launchProcess_(obj.vlcExePath_, argStr);
            if ~launched
                obj.vlcPid_ = 0;
                obj.isRecording_ = false;
                vprintf(0, 1, 'hw.VlcRecorder: failed to launch VLC.');
            else
                obj.vlcPid_ = -1;
                vprintf(2, 'hw.VlcRecorder: VLC launched, recording=%d', obj.isRecording_);
            end
        end

        function stopVlc_(obj)
            % stopVlc_()
            % Terminate VLC processes (PID tracking intentionally not used).
            if obj.vlcPid_ ~= 0
                % Ask VLC to quit cleanly first so muxers can finalize output.
                system(sprintf('"%s" --one-instance vlc://quit 1>nul 2>nul', char(obj.vlcExePath_)));
                pause(1.0);

                % Fallback in case VLC does not exit promptly.
                [~, tl] = system('tasklist /FI "IMAGENAME eq vlc.exe" /FO CSV /NH 2>nul');
                if contains(lower(tl), 'vlc.exe')
                    system('taskkill /IM vlc.exe /T 2>nul');
                end
                pause(0.5);  % allow VLC to flush file buffers before caller checks output
                vprintf(2, 'hw.VlcRecorder: VLC terminated.');
                obj.vlcPid_      = 0;
                obj.isRecording_ = false;
            end
        end

        function launched = launchProcess_(~, exePath, argStr)
            % launched = launchProcess_(exePath, argStr)
            % Launch VLC via a temporary .bat file using plain cmd.exe syntax.
            %
            % A one-line .bat file is written containing:
            %   start "" "exePath" argStr
            % This avoids PowerShell and uses VLC command-line options directly.
            %
            % Inputs:
            %   exePath - full path to vlc.exe
            %   argStr  - VLC argument string; embedded double-quotes are preserved
            % Returns:
            %   launched - true when cmd accepted the launch command

            batFile = [tempname() '.bat'];
            fid = fopen(batFile, 'w', 'n', 'UTF-8');
            fprintf(fid, '@echo off\r\nstart "" "%s" %s\r\n', char(exePath), char(argStr));
            fclose(fid);
            [st, ~] = system(sprintf('cmd /c "%s"', batFile));
            delete(batFile);

            launched = (st == 0);
        end
    end

end
