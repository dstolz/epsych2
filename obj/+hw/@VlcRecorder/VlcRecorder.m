classdef VlcRecorder < hw.Interface
    % obj = hw.VlcRecorder()
    % hw.Interface implementation for webcam preview and recording using VLC.
    %
    % connect() initialises the interface. Use set_parameter to configure the
    % device and optional output file, then trigger('Play') to start.
    %
    % When RecordingFile is empty, VLC opens in display-only mode.
    % When RecordingFile is set, the stream is transcoded to H.264 and
    % duplicated to both the display window and the output file (--sout).
    %
    % VLC runs as a tracked child process (System.Diagnostics.Process) with
    % its remote-control interface bound to a private localhost TCP port.
    % Stopping sends 'quit' over that port so VLC shuts down cleanly and the
    % muxer finalises the output file; if VLC does not exit promptly the
    % process is closed or killed as a fallback. Only the VLC instance owned
    % by this object is ever touched.
    %
    % Parameters exposed (via all_parameters):
    %   DeviceName    - (String, Any)  DirectShow video device name.
    %                                  Default: 'Integrated Camera'.
    %   VlcExePath    - (String, Any)  Path to vlc.exe. Auto-detected from the
    %                                  standard install locations when possible.
    %   RecordingFile - (File, Any)    Output file path. Leave empty for display
    %                                  only. Use a .avi or .ts extension; any
    %                                  other extension is replaced with .ts
    %                                  (VLC's mp4 muxer writes broken timestamps
    %                                  for camera captures).
    %   MediaFile     - (String, Any)  Media URI passed to VLC (default: 'dshow://').
    %   DisplayBanner - (String, Any)  Text overlaid on the video window and used as
    %                                  its title. Applied in display-only mode only,
    %                                  so it can never be burned into a recording.
    %                                  Default: '' (no banner).
    %   FrameRate     - (Float, Any)   Capture fps forced via --dshow-fps. Default: 30
    %                                  (a normal webcam rate; the C270 test camera's
    %                                  own default is only 5 fps). 0 = camera default.
    %   Resolution    - (Integer[2])   Capture size [width height] forced via
    %                                  --dshow-size. Default: [0 0] (camera default).
    %   CropTop/Bottom/Left/Right
    %                 - (Integer, Any) Pixels to crop from each edge (default 0).
    %                                  Rounded up to an even number for x264.
    %   MinimalView   - (Boolean, Any) Start VLC in minimal view (--qt-minimal-view):
    %                                  video and playback controls, no menu bar,
    %                                  playlist, or status bar. Default: true.
    %   AlwaysOnTop   - (Boolean, Any) Keep the VLC window above other windows
    %                                  (--video-on-top). Default: false.
    %
    % Triggers (via trigger()):
    %   Play        - Launch VLC. Records to RecordingFile if one is set.
    %   Stop        - Close VLC and finalise any recording.
    %   Pause       - No-op (not supported over command line).
    %   StartRecord - Restart VLC with recording enabled (requires RecordingFile).
    %   StopRecord  - Restart VLC in display-only mode (stops recording).
    %
    % Notes
    %   StartRecord / StopRecord briefly restart the VLC window because the
    %   sout chain cannot be changed on a running instance.
    %
    %   Prefer .ts recordings when crash robustness matters: an MPEG-TS file
    %   remains playable even if VLC dies mid-recording, whereas .avi requires
    %   the clean shutdown performed by trigger('Stop') to write its index.
    %   Both containers open in VLC and in MATLAB's VideoReader.
    %
    % Example
    %   obj = hw.VlcRecorder();
    %   obj.connect();
    %   obj.set_parameter('DeviceName',    'Logi C270 HD WebCam');
    %   obj.set_parameter('RecordingFile', 'C:\data\capture.ts');
    %   obj.trigger('Play');
    %   pause(30);
    %   obj.trigger('Stop');
    %
    % Setup GUI
    %   obj.setupGUI() opens gui.VlcRecorderSetup: a live webcam preview with
    %   an interactive crop ROI for configuring DeviceName, FrameRate,
    %   Resolution, the Crop* parameters, MinimalView, and AlwaysOnTop.
    %
    % See also: documentation/hw/hw_VlcRecorder.md, documentation/hw/hw_Interface.md,
    %           hw.Module, hw.Parameter, gui.VlcRecorderSetup


    properties (SetAccess = protected)
        HW = []  % unused; retained for hw.Interface compatibility
        Module
    end

    properties
        IsConnected = false
    end

    properties (Constant)
        Type = 'VlcRecorder'

        % Cardinal caption corners -> VLC's --marq-position bitfield
        % (center 0, left 1, right 2, top 4, bottom 8). Cardinal names rather
        % than the bitfield because the operator picks a corner, not a number.
        CAPTION_POSITIONS = struct( ...
            'center',    0, ...
            'west',      1, ...
            'east',      2, ...
            'north',     4, ...
            'northwest', 5, ...
            'northeast', 6, ...
            'south',     8, ...
            'southwest', 9, ...
            'southeast', 10)

        % Caption colours as VLC's packed RGB integer (--marq-color). Kept to a
        % named few: this is a legibility choice over an unknown scene, not a
        % palette. Red is offered but is not the default -- a red overlay reads
        % as "recording" on camera software, which is not what this marks.
        CAPTION_COLORS = struct( ...
            'white',   16777215, ...
            'yellow',  16776960, ...
            'green',      65280, ...
            'cyan',       65535, ...
            'magenta', 16711935, ...
            'red',     16711680, ...
            'black',          0)

        % Frame transforms, passed straight to VLC's transform{type=...}. One
        % filter takes one type, so rotating AND flipping is not offered: the
        % eight values are every orientation VLC can produce.
        TRANSFORMS = {'none','90','180','270','hflip','vflip','transpose','antitranspose'}
    end

    properties (SetObservable, AbortSet)
        mode
    end

    properties (Access = private)
        vlcExePath_    (1,1) string = ""                   % path to vlc.exe; auto-detected when empty
        deviceName_    (1,1) string = "Integrated Camera"  % DirectShow video device name
        recordingFile_ (1,1) string = ""                   % output file path; empty = display only
        mediaUri_      (1,1) string = "dshow://"           % media URI for VLC
        displayBanner_ (1,1) string = ""                   % display-only overlay/title text; "" = none
        frameRate_     (1,1) double  = 30                  % dshow capture fps; 0 = camera default
        resolution_    (1,2) double  = [0 0]               % [width height]; [0 0] = camera default
        cropTop_       (1,1) double  = 0                   % crop, in pixels, from the top edge
        cropBottom_    (1,1) double  = 0                   % crop, in pixels, from the bottom edge
        cropLeft_      (1,1) double  = 0                   % crop, in pixels, from the left edge
        cropRight_     (1,1) double  = 0                   % crop, in pixels, from the right edge
        captionEnabled_  (1,1) logical = false              % burn CaptionText into the recording
        captionTemplate_ (1,1) string = "{subject}  {datetime}" % operator's caption, with {tokens}
        captionText_     (1,1) string = ""                  % resolved caption; "" = expand the template here
        captionPosition_ (1,1) string = "southwest"         % cardinal corner of the burned-in caption
        captionSize_     (1,1) double = 20                  % caption font size, px
        captionColor_    (1,1) string = "yellow"            % caption colour name (see CAPTION_COLORS)
        transform_       (1,1) string = "none"              % rotate/flip applied to the frame
        minimalView_   (1,1) logical = true                % start VLC without menus/playlist (--qt-minimal-view)
        alwaysOnTop_   (1,1) logical = false               % keep the VLC window above others (--video-on-top)
        isRecording_   (1,1) logical = false               % true when VLC was launched with --sout recording
        rcPort_        (1,1) double  = 0                   % localhost TCP port of the RC interface
        vlcProc_                                           % System.Diagnostics.Process of the running VLC
    end


    methods
        function obj = VlcRecorder()
            % obj = hw.VlcRecorder()
            % Construct a VlcRecorder without connecting.
            obj.Module = hw.Module.empty(1, 0);
            obj.vlcExePath_ = hw.VlcRecorder.findVlcExe();
        end

        function delete(obj)
            % Ensure the owned VLC process does not outlive the object.
            try
                obj.stopVlc_();
            catch
                % object teardown must not throw
            end
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
            %   result - 1 on success, 0 on failure or unrecognised name.
            if isa(name, 'hw.Parameter')
                name = name.Name;
            end
            switch name
                case 'Play'
                    obj.stopVlc_();
                    result = double(obj.launchVlc_());

                case 'Stop'
                    obj.stopVlc_();
                    result = 1;

                case 'Pause'
                    vprintf(3, 'hw.VlcRecorder: Pause is a no-op for command-line VLC.');
                    result = 1;

                case 'StartRecord'
                    if obj.isRecording_
                        result = 1;
                    elseif strlength(strtrim(obj.recordingFile_)) == 0
                        vprintf(0, 1, 'hw.VlcRecorder: set RecordingFile before StartRecord.');
                        result = 0;
                    else
                        obj.stopVlc_();
                        result = double(obj.launchVlc_());
                    end

                case 'StopRecord'
                    if obj.isRecording_
                        % Restart without recording by temporarily clearing the file path.
                        recFile = obj.recordingFile_;
                        obj.recordingFile_ = "";
                        obj.stopVlc_();
                        launched = obj.launchVlc_();
                        obj.recordingFile_ = recFile;
                        result = double(launched);
                    else
                        result = 1;
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

                case 'VlcExePath'
                    obj.vlcExePath_ = string(value);
                    vprintf(3, 'hw.VlcRecorder: VlcExePath = "%s"', char(value));

                case 'MediaFile'
                    obj.mediaUri_ = string(value);
                    vprintf(3, 'hw.VlcRecorder: MediaFile = "%s"', char(value));

                case 'RecordingFile'
                    obj.recordingFile_ = string(value);
                    vprintf(3, 'hw.VlcRecorder: RecordingFile = "%s"', char(value));

                case 'DisplayBanner'
                    obj.displayBanner_ = string(value);
                    vprintf(3, 'hw.VlcRecorder: DisplayBanner = "%s"', char(value));

                case 'EnableCaption'
                    obj.captionEnabled_ = logical(value);
                    vprintf(3, 'hw.VlcRecorder: EnableCaption = %d', obj.captionEnabled_);

                case 'CaptionTemplate'
                    obj.captionTemplate_ = string(value);
                    vprintf(3, 'hw.VlcRecorder: CaptionTemplate = "%s"', char(value));

                case 'CaptionText'
                    obj.captionText_ = string(value);
                    vprintf(3, 'hw.VlcRecorder: CaptionText = "%s"', char(value));

                case 'CaptionPosition'
                    % An unknown corner falls back to the default rather than
                    % failing the launch: a caption in the wrong corner is a far
                    % better outcome than a run with no video.
                    v = lower(strtrim(string(value)));
                    if isfield(hw.VlcRecorder.CAPTION_POSITIONS, v)
                        obj.captionPosition_ = v;
                    else
                        vprintf(0, 1, 'hw.VlcRecorder: unknown CaptionPosition "%s"; keeping "%s".', ...
                            char(v), char(obj.captionPosition_));
                    end
                    vprintf(3, 'hw.VlcRecorder: CaptionPosition = "%s"', char(obj.captionPosition_));

                case 'CaptionSize'
                    obj.captionSize_ = min(200, max(6, round(double(value))));
                    vprintf(3, 'hw.VlcRecorder: CaptionSize = %d', obj.captionSize_);

                case 'CaptionColor'
                    v = lower(strtrim(string(value)));
                    if isfield(hw.VlcRecorder.CAPTION_COLORS, v)
                        obj.captionColor_ = v;
                    else
                        vprintf(0, 1, 'hw.VlcRecorder: unknown CaptionColor "%s"; keeping "%s".', ...
                            char(v), char(obj.captionColor_));
                    end
                    vprintf(3, 'hw.VlcRecorder: CaptionColor = "%s"', char(obj.captionColor_));

                case 'Transform'
                    v = lower(strtrim(string(value)));
                    if any(strcmp(hw.VlcRecorder.TRANSFORMS, v))
                        obj.transform_ = v;
                    else
                        vprintf(0, 1, 'hw.VlcRecorder: unknown Transform "%s"; keeping "%s".', ...
                            char(v), char(obj.transform_));
                    end
                    vprintf(3, 'hw.VlcRecorder: Transform = "%s"', char(obj.transform_));

                case 'FrameRate'
                    obj.frameRate_ = max(0, double(value));
                    vprintf(3, 'hw.VlcRecorder: FrameRate = %g', obj.frameRate_);

                case 'Resolution'
                    v = double(value);
                    if numel(v) == 2
                        obj.resolution_ = max(0, round(v(:)'));
                        vprintf(3, 'hw.VlcRecorder: Resolution = [%d %d]', obj.resolution_(1), obj.resolution_(2));
                    else
                        vprintf(0, 1, 'hw.VlcRecorder: Resolution must be a [width height] pair; ignoring.');
                    end

                case 'CropTop'
                    obj.cropTop_ = max(0, round(double(value)));
                    vprintf(3, 'hw.VlcRecorder: CropTop = %d', obj.cropTop_);

                case 'CropBottom'
                    obj.cropBottom_ = max(0, round(double(value)));
                    vprintf(3, 'hw.VlcRecorder: CropBottom = %d', obj.cropBottom_);

                case 'CropLeft'
                    obj.cropLeft_ = max(0, round(double(value)));
                    vprintf(3, 'hw.VlcRecorder: CropLeft = %d', obj.cropLeft_);

                case 'CropRight'
                    obj.cropRight_ = max(0, round(double(value)));
                    vprintf(3, 'hw.VlcRecorder: CropRight = %d', obj.cropRight_);

                case 'MinimalView'
                    obj.minimalView_ = logical(value);
                    vprintf(3, 'hw.VlcRecorder: MinimalView = %d', obj.minimalView_);

                case 'AlwaysOnTop'
                    obj.alwaysOnTop_ = logical(value);
                    vprintf(3, 'hw.VlcRecorder: AlwaysOnTop = %d', obj.alwaysOnTop_);

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

                case 'VlcExePath'
                    value = char(obj.vlcExePath_);

                case 'MediaFile'
                    value = char(obj.mediaUri_);

                case 'DisplayBanner'
                    value = char(obj.displayBanner_);

                case 'EnableCaption'
                    value = obj.captionEnabled_;

                case 'CaptionTemplate'
                    value = char(obj.captionTemplate_);

                case 'CaptionText'
                    value = char(obj.captionText_);

                case 'CaptionPosition'
                    value = char(obj.captionPosition_);

                case 'CaptionSize'
                    value = obj.captionSize_;

                case 'CaptionColor'
                    value = char(obj.captionColor_);

                case 'Transform'
                    value = char(obj.transform_);

                case 'FrameRate'
                    value = obj.frameRate_;

                case 'Resolution'
                    value = obj.resolution_;

                case 'CropTop'
                    value = obj.cropTop_;

                case 'CropBottom'
                    value = obj.cropBottom_;

                case 'CropLeft'
                    value = obj.cropLeft_;

                case 'CropRight'
                    value = obj.cropRight_;

                case 'MinimalView'
                    value = obj.minimalView_;

                case 'AlwaysOnTop'
                    value = obj.alwaysOnTop_;

                otherwise
                    % Triggers and unknown names do not map to readable hardware state.
                    value = nan;
            end
        end

        function selected = selectDevice(obj)
            % selected = obj.selectDevice()
            % Show a list dialog of available video capture devices and set
            % DeviceName to the user's choice.
            % Returns:
            %   selected - chosen device name string, or "" if cancelled.

            devices = hw.VlcRecorder.listDevices();

            if isempty(devices)
                uiwait(warndlg( ...
                    'No video capture devices found via Get-PnpDevice.', ...
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
                'PromptString',  'Available video capture devices:', ...
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

        function results = selfTest(obj, options)
            % results = selfTest(obj)
            % results = selfTest(obj, Invasive=true)
            % Check that VLC can be located and a camera is configured. The
            % non-invasive pass never launches VLC; the invasive pass enumerates
            % capture devices and confirms the configured one is present.
            %
            % See also: hw.Interface.selfTest, hw.VlcRecorder.findVlcExe
            arguments
                obj
                options.Invasive (1,1) logical = false
            end

            results = hw.Interface.selfTestResult();

            % vlc.exe: prefer the configured path, fall back to auto-detection
            % the same way launchVlc_ does at run time.
            exe = strtrim(obj.vlcExePath_);
            source = "configured VlcExePath";
            if strlength(exe) == 0
                exe = hw.VlcRecorder.findVlcExe();
                source = "auto-detected";
            end

            if strlength(exe) == 0
                results(end+1) = hw.Interface.selfTestResult('VLC executable', 'fail', ...
                    'vlc.exe could not be located.', ...
                    Remedy = "Install VLC, or set the VlcExePath parameter via View > Webcam Recorder Setup.");
            elseif ~isfile(exe)
                results(end+1) = hw.Interface.selfTestResult('VLC executable', 'fail', ...
                    sprintf('vlc.exe path (%s) does not exist: %s', source, exe), ...
                    Remedy = "Correct VlcExePath via View > Webcam Recorder Setup.");
            else
                results(end+1) = hw.Interface.selfTestResult('VLC executable', 'pass', ...
                    sprintf('Found vlc.exe (%s): %s', source, exe));
            end

            % Camera selection
            if strlength(strtrim(obj.deviceName_)) == 0
                results(end+1) = hw.Interface.selfTestResult('Capture device', 'warn', ...
                    'No DeviceName configured; VLC will fall back to its default camera.', ...
                    Remedy = "Pick a camera in View > Webcam Recorder Setup.");
            else
                results(end+1) = hw.Interface.selfTestResult('Capture device', 'pass', ...
                    sprintf('Configured device: %s', obj.deviceName_));
            end

            if ~options.Invasive
                return
            end

            % Invasive: enumerate cameras (spawns PowerShell; no VLC launch)
            devices = hw.VlcRecorder.listDevices();
            if isempty(devices)
                results(end+1) = hw.Interface.selfTestResult('Device enumeration', 'fail', ...
                    'No video capture devices reported by the operating system.', ...
                    Remedy = "Connect a webcam and confirm it appears in Windows Camera settings.");
                return
            end

            detail = "Available: " + string(devices(:).');
            if strlength(strtrim(obj.deviceName_)) > 0 && ~any(strcmpi(devices, char(obj.deviceName_)))
                results(end+1) = hw.Interface.selfTestResult('Device enumeration', 'fail', ...
                    sprintf('Configured device "%s" is not among the %d device(s) present.', ...
                    obj.deviceName_, numel(devices)), ...
                    Detail = detail, ...
                    Remedy = "Re-select the camera in View > Webcam Recorder Setup.");
            else
                results(end+1) = hw.Interface.selfTestResult('Device enumeration', 'pass', ...
                    sprintf('%d capture device(s) present.', numel(devices)), ...
                    Detail = detail);
            end
        end

        function g = setupGUI(obj, varargin)
            % g = obj.setupGUI()
            % g = obj.setupGUI(Name=Value,...)
            % Open gui.VlcRecorderSetup: a live webcam preview with an
            % interactive crop ROI for configuring DeviceName, FrameRate,
            % Resolution, and CropTop/Bottom/Left/Right.
            % See also: gui.VlcRecorderSetup, documentation/gui/VlcRecorderSetup.md
            g = gui.VlcRecorderSetup(obj, varargin{:});
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

        function txt = expandCaption(template, tokens)
            % txt = hw.VlcRecorder.expandCaption(template)
            % txt = hw.VlcRecorder.expandCaption(template, tokens)
            % Fill the {tokens} in a caption template.
            %
            % Recognised: {subject} {subjects} {box} {file}, supplied by the
            % session, and {date} {time} {datetime}, taken from tokens.When (the
            % session start) or the clock. An unsupplied token expands to
            % nothing rather than being left as literal braces -- a caption
            % reading "{subject}" over a recording is worse than one with a gap,
            % and a rig running without a session has no subject to name.
            %
            % Parameters:
            %   template - caption text with {tokens}
            %   tokens   - struct with any of Subject, Subjects, Box, File, When
            %
            % Returns:
            %   txt - the expanded caption, whitespace-trimmed
            arguments
                template (1,1) string = ""
                tokens (1,1) struct = struct()
            end

            txt = template;
            if strlength(strtrim(txt)) == 0, return, end

            when = datetime('now');
            if isfield(tokens, 'When') && ~isempty(tokens.When)
                when = tokens.When;
            end

            map = struct( ...
                'subject',  localToken(tokens, 'Subject'), ...
                'subjects', localToken(tokens, 'Subjects'), ...
                'box',      localToken(tokens, 'Box'), ...
                'file',     localToken(tokens, 'File'), ...
                'date',     string(datetime(when, 'Format', 'yyyy-MM-dd')), ...
                'time',     string(datetime(when, 'Format', 'HH:mm:ss')), ...
                'datetime', string(datetime(when, 'Format', 'yyyy-MM-dd HH:mm:ss')));

            names = fieldnames(map);
            for i = 1:numel(names)
                txt = replace(txt, "{" + names{i} + "}", map.(names{i}));
            end

            % Anything still in braces was never a token this class knows.
            txt = regexprep(txt, '\{[A-Za-z_]*\}', '');
            txt = strtrim(regexprep(txt, ' {2,}', '  '));

            function v = localToken(s, name)
                if isfield(s, name) && ~isempty(s.(name))
                    v = string(s.(name));
                    v = strjoin(v(:)', ", ");
                else
                    v = "";
                end
            end
        end

        function txt = sampleCaption(template)
            % txt = hw.VlcRecorder.sampleCaption(template)
            % Expand a caption template with visible stand-ins for what only a
            % session knows, for previewing the caption with no session open.
            %
            % Stand-ins rather than empty: the point of a preview is to judge
            % the corner, colour and size against a real frame, and a caption
            % that expanded to a bare date would misrepresent both its length
            % and its position.
            %
            % Parameters:
            %   template - caption text with {tokens}
            %
            % Returns:
            %   txt - the expanded sample caption
            arguments
                template (1,1) string = ""
            end
            txt = hw.VlcRecorder.expandCaption(template, ...
                struct('Subject', "SUBJECT", 'Subjects', "SUBJECT", ...
                       'Box', "1", 'File', "preview"));
        end

        function exePath = findVlcExe()
            % exePath = hw.VlcRecorder.findVlcExe()
            % Locate vlc.exe from the registry, standard install folders, or the
            % system PATH. Returns "" when VLC cannot be found.
            candidates = string.empty(1, 0);
            try
                installDir = winqueryreg('HKEY_LOCAL_MACHINE', 'SOFTWARE\VideoLAN\VLC', 'InstallDir');
                candidates(end+1) = string(fullfile(installDir, 'vlc.exe'));
            catch
                % registry key absent; fall through to default locations
            end
            candidates(end+1) = string(fullfile(getenv('ProgramFiles'), 'VideoLAN', 'VLC', 'vlc.exe'));
            candidates(end+1) = string(fullfile(getenv('ProgramFiles(x86)'), 'VideoLAN', 'VLC', 'vlc.exe'));

            for c = candidates
                if isfile(c)
                    exePath = c;
                    return
                end
            end

            exePath = "";
            [st, out] = system('where vlc.exe');
            if st == 0
                lines = strtrim(splitlines(strtrim(out)));
                lines = lines(~cellfun('isempty', lines));
                if ~isempty(lines)
                    exePath = string(lines{1});
                end
            end
        end

        function devices = listDevices()
            % devices = hw.VlcRecorder.listDevices()
            % Enumerate video capture device names via PowerShell Get-PnpDevice.
            % Returns a cell array of char vectors; empty when none are found.
            devices = {};
            [st, raw] = system(['powershell -NoProfile -Command "' ...
                'Get-PnpDevice -Class Camera -Status OK | ' ...
                'Select-Object -ExpandProperty FriendlyName"']);
            if st == 0 && ~isempty(strtrim(raw))
                lines = strtrim(splitlines(strtrim(raw)));
                devices = lines(~cellfun('isempty', lines));
            end
        end
    end


    methods (Access = protected)
        function setup_interface(obj)
            % setup_interface()
            % Create the Module and populate parameters and triggers.
            M = hw.Module(obj, 'VlcRecorder', 'VLC', 1);
            obj.Module = M;

            obj.add_parameter('DeviceName', char(obj.deviceName_), ...
                Type    = 'String', ...
                Access  = 'Any', ...
                Visible = true, ...
                Description = 'DirectShow video device name.');

            obj.add_parameter('VlcExePath', char(obj.vlcExePath_), ...
                Type    = 'String', ...
                Access  = 'Any', ...
                Visible = true, ...
                Description = 'Full path to the VLC executable (auto-detected when possible).');

            obj.add_parameter('RecordingFile', char(obj.recordingFile_), ...
                Type    = 'File', ...
                Access  = 'Any', ...
                Visible = true, ...
                Description = 'Output file path for VLC recording. Leave empty for display only.');

            obj.add_parameter('MediaFile', char(obj.mediaUri_), ...
                Type    = 'String', ...
                Access  = 'Any', ...
                Visible = true, ...
                Description = 'Media URI passed to VLC (e.g. dshow://).');

            obj.add_parameter('DisplayBanner', char(obj.displayBanner_), ...
                Type    = 'String', ...
                Access  = 'Any', ...
                Visible = true, ...
                Description = 'Text overlaid on the video window and used as its title. Display-only mode; never burned into a recording.');

            obj.add_parameter('EnableCaption', false, ...
                Type    = 'Boolean', ...
                Access  = 'Any', ...
                Visible = true, ...
                PersistWithPhase = true, ...
                Description = 'Burn a caption into the recording naming the subject and session start.');

            obj.add_parameter('CaptionTemplate', char(obj.captionTemplate_), ...
                Type    = 'String', ...
                Access  = 'Any', ...
                Visible = true, ...
                Description = 'Caption text. Tokens {subject} {subjects} {box} {date} {time} {datetime} {file} are filled in when recording starts.');

            obj.add_parameter('CaptionText', char(obj.captionText_), ...
                Type    = 'String', ...
                Access  = 'Any', ...
                Visible = false, ...
                Description = 'Resolved caption actually burned in. Set by the session at recording start; empty means expand CaptionTemplate here.');

            % Values is not an add_parameter option; the choice list goes on the
            % handle it returns.
            P = obj.add_parameter('CaptionPosition', char(obj.captionPosition_), ...
                Type    = 'String', ...
                Access  = 'Any', ...
                Visible = true, ...
                Description = 'Corner of the frame the caption sits in.');
            P.Values = fieldnames(hw.VlcRecorder.CAPTION_POSITIONS)';

            obj.add_parameter('CaptionSize', obj.captionSize_, ...
                Type    = 'Integer', ...
                Access  = 'Any', ...
                Visible = true, ...
                Unit    = 'px', ...
                Min     = 6, ...
                Max     = 200, ...
                Description = 'Caption font size in pixels.');

            P = obj.add_parameter('CaptionColor', char(obj.captionColor_), ...
                Type    = 'String', ...
                Access  = 'Any', ...
                Visible = true, ...
                Description = 'Caption colour.');
            P.Values = fieldnames(hw.VlcRecorder.CAPTION_COLORS)';

            P = obj.add_parameter('Transform', char(obj.transform_), ...
                Type    = 'String', ...
                Access  = 'Any', ...
                Visible = true, ...
                Description = 'Rotate or flip the frame (VLC transform filter). Applies to the recording and the preview alike.');
            P.Values = hw.VlcRecorder.TRANSFORMS;

            obj.add_parameter('FrameRate', obj.frameRate_, ...
                Type    = 'Float', ...
                Access  = 'Any', ...
                Visible = true, ...
                Unit    = 'fps', ...
                Min     = 0, ...
                Description = 'Capture frame rate forced via --dshow-fps. 0 = camera default. Default 30 fps is typical for a webcam (this camera''s native default is only 5 fps).');

            obj.add_parameter('Resolution', obj.resolution_, ...
                Type    = 'Integer', ...
                Access  = 'Any', ...
                Visible = true, ...
                Unit    = 'px', ...
                Min     = 0, ...
                isArray = true, ...
                Description = 'Capture resolution as [width height], forced via --dshow-size. [0 0] = camera default.');

            obj.add_parameter('CropTop', obj.cropTop_, ...
                Type    = 'Integer', ...
                Access  = 'Any', ...
                Visible = true, ...
                Unit    = 'px', ...
                Min     = 0, ...
                Description = 'Pixels to crop from the top of the frame (rounded up to an even number).');

            obj.add_parameter('CropBottom', obj.cropBottom_, ...
                Type    = 'Integer', ...
                Access  = 'Any', ...
                Visible = true, ...
                Unit    = 'px', ...
                Min     = 0, ...
                Description = 'Pixels to crop from the bottom of the frame (rounded up to an even number).');

            obj.add_parameter('CropLeft', obj.cropLeft_, ...
                Type    = 'Integer', ...
                Access  = 'Any', ...
                Visible = true, ...
                Unit    = 'px', ...
                Min     = 0, ...
                Description = 'Pixels to crop from the left of the frame (rounded up to an even number).');

            obj.add_parameter('CropRight', obj.cropRight_, ...
                Type    = 'Integer', ...
                Access  = 'Any', ...
                Visible = true, ...
                Unit    = 'px', ...
                Min     = 0, ...
                Description = 'Pixels to crop from the right of the frame (rounded up to an even number).');

            % PersistWithPhase: these are window settings the operator sets and
            % leaves, not momentary buttons, so a saved phase must restore them
            % (hw.Parameter.isTransientControl otherwise assumes any Boolean the
            % dispatcher never refreshes is a button press).
            obj.add_parameter('MinimalView', obj.minimalView_, ...
                Type    = 'Boolean', ...
                Access  = 'Any', ...
                Visible = true, ...
                PersistWithPhase = true, ...
                Description = 'Start VLC in minimal view (--qt-minimal-view): no menu bar, playlist, or status bar.');

            obj.add_parameter('AlwaysOnTop', obj.alwaysOnTop_, ...
                Type    = 'Boolean', ...
                Access  = 'Any', ...
                Visible = true, ...
                PersistWithPhase = true, ...
                Description = 'Keep the VLC window above other windows (--video-on-top).');

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
        function ok = launchVlc_(obj)
            % ok = launchVlc_()
            % Launch VLC as a tracked child process. If RecordingFile is set,
            % the stream is recorded and previewed simultaneously; otherwise
            % VLC opens in display-only mode.
            % Returns true when VLC starts and survives its argument parsing.
            if obj.isVlcRunning_()
                ok = true;
                return
            end
            ok = false;

            exe = obj.vlcExePath_;
            if strlength(strtrim(exe)) == 0 || ~isfile(exe)
                exe = hw.VlcRecorder.findVlcExe();
                if strlength(exe) == 0
                    vprintf(0, 1, 'hw.VlcRecorder: vlc.exe not found; set the VlcExePath parameter.');
                    return
                end
                obj.vlcExePath_ = exe;
            end

            obj.rcPort_ = obj.pickFreePort_();
            [argStr, recording] = obj.buildVlcArgs_();

            try
                psi = System.Diagnostics.ProcessStartInfo(exe, argStr);
                psi.UseShellExecute = true;  % keep VLC stdio out of the MATLAB console
                proc = System.Diagnostics.Process.Start(psi);
            catch ME
                vprintf(0, 1, ME);
                return
            end

            pause(1);  % give VLC a moment to reject bad arguments
            if isempty(proc) || proc.HasExited
                vprintf(0, 1, 'hw.VlcRecorder: VLC exited immediately after launch; args: %s', argStr);
                return
            end

            obj.vlcProc_     = proc;
            obj.isRecording_ = recording;
            vprintf(2, 'hw.VlcRecorder: VLC launched (PID %d), recording=%d', double(proc.Id), recording);
            ok = true;
        end

        function [argStr, recording] = buildVlcArgs_(obj)
            % [argStr, recording] = buildVlcArgs_()
            % Compose the VLC command line. The RC interface is bound to a
            % private localhost port so stopVlc_ can request a clean shutdown.
            uri = strtrim(char(obj.mediaUri_));
            if isempty(uri)
                uri = 'dshow://';
            end
            recFile = strtrim(char(obj.recordingFile_));

            opts = { ...
                '--no-one-instance', ...  % never forward args to a pre-existing VLC window
                '--no-qt-privacy-ask', ...
                '--no-video-title-show', ...
                '--no-audio', ...
                '--extraintf', 'rc', ...
                '--rc-host', sprintf('127.0.0.1:%d', obj.rcPort_), ...
                '--rc-quiet'};

            % Both are stated explicitly rather than only when enabled: VLC
            % persists them in the user's vlcrc, so an operator who toggled
            % minimal view (Ctrl+H) or always-on-top in their own VLC would
            % otherwise carry that setting into every session here.
            opts{end+1} = obj.boolOpt_('qt-minimal-view', obj.minimalView_);
            opts{end+1} = obj.boolOpt_('video-on-top',    obj.alwaysOnTop_);

            if strncmpi(uri, 'dshow', 5)
                opts{end+1} = sprintf('--dshow-vdev="%s"', char(obj.deviceName_));
                opts{end+1} = '--dshow-adev=none';
                if obj.frameRate_ > 0
                    opts{end+1} = sprintf('--dshow-fps=%g', obj.frameRate_);
                end
                if all(obj.resolution_ > 0)
                    opts{end+1} = sprintf('--dshow-size=%dx%d', obj.resolution_(1), obj.resolution_(2));
                end
            end

            filterSpec = obj.videoFilterSpec_();

            recording = ~isempty(recFile);
            if recording
                [recDir, recBase, recExt] = fileparts(recFile);
                if ~isempty(recDir) && ~isfolder(recDir)
                    mkdir(recDir);
                end

                switch lower(recExt)
                    case '.avi'
                        mux = 'avi';
                    case '.ts'
                        mux = 'ts';
                    otherwise
                        % VLC's mp4 muxer produces unplayable timestamps for
                        % dshow captures, so only avi and ts are supported.
                        mux = 'ts';
                        recFile = fullfile(recDir, [recBase '.ts']);
                        obj.recordingFile_ = string(recFile);
                        vprintf(0, 1, 'hw.VlcRecorder: only .avi and .ts containers record reliably; recording to "%s" instead.', recFile);
                end

                % VLC config-chain syntax: forward slashes and a single-quoted dst.
                recVlc = strrep(recFile, '\', '/');
                recVlc = strrep(recVlc, '''', '''''');

                if isempty(filterSpec)
                    vfilterOpt = '';
                else
                    % Single-quoted: without the quotes VLC's sout parser splits
                    % the value at ':' and silently keeps only the first filter.
                    vfilterOpt = sprintf('vfilter=''%s'',', filterSpec);
                end

                % sfilter=marq puts the marquee INTO the transcode's subpicture
                % chain and soverlay blends it into the frames, which is what
                % burns the caption into the file. The marquee's text and
                % appearance ride along as ordinary --marq-* options.
                captionOpts = obj.captionOpts_();
                if isempty(captionOpts)
                    soverlayOpt = '';
                else
                    soverlayOpt = ',sfilter=marq,soverlay';
                end

                % transcode must come before duplicate: a chained value inside
                % duplicate{dst=...} is split at ':' by VLC's option parser.
                % zerolatency stops x264 buffering frames so the file grows
                % continuously and short recordings are not lost in the encoder.
                sout = sprintf(['#transcode{%svcodec=h264,venc=x264{preset=ultrafast,tune=zerolatency},vb=1200,acodec=none%s}' ...
                    ':duplicate{dst=display,dst=standard{access=file,mux=%s,dst=''%s''}}'], ...
                    vfilterOpt, soverlayOpt, mux, recVlc);
                opts{end+1} = sprintf('"--sout=%s"', sout);
                opts{end+1} = '--sout-keep';
                opts = [opts, captionOpts];
            else
                if ~isempty(filterSpec)
                    % Display-only mode: apply the filter chain directly so the
                    % preview matches what a recording would contain. Here the
                    % ':' chain needs no quoting -- it is a plain option value,
                    % not a sout config chain.
                    opts{end+1} = sprintf('--video-filter=%s', filterSpec);
                end
                % One marquee sub-source, so these two cannot both be drawn.
                % DisplayBanner wins when set: its whole job is to warn that a
                % stream is NOT being recorded, and a caption must never
                % displace that. It is empty in the setup dialog's "Preview in
                % VLC", which is where the caption preview is wanted -- so the
                % preview shows the caption in its real corner, colour and
                % size, and the live view keeps its warning.
                %
                % The banner is only ever added on this branch, so no code path
                % can burn it into a recorded file.
                bannerOpts = obj.displayBannerOpts_();
                if isempty(bannerOpts)
                    opts = [opts, obj.displayCaptionOpts_()];
                else
                    opts = [opts, bannerOpts];
                end
            end

            argStr = sprintf('%s "%s"', strjoin(opts, ' '), uri);
        end

        function opt = boolOpt_(~, name, tf)
            % opt = boolOpt_(name, tf)
            % Format a VLC boolean switch as '--name' or '--no-name'.
            if tf
                opt = ['--' name];
            else
                opt = ['--no-' name];
            end
        end

        function opts = displayBannerOpts_(obj)
            % opts = displayBannerOpts_()
            % VLC options that overlay DisplayBanner on the video and use it as
            % the window title. Returns {} when no banner is configured.
            %
            % marq-timeout=0 keeps the overlay up for the life of the window, so
            % the label cannot scroll away and leave an unlabelled stream. The
            % text is deliberately not red: a red overlay reads as "recording"
            % on camera software, which is the opposite of what this marks.
            banner = strtrim(char(obj.displayBanner_));
            if isempty(banner)
                opts = {};
                return
            end

            opts = [{'--sub-source=marq'}, ...
                obj.marqOpts_(banner, 'north', 'yellow', 24), ...
                {sprintf('--meta-title="%s"', strrep(banner, '"', ''''))}];
        end

        function opts = displayCaptionOpts_(obj)
            % opts = displayCaptionOpts_()
            % The recording caption drawn on a PREVIEW window, in its own
            % position, colour and size, so "Preview in VLC" shows what the
            % recording will actually look like. Returns {} when the caption is
            % off or resolves to nothing.
            %
            % A preview needs '--sub-source=marq' because there is no transcode
            % chain to hang an sfilter on; that is the whole difference between
            % this and captionOpts_, which is why the two are separate methods
            % over one shared option builder rather than one method with a flag.
            txt = strtrim(char(obj.resolvedCaption_()));
            if isempty(txt)
                opts = {};
                return
            end

            opts = [{'--sub-source=marq'}, ...
                obj.marqOpts_(txt, char(obj.captionPosition_), ...
                              char(obj.captionColor_), obj.captionSize_)];
        end

        function opts = marqOpts_(~, txt, position, color, fontSize)
            % opts = marqOpts_(txt, position, color, fontSize)
            % The --marq-* options for one marquee: text, corner, colour, size.
            % Shared by the display banner, the preview caption, and the
            % recording caption, so all three quote and place text alike.
            %
            % VLC has ONE marquee sub-source with one set of options, so a
            % window can show one marquee and not two; who wins is decided by
            % the caller (see buildVlcArgs_).
            %
            % marq-timeout=0 keeps the overlay up for the life of the window, so
            % a label cannot scroll away and leave an unmarked stream.

            % Double quotes terminate the option value; swap them for single.
            txt = strrep(char(txt), '"', '''');

            opts = { ...
                sprintf('--marq-marquee="%s"', txt), ...
                sprintf('--marq-position=%d', hw.VlcRecorder.CAPTION_POSITIONS.(char(position))), ...
                sprintf('--marq-color=%d', hw.VlcRecorder.CAPTION_COLORS.(char(color))), ...
                '--marq-opacity=255', ...
                sprintf('--marq-size=%d', fontSize), ...
                '--marq-timeout=0'};
        end

        function spec = cropFilterSpec_(obj)
            % spec = cropFilterSpec_()
            % Build a VLC croppadd{} filter spec from the CropTop/Bottom/Left/Right
            % parameters. Returns '' when no crop is configured. x264 requires
            % even frame dimensions, so each nonzero value is rounded up to the
            % nearest even number.
            raw  = [obj.cropTop_, obj.cropBottom_, obj.cropLeft_, obj.cropRight_];
            even = ceil(raw / 2) * 2;
            if any(even ~= raw)
                vprintf(1, 'hw.VlcRecorder: crop values rounded up to even pixel counts (top=%d bottom=%d left=%d right=%d).', ...
                    even(1), even(2), even(3), even(4));
            end

            names = {'croptop', 'cropbottom', 'cropleft', 'cropright'};
            terms = cell(1, 4);
            for i = 1:4
                if even(i) > 0
                    terms{i} = sprintf('%s=%d', names{i}, even(i));
                end
            end
            terms = terms(~cellfun('isempty', terms));

            if isempty(terms)
                spec = '';
            else
                spec = sprintf('croppadd{%s}', strjoin(terms, ','));
            end
        end

        function spec = videoFilterSpec_(obj)
            % spec = videoFilterSpec_()
            % The whole video filter chain -- crop, then rotate/flip -- as VLC's
            % ':'-separated module chain, or '' when neither is configured.
            %
            % Crop comes first so the crop values keep meaning what the operator
            % sees in the un-rotated preview; rotating first would silently
            % reinterpret "top" as "left".
            %
            % NOTE the chain is returned UNQUOTED. Where it goes decides how it
            % must be embedded, and the two are not the same:
            %   --video-filter=a:b        (display) chains as-is
            %   vfilter='a:b'             (inside --sout) needs the single quotes
            % Without them VLC's sout config-chain parser splits the value at
            % the ':' and keeps only the first filter -- no error, no log line,
            % the rotation simply never happens. Verified on VLC 3 against a
            % dshow capture (see documentation/hw/hw_VlcRecorder.md).
            terms = {obj.cropFilterSpec_()};
            if ~strcmp(obj.transform_, "none")
                terms{end+1} = sprintf('transform{type=%s}', char(obj.transform_));
            end
            terms = terms(~cellfun('isempty', terms));
            spec = strjoin(terms, ':');
        end

        function opts = captionOpts_(obj)
            % opts = captionOpts_()
            % VLC options for the burned-in recording caption, or {} when the
            % caption is off or resolves to nothing.
            %
            % These carry only the marquee's TEXT and appearance. What actually
            % gets it into the file is 'sfilter=marq,soverlay' inside the
            % transcode chain (see buildArgs): '--sub-source=marq' decorates the
            % display vout only, and a recording made with it -- plus soverlay --
            % comes out clean, which is how the display banner has always been
            % kept out of recordings.
            txt = strtrim(char(obj.resolvedCaption_()));
            if isempty(txt)
                opts = {};
                return
            end

            % No '--sub-source=marq' here: on the recording branch the marquee
            % is reached through the transcode's sfilter instead (see buildArgs).
            opts = obj.marqOpts_(txt, char(obj.captionPosition_), ...
                                 char(obj.captionColor_), obj.captionSize_);
        end

        function txt = resolvedCaption_(obj)
            % txt = resolvedCaption_()
            % The caption text to burn in: whatever the session resolved into
            % CaptionText, else the template expanded against what this object
            % knows on its own (the clock), so a recorder driven directly still
            % captions its recordings.
            if ~obj.captionEnabled_
                txt = "";
            elseif strlength(strtrim(obj.captionText_)) > 0
                txt = obj.captionText_;
            else
                txt = hw.VlcRecorder.expandCaption(obj.captionTemplate_);
            end
        end

        function stopVlc_(obj)
            % stopVlc_()
            % Stop the owned VLC instance: ask the RC interface to quit so the
            % muxer finalises the output, then escalate to window close / kill.
            proc = obj.vlcProc_;
            obj.vlcProc_     = [];
            obj.isRecording_ = false;
            if isempty(proc)
                return
            end

            try
                if ~proc.HasExited
                    if ~(obj.sendRcQuit_() && proc.WaitForExit(8000))
                        proc.CloseMainWindow();
                        if ~proc.WaitForExit(3000)
                            proc.Kill();
                            proc.WaitForExit(3000);
                        end
                    end
                end
                vprintf(2, 'hw.VlcRecorder: VLC stopped.');
            catch ME
                vprintf(0, 1, ME);
            end
            obj.rcPort_ = 0;
        end

        function ok = sendRcQuit_(obj)
            % ok = sendRcQuit_()
            % Send 'quit' to the running VLC over its RC TCP port.
            % Returns true when the command was delivered.
            ok = false;
            if obj.rcPort_ <= 0
                return
            end
            try
                client = System.Net.Sockets.TcpClient();
                client.Connect('127.0.0.1', int32(obj.rcPort_));
                stream  = client.GetStream();
                payload = uint8(sprintf('quit\n'));
                stream.Write(payload, int32(0), int32(numel(payload)));
                stream.Flush();
                client.Close();
                ok = true;
            catch ME
                vprintf(2, 'hw.VlcRecorder: RC quit failed (%s); closing the window instead.', ME.message);
            end
        end

        function tf = isVlcRunning_(obj)
            % tf = isVlcRunning_()
            % True when the owned VLC process is alive.
            tf = false;
            if isempty(obj.vlcProc_)
                return
            end
            try
                tf = ~obj.vlcProc_.HasExited;
            catch
                obj.vlcProc_ = [];
            end
        end

        function port = pickFreePort_(~)
            % port = pickFreePort_()
            % Ask the OS for a free ephemeral TCP port on loopback.
            try
                listener = System.Net.Sockets.TcpListener(System.Net.IPAddress.Loopback, 0);
                listener.Start();
                port = double(listener.LocalEndpoint.Port);
                listener.Stop();
            catch
                port = randi([20000 65000]);
            end
        end
    end

end
