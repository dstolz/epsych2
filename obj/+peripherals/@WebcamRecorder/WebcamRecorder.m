classdef WebcamRecorder < handle
    % WebcamRecorder Video preview and disk recording for webcam devices.
    %
    %   WebcamRecorder(deviceName) creates a recorder for the specified
    %   video device.
    %
    %   WebcamRecorder(deviceName, opts) configures recording, preview,
    %   optional audio capture, and optional UI controls.
    %
    %   This class wraps Image Acquisition Toolbox video input for webcam
    %   preview and disk logging through VideoWriter. It can also capture a
    %   mono audio track separately with AUDIRecorder and save timing
    %   metadata for later synchronization.
    %
    %   Inputs
    %     deviceName  Name of the video device to use.
    %
    %     opts        Name-value style options passed as a struct:
    %       Filename             Output video file path.
    %       Parent               Parent graphics container for preview/UI.
    %       VideoProfile         VideoWriter profile, e.g. "MPEG-4".
    %       RecordingResolution  Requested recording resolution [W H].
    %       RecordingFrameRate   Requested recording frame rate in Hz.
    %       PreviewFrameRate     Preview update rate in Hz.
    %       Adaptor              Image Acquisition adaptor name.
    %       AudioDeviceName      Audio input device name substring.
    %       AudioSampleRate      Audio sample rate in Hz.
    %       AudioBitsPerSample   Audio bit depth, 8 or 16.
    %       ShowControls         True to build UI controls in Parent.
    %
    %   Public properties
    %     Filename              Output video file path.
    %     Parent                Parent graphics container.
    %     VideoProfile          VideoWriter profile.
    %     PreviewFrameRate      Preview update rate.
    %     AudioDeviceName       Audio input device name.
    %     AudioSampleRate       Audio sample rate.
    %     AudioBitsPerSample    Audio bit depth.
    %     ShowControls          Whether the control panel is shown.
    %     RecordingResolution   Active/requested recording resolution.
    %     RecordingFrameRate    Active/requested recording frame rate.
    %     IsRecording           True while recording.
    %     IsPreviewing          True while preview is active.
    %     DeviceName            Selected video device name.
    %     Adaptor               Selected Image Acquisition adaptor.
    %     AvailableFormats      Supported device format strings.
    %     Duration              Elapsed recording duration in seconds.
    %
    %   Methods
    %     WebcamRecorder        Construct recorder, resolve device/format,
    %                           and optionally build UI controls.
    %     delete                Stop activity and release timers, listeners,
    %                           and device resources.
    %     startPreview          Start throttled live preview in the parent UI.
    %     stopPreview           Stop live preview.
    %     startRecording        Start disk recording and optional audio
    %                           capture.
    %     stopRecording         Stop recording, save audio, and write sync
    %                           metadata.
    %     start                 Start preview and recording together.
    %     stop                  Stop recording and preview together.
    %     estimateMBPerMinute   Estimate storage usage from current settings.
    %     snapshot              Save a single frame to PNG.
    %     listDevices           Enumerate available devices and formats for
    %                           an adaptor.
    %
    %   Example
    %     rec = WebcamRecorder("HD Webcam", struct('Filename', "test.mp4"));
    %
    %   See also imaqhwinfo, videoinput, VideoWriter, audiorecorder

    properties
        Filename            (1,1) string = ""      % Output video file path
        Parent = []                                % UI container for controls/preview
        VideoProfile        (1,1) string = "MPEG-4" % VideoWriter profile (e.g. 'MPEG-4')
        PreviewFrameRate    (1,1) double {mustBePositive} = 15 % Preview frame rate (Hz)
        AudioDeviceName     (1,1) string = ""      % Name of audio input device
        AudioSampleRate     (1,1) double {mustBePositive} = 44100 % Audio sample rate (Hz)
        AudioBitsPerSample  (1,1) double {mustBeMember(AudioBitsPerSample,[8 16])} = 16 % Audio bit depth (8 or 16)
        ShowControls        (1,1) logical = false  % Show UI controls (default false)
    end

    properties (SetObservable)
        RecordingResolution (1,2) double {mustBePositive} = [1920 1080] % [width height] in pixels
        RecordingFrameRate  (1,1) double {mustBePositive} = 30          % Recording frame rate (Hz)
    end

    properties (SetAccess = private)
        IsRecording  (1,1) logical = false    % True if currently recording
        IsPreviewing (1,1) logical = false    % True if preview is active
        DeviceName   (1,1) string  = ""      % Name of selected video device
        Adaptor      (1,1) string  = "winvideo" % Video adaptor name
    end

    properties (Dependent, SetAccess = private)
        AvailableFormats    % Supported video formats for device
        Duration           % Elapsed recording time (s)
    end

    properties (Access = private)
        videoInput_
        videoWriter_
        audioRecorder_
        previewImage_
        previewAxes_
        lastPreviewTime_ uint64 = 0
        recordingStartTime_ uint64 = 0
        recordingStartDateTime_ datetime = NaT
        deviceID_ (1,1) double = 1
        formatString_ (1,1) string = ""
        rootLayout_
        controlPanel_
        btnRecord_
        btnPreview_
        btnSnapshot_
        ddDevice_
        ddFormat_
        lblInfo_
        durationTimer_
        propListeners_
        suppressSettingsCallback_ (1,1) logical = false
        isConstructed_ (1,1) logical = false
        audioWasStarted_ (1,1) logical = false
    end

    methods
        function obj = WebcamRecorder(deviceName, opts)
            % WebcamRecorder Construct recorder, resolve hardware, and initialize UI state.
            arguments
                deviceName          (1,1) string
                opts.Filename       (1,1) string = ""
                opts.Parent = []
                opts.VideoProfile   (1,1) string = "MPEG-4"
                opts.RecordingResolution (1,2) double {mustBePositive} = [800 600]
                opts.RecordingFrameRate  (1,1) double {mustBePositive} = 25
                opts.PreviewFrameRate    (1,1) double {mustBePositive} = 15
                opts.Adaptor        (1,1) string = "winvideo"
                opts.AudioDeviceName (1,1) string = ""
                opts.AudioSampleRate (1,1) double {mustBePositive} = 44100
                opts.AudioBitsPerSample (1,1) double {mustBeMember(opts.AudioBitsPerSample,[8 16])} = 16
                opts.ShowControls   (1,1) logical = false
            end

            sp = matlabshared.supportpkg.getSupportPackageRoot;
            wp = fullfile(sp, "toolbox", "matlab", "webcam", "supportpackages");
            if isfolder(wp) && ~contains(path, wp)
                addpath(wp)
            end
            rehash toolboxcache

            obj.DeviceName = deviceName;
            obj.Adaptor = opts.Adaptor;
            obj.Filename = opts.Filename;
            obj.Parent = opts.Parent;
            obj.VideoProfile = opts.VideoProfile;
            obj.PreviewFrameRate = opts.PreviewFrameRate;
            obj.AudioDeviceName = opts.AudioDeviceName;
            obj.AudioSampleRate = opts.AudioSampleRate;
            obj.AudioBitsPerSample = opts.AudioBitsPerSample;

            obj.resolveDeviceID_();

            obj.RecordingResolution = opts.RecordingResolution;
            obj.RecordingFrameRate = opts.RecordingFrameRate;

            obj.resolveFormat_();
            obj.createVideoInput_();

            obj.propListeners_ = [
                addlistener(obj, 'RecordingResolution', 'PostSet', @(~,~) obj.onSettingsChanged_())
                addlistener(obj, 'RecordingFrameRate',  'PostSet', @(~,~) obj.onSettingsChanged_())
                ];

            obj.isConstructed_ = true;

            if ~isempty(obj.Parent) && opts.ShowControls
                obj.ShowControls = true;
                obj.buildControlPanel_();
            end

            vprintf(1, 'WebcamRecorder: Initialized "%s" [%s] at %dx%d @ %.0f fps', ...
                obj.DeviceName, obj.Adaptor, ...
                obj.RecordingResolution(1), obj.RecordingResolution(2), ...
                obj.RecordingFrameRate);
        end

        function delete(obj)
            % delete Stop preview/recording and release owned resources.
            if obj.IsRecording
                obj.stopRecording();
            end
            if obj.IsPreviewing
                obj.stopPreview();
            end
            if ~isempty(obj.durationTimer_) && isvalid(obj.durationTimer_)
                stop(obj.durationTimer_)
                delete(obj.durationTimer_)
            end
            if ~isempty(obj.videoInput_) && isvalid(obj.videoInput_)
                delete(obj.videoInput_)
            end
            if ~isempty(obj.propListeners_)
                delete(obj.propListeners_)
            end
            vprintf(1, 'WebcamRecorder: Cleaned up "%s"', obj.DeviceName);
        end

        function startPreview(obj)
            % startPreview Start live preview in the configured parent container.
            if isempty(obj.Parent)
                vprintf(1, 'WebcamRecorder: No Parent set - cannot preview');
                return
            end
            if obj.IsPreviewing
                return
            end

            obj.createPreviewImage_();
            obj.lastPreviewTime_ = tic;
            setappdata(obj.previewImage_, 'WebcamRecorderObj', obj);
            obj.videoInput_.UpdatePreviewWindowFcn = @WebcamRecorder.updatePreviewFcn_;
            preview(obj.videoInput_, obj.previewImage_);
            obj.IsPreviewing = true;
            obj.syncButtonStates_();

            vprintf(1, 'WebcamRecorder: Preview started at %dx%d, throttled to %.0f fps', ...
                obj.RecordingResolution(1), obj.RecordingResolution(2), obj.PreviewFrameRate);
        end

        function stopPreview(obj)
            % stopPreview Stop the live preview stream.
            if ~obj.IsPreviewing
                return
            end
            closepreview(obj.videoInput_);
            obj.IsPreviewing = false;
            obj.syncButtonStates_();
            vprintf(1, 'WebcamRecorder: Preview stopped');
        end

        function startRecording(obj)
            % startRecording Start video logging to disk and optional audio capture.
            if obj.IsRecording
                return
            end
            if strlength(obj.Filename) == 0
                error('WebcamRecorder:NoFilename', 'Filename must be set before recording.')
            end

            [fdir, ~, ~] = fileparts(obj.Filename);
            if strlength(fdir) > 0 && ~isfolder(fdir)
                mkdir(fdir)
            end

            wasPreviewing = obj.IsPreviewing;
            if wasPreviewing
                obj.stopPreview();
            end

            obj.videoWriter_ = VideoWriter(obj.Filename, obj.VideoProfile);
            obj.videoWriter_.FrameRate = obj.RecordingFrameRate;
            open(obj.videoWriter_);

            obj.videoInput_.LoggingMode = 'disk';
            obj.videoInput_.DiskLogger = obj.videoWriter_;
            obj.videoInput_.FramesPerTrigger = Inf;

            obj.audioWasStarted_ = false;
            if strlength(obj.AudioDeviceName) > 0
                obj.startAudio_();
            end

            start(obj.videoInput_);
            obj.recordingStartTime_ = tic;
            obj.recordingStartDateTime_ = datetime('now');
            obj.IsRecording = true;
            obj.startDurationTimer_();
            obj.syncButtonStates_();
            obj.updateInfoLabel_();

            if wasPreviewing
                obj.startPreview();
            end

            vprintf(1, 'WebcamRecorder: Recording to "%s" at %dx%d @ %.0f fps (%s)', ...
                obj.Filename, obj.RecordingResolution(1), obj.RecordingResolution(2), ...
                obj.RecordingFrameRate, obj.VideoProfile);
        end

        function stopRecording(obj)
            % stopRecording Stop recording and finalize video, audio, and metadata files.
            if ~obj.IsRecording
                return
            end

            wasPreviewing = obj.IsPreviewing;
            if wasPreviewing
                obj.stopPreview();
            end

            if ~isempty(obj.videoInput_) && isvalid(obj.videoInput_) && isrunning(obj.videoInput_)
                stop(obj.videoInput_)
            end

            elapsed = toc(obj.recordingStartTime_);

            if ~isempty(obj.videoWriter_) && isopen(obj.videoWriter_)
                close(obj.videoWriter_)
            end
            obj.videoWriter_ = [];

            if obj.audioWasStarted_ && ~isempty(obj.audioRecorder_) && isrecording(obj.audioRecorder_)
                stop(obj.audioRecorder_)
                audioData = getaudiodata(obj.audioRecorder_);
                wavFile = obj.audioFilename_();
                audiowrite(wavFile, audioData, obj.AudioSampleRate)
                vprintf(1, 'WebcamRecorder: Audio saved to "%s"', wavFile);
            end
            obj.audioRecorder_ = [];

            obj.saveSyncMetadata_(elapsed);
            obj.audioWasStarted_ = false;
            obj.IsRecording = false;
            obj.stopDurationTimer_();
            obj.syncButtonStates_();
            obj.updateInfoLabel_();

            if wasPreviewing
                obj.startPreview();
            end

            vprintf(1, 'WebcamRecorder: Recording stopped (%.1f s)', elapsed);
        end

        function start(obj)
            % start Convenience method to start preview and recording.
            obj.startPreview();
            obj.startRecording();
        end

        function stop(obj)
            % stop Convenience method to stop recording and preview.
            obj.stopRecording();
            obj.stopPreview();
        end

        function mb = estimateMBPerMinute(obj)
            % estimateMBPerMinute Estimate approximate storage usage in MB per minute.
            w = obj.RecordingResolution(1);
            h = obj.RecordingResolution(2);
            fps = obj.RecordingFrameRate;
            rawBytesPerSec = w * h * 3 * fps;
            switch lower(obj.VideoProfile)
                case "mpeg-4"
                    ratio = 30;
                case "motion jpeg avi"
                    ratio = 10;
                case "motion jpeg 2000"
                    ratio = 20;
                otherwise
                    ratio = 1;
            end
            videoBytesPerMin = (rawBytesPerSec / ratio) * 60;
            audioBytesPerMin = 0;
            if strlength(obj.AudioDeviceName) > 0
                audioBytesPerMin = obj.AudioSampleRate * (obj.AudioBitsPerSample / 8) * 60;
            end
            mb = (videoBytesPerMin + audioBytesPerMin) / 1e6;
        end

        function snapshot(obj)
            % snapshot Capture one frame and save it as a PNG image.
            if isempty(obj.videoInput_) || ~isvalid(obj.videoInput_)
                vprintf(0, 1, 'WebcamRecorder: Cannot snapshot - no active videoinput');
                return
            end
            frame = getsnapshot(obj.videoInput_);
            if strlength(obj.Filename) > 0
                [fdir, fbase, ~] = fileparts(obj.Filename);
            else
                fdir = pwd;
                fbase = "snapshot";
            end
            if ~isfolder(fdir)
                mkdir(fdir)
            end
            ts = datestr(now, 'yyyymmdd_HHMMSSfff');
            snapFile = fullfile(fdir, sprintf('%s_%s.png', fbase, ts));
            imwrite(frame, snapFile)
            vprintf(1, 'WebcamRecorder: Snapshot saved to "%s"', snapFile);
        end

        function fmts = get.AvailableFormats(obj)
            % get.AvailableFormats Return supported format strings for the current device.
            info = imaqhwinfo(obj.Adaptor, obj.deviceID_);
            fmts = string(info.SupportedFormats);
        end

        function d = get.Duration(obj)
            % get.Duration Return elapsed recording time in seconds, or NaN when idle.
            if obj.IsRecording && obj.recordingStartTime_ > 0
                d = toc(obj.recordingStartTime_);
            else
                d = NaN;
            end
        end
    end

    methods
        function set.ShowControls(obj, val)
            % set.ShowControls Show or hide the optional control panel.
            if obj.ShowControls == val
                return
            end
            oldVal = obj.ShowControls;
            obj.ShowControls = val;
            obj.onShowControlsChanged_(oldVal, val);
        end

        function set.Filename(obj, val)
            % set.Filename Update the output filename and dependent UI state.
            obj.Filename = val;
            obj.syncButtonStates_();
            obj.updateInfoLabel_();
        end
    end

    methods (Static)
        function tbl = listDevices(adaptor)
            % listDevices Enumerate available devices and supported formats for an adaptor.
            arguments
                adaptor (1,1) string = "winvideo"
            end
            info = imaqhwinfo(adaptor);
            n = numel(info.DeviceIDs);
            names = strings(n, 1);
            ids = zeros(n, 1);
            fmts = cell(n, 1);
            for i = 1:n
                devInfo = imaqhwinfo(adaptor, info.DeviceIDs{i});
                names(i) = string(devInfo.DeviceName);
                ids(i) = info.DeviceIDs{i};
                fmts{i} = string(devInfo.SupportedFormats);
            end
            tbl = table(names, ids, fmts, 'VariableNames', {'Name','DeviceID','Formats'});
        end
    end

    methods (Static, Hidden)
        function updatePreviewFcn_(~, event, hImage)
            % updatePreviewFcn_ Throttle preview display updates to PreviewFrameRate.
            obj = getappdata(hImage, 'WebcamRecorderObj');
            if isempty(obj) || ~isvalid(obj)
                return
            end
            elapsed = toc(obj.lastPreviewTime_);
            if elapsed < (1 / obj.PreviewFrameRate)
                return
            end
            hImage.CData = event.Data;
            obj.lastPreviewTime_ = tic;
        end
    end

    methods (Access = private)
        function onShowControlsChanged_(obj, oldVal, newVal)
            % onShowControlsChanged_ Build or destroy controls after ShowControls changes.
            if newVal && ~oldVal && ~isempty(obj.Parent)
                obj.buildControlPanel_();
            elseif ~newVal && oldVal
                obj.destroyControlPanel_();
            end
        end

        function resolveDeviceID_(obj)
            % resolveDeviceID_ Map DeviceName to the adaptor-specific device ID.
            info = imaqhwinfo(obj.Adaptor);
            for i = 1:numel(info.DeviceIDs)
                devInfo = imaqhwinfo(obj.Adaptor, info.DeviceIDs{i});
                if strcmpi(string(devInfo.DeviceName), obj.DeviceName)
                    obj.deviceID_ = info.DeviceIDs{i};
                    return
                end
            end
            error('WebcamRecorder:DeviceNotFound', ...
                'Device "%s" not found for adaptor "%s".', obj.DeviceName, obj.Adaptor)
        end

        function resolveMaxResolution_(obj)
            % resolveMaxResolution_ Select the largest supported resolution for the device.
            fmts = obj.AvailableFormats;
            bestArea = 0;
            bestRes = [640 480];
            for i = 1:numel(fmts)
                res = WebcamRecorder.parseResolutionFromFormat_(fmts(i));
                if ~isempty(res) && prod(res) > bestArea
                    bestArea = prod(res);
                    bestRes = res;
                end
            end
            if ~isequal(obj.RecordingResolution, bestRes)
                obj.RecordingResolution = bestRes;
            end
        end

        function resolveMaxFrameRate_(obj)
            % resolveMaxFrameRate_ Reset the requested frame rate to 30 Hz.
            if obj.RecordingFrameRate ~= 30
                obj.RecordingFrameRate = 30;
            end
        end

        function resolveFormat_(obj)
            % resolveFormat_ Choose the supported format nearest the requested resolution.
            fmts = obj.AvailableFormats;
            targetW = obj.RecordingResolution(1);
            targetH = obj.RecordingResolution(2);
            bestFmt = fmts(1);
            bestDist = Inf;
            for i = 1:numel(fmts)
                res = WebcamRecorder.parseResolutionFromFormat_(fmts(i));
                if isempty(res)
                    continue
                end
                dist = abs(res(1) - targetW) + abs(res(2) - targetH);
                if dist < bestDist
                    bestDist = dist;
                    bestFmt = fmts(i);
                    if dist == 0
                        break
                    end
                end
            end
            obj.formatString_ = bestFmt;
            actualRes = WebcamRecorder.parseResolutionFromFormat_(bestFmt);
            if ~isempty(actualRes) && ~isequal(obj.RecordingResolution, actualRes)
                obj.RecordingResolution = actualRes;
            end
        end

        function createVideoInput_(obj)
            % createVideoInput_ Create and configure the VIDEOINPUT object for capture.
            if ~isempty(obj.videoInput_) && isvalid(obj.videoInput_)
                delete(obj.videoInput_)
            end

            obj.videoInput_ = videoinput(obj.Adaptor, obj.deviceID_, char(obj.formatString_));
            obj.videoInput_.FramesPerTrigger = Inf;
            obj.videoInput_.ReturnedColorspace = 'rgb';
            triggerconfig(obj.videoInput_, 'immediate');

            src = getselectedsource(obj.videoInput_);
            srcProps = set(src);
            if isfield(srcProps, 'FrameRate')
                availRates = srcProps.FrameRate;
                if iscell(availRates)
                    rates = cellfun(@str2double, availRates);
                    [~, idx] = min(abs(rates - obj.RecordingFrameRate));
                    src.FrameRate = availRates{idx};
                    if obj.RecordingFrameRate ~= rates(idx)
                        obj.RecordingFrameRate = rates(idx);
                    end
                else
                    src.FrameRate = num2str(obj.RecordingFrameRate);
                end
            end

            vprintf(2, 'WebcamRecorder: videoinput created [%s] fmt="%s"', ...
                obj.Adaptor, obj.formatString_);
        end

        function onSettingsChanged_(obj)
            % onSettingsChanged_ Recreate video input after resolution or frame-rate changes.
            if ~obj.isConstructed_ || obj.suppressSettingsCallback_
                return
            end
            if obj.IsRecording
                error('WebcamRecorder:CannotChangeWhileRecording', ...
                    'Cannot change resolution or frame rate while recording.')
            end

            obj.suppressSettingsCallback_ = true;
            cleanupObj = onCleanup(@() obj.clearSettingsSuppress_());

            wasPreviewing = obj.IsPreviewing;
            if wasPreviewing
                obj.stopPreview();
            end
            if ~isempty(obj.previewAxes_) && isvalid(obj.previewAxes_)
                delete(obj.previewAxes_)
                obj.previewAxes_ = [];
                obj.previewImage_ = [];
            end
            obj.resolveFormat_();
            obj.createVideoInput_();
            if wasPreviewing
                obj.startPreview();
            end
            obj.updateInfoLabel_();

            clear cleanupObj
        end

        function clearSettingsSuppress_(obj)
            % clearSettingsSuppress_ Re-enable settings change callbacks.
            obj.suppressSettingsCallback_ = false;
        end

        function createPreviewImage_(obj)
            % createPreviewImage_ Create hidden preview axes and image target.
            if ~isempty(obj.previewAxes_) && isvalid(obj.previewAxes_)
                return
            end
            if ~isempty(obj.rootLayout_) && isvalid(obj.rootLayout_)
                axParent = obj.rootLayout_;
            else
                axParent = obj.Parent;
            end
            obj.previewAxes_ = uiaxes(axParent);
            obj.previewAxes_.Toolbar.Visible = 'off';
            disableDefaultInteractivity(obj.previewAxes_)
            obj.previewAxes_.Visible = 'off';
            if ~isempty(obj.rootLayout_) && isvalid(obj.rootLayout_)
                obj.previewAxes_.Layout.Row = 1;
                obj.previewAxes_.Layout.Column = 1;
            end
            w = obj.RecordingResolution(1);
            h = obj.RecordingResolution(2);
            obj.previewImage_ = image(obj.previewAxes_, zeros(h, w, 3, 'uint8'));
            axis(obj.previewAxes_, 'image')
            obj.previewAxes_.XTick = [];
            obj.previewAxes_.YTick = [];
        end

        function startAudio_(obj)
            % startAudio_ Start mono audio capture from the selected audio input device.
            audioDevs = audiodevinfo;
            devID = -1;
            for i = 0:audioDevs.NInputs-1
                name = audiodevinfo(1, i);
                if contains(string(name), obj.AudioDeviceName, 'IgnoreCase', true)
                    devID = i;
                    break
                end
            end
            if devID < 0
                vprintf(0, 1, 'WebcamRecorder: Audio device "%s" not found - skipping audio', ...
                    obj.AudioDeviceName)
                return
            end
            obj.audioRecorder_ = audiorecorder(obj.AudioSampleRate, ...
                obj.AudioBitsPerSample, 1, devID);
            record(obj.audioRecorder_)
            obj.audioWasStarted_ = true;
            vprintf(1, 'WebcamRecorder: Audio capture started (%d Hz, %d-bit)', ...
                obj.AudioSampleRate, obj.AudioBitsPerSample);
        end

        function fn = audioFilename_(obj)
            % audioFilename_ Derive the WAV filename that accompanies the video file.
            [fdir, fbase, ~] = fileparts(obj.Filename);
            fn = fullfile(fdir, fbase + ".wav");
        end

        function saveSyncMetadata_(obj, elapsed)
            % saveSyncMetadata_ Save recording timing and configuration metadata to MAT.
            if strlength(obj.Filename) == 0
                return
            end
            [fdir, fbase, ~] = fileparts(obj.Filename);
            metaFile = fullfile(fdir, fbase + "_sync.mat");
            syncInfo.videoFile = obj.Filename;
            if obj.audioWasStarted_
                syncInfo.audioFile = obj.audioFilename_();
            else
                syncInfo.audioFile = "";
            end
            syncInfo.recordingStartDateTime = obj.recordingStartDateTime_;
            syncInfo.recordingStopDateTime = datetime('now');
            syncInfo.durationSeconds = elapsed;
            syncInfo.recordingResolution = obj.RecordingResolution;
            syncInfo.recordingFrameRate = obj.RecordingFrameRate;
            syncInfo.videoProfile = obj.VideoProfile;
            syncInfo.audioSampleRate = obj.AudioSampleRate;
            syncInfo.audioBitsPerSample = obj.AudioBitsPerSample;
            syncInfo.hasAudio = obj.audioWasStarted_;
            save(metaFile, 'syncInfo')
            vprintf(2, 'WebcamRecorder: Sync metadata saved to "%s"', metaFile);
        end

        function buildControlPanel_(obj)
            % buildControlPanel_ Create the recorder UI controls inside Parent.
            if isempty(obj.Parent)
                return
            end
            wasPreviewing = obj.IsPreviewing;
            if wasPreviewing
                obj.stopPreview();
            end
            obj.destroyControlPanel_();

            obj.rootLayout_ = uigridlayout(obj.Parent, [2 1], ...
                'RowHeight', {"1x", 80}, ...
                'Padding', [0 0 0 0], ...
                'RowSpacing', 4);
            obj.controlPanel_ = uigridlayout(obj.rootLayout_, [1 5], ...
                'ColumnWidth', {80, 80, 80, 180, "1x"}, ...
                'Padding', [6 4 6 4], ...
                'ColumnSpacing', 6);
            obj.controlPanel_.Layout.Row = 2;
            obj.controlPanel_.Layout.Column = 1;

            obj.btnRecord_ = uibutton(obj.controlPanel_, 'state', ...
                'Text', 'Record', ...
                'ValueChangedFcn', @(src, evt) obj.onRecordButton_(src, evt));
            obj.btnRecord_.Layout.Column = 1;

            obj.btnPreview_ = uibutton(obj.controlPanel_, 'state', ...
                'Text', 'Preview', ...
                'ValueChangedFcn', @(src, evt) obj.onPreviewButton_(src, evt));
            obj.btnPreview_.Layout.Column = 2;

            obj.btnSnapshot_ = uibutton(obj.controlPanel_, 'push', ...
                'Text', 'Snapshot', ...
                'ButtonPushedFcn', @(src, evt) obj.onSnapshotButton_(src, evt));
            obj.btnSnapshot_.Layout.Column = 3;

            ddGrid = uigridlayout(obj.controlPanel_, [2 1], ...
                'RowHeight', {'1x', '1x'}, ...
                'Padding', [0 0 0 0], ...
                'RowSpacing', 2);
            ddGrid.Layout.Column = 4;

            devItems = {char(obj.DeviceName)};
            try
                tbl = peripherals.WebcamRecorder.listDevices(obj.Adaptor);
                devItems = cellstr(tbl.Name);
            end
            obj.ddDevice_ = uidropdown(ddGrid, ...
                'Items', devItems, ...
                'Value', char(obj.DeviceName), ...
                'ValueChangedFcn', @(src, evt) obj.onDeviceDropdown_(src, evt));
            obj.ddDevice_.Layout.Row = 1;

            fmtItems = {char(obj.formatString_)};
            try
                fmtItems = cellstr(obj.AvailableFormats);
            end
            obj.ddFormat_ = uidropdown(ddGrid, ...
                'Items', fmtItems, ...
                'Value', char(obj.formatString_), ...
                'ValueChangedFcn', @(src, evt) obj.onFormatDropdown_(src, evt));
            obj.ddFormat_.Layout.Row = 2;

            obj.lblInfo_ = uilabel(obj.controlPanel_, ...
                'Text', '', ...
                'WordWrap', 'on', ...
                'VerticalAlignment', 'top', ...
                'FontSize', 11);
            obj.lblInfo_.Layout.Column = 5;

            obj.syncButtonStates_();
            obj.updateInfoLabel_();

            if wasPreviewing
                obj.startPreview();
            end
        end

        function destroyControlPanel_(obj)
            % destroyControlPanel_ Delete the recorder UI controls and preview widgets.
            wasPreviewing = obj.IsPreviewing;
            if wasPreviewing
                obj.stopPreview();
            end
            if ~isempty(obj.rootLayout_) && isvalid(obj.rootLayout_)
                delete(obj.rootLayout_)
            end
            obj.rootLayout_ = [];
            obj.controlPanel_ = [];
            obj.btnRecord_ = [];
            obj.btnPreview_ = [];
            obj.btnSnapshot_ = [];
            obj.ddDevice_ = [];
            obj.ddFormat_ = [];
            obj.lblInfo_ = [];
            obj.previewAxes_ = [];
            obj.previewImage_ = [];
            if wasPreviewing
                obj.startPreview();
            end
        end

        function updateInfoLabel_(obj)
            % updateInfoLabel_ Refresh the summary text shown in the control panel.
            if isempty(obj.lblInfo_) || ~isvalid(obj.lblInfo_)
                return
            end
            w = obj.RecordingResolution(1);
            h = obj.RecordingResolution(2);
            fps = obj.RecordingFrameRate;
            mb = obj.estimateMBPerMinute();
            lines = strings(0, 1);
            lines(end+1) = sprintf('%dx%d @ %.0f fps', w, h, fps);
            lines(end+1) = sprintf('~%.1f MB/min (%s)', mb, obj.VideoProfile);
            if obj.IsRecording
                elapsed = toc(obj.recordingStartTime_);
                mins = floor(elapsed / 60);
                secs = floor(mod(elapsed, 60));
                lines(end+1) = sprintf('Recording: %02d:%02d', mins, secs);
            else
                lines(end+1) = "Idle";
            end
            if strlength(obj.Filename) > 0
                fn = obj.Filename;
                if strlength(fn) > 40
                    fn = "..." + extractAfter(fn, strlength(fn) - 37);
                end
                lines(end+1) = fn;
            end
            obj.lblInfo_.Text = join(lines, newline);
        end

        function onRecordButton_(obj, src, ~)
            % onRecordButton_ Dispatch record button state changes to start/stop recording.
            if src.Value
                try
                    obj.startRecording();
                catch ME
                    src.Value = false;
                    vprintf(0, 1, ME)
                end
            else
                obj.stopRecording();
            end
        end

        function onPreviewButton_(obj, src, ~)
            % onPreviewButton_ Dispatch preview button state changes to start/stop preview.
            if src.Value
                obj.startPreview();
            else
                obj.stopPreview();
            end
        end

        function onSnapshotButton_(obj, ~, ~)
            % onSnapshotButton_ Handle the snapshot button press.
            obj.snapshot();
        end

        function onDeviceDropdown_(obj, src, ~)
            % onDeviceDropdown_ Switch to a different capture device from the UI.
            if obj.IsRecording
                src.Value = char(obj.DeviceName);
                return
            end

            wasPreviewing = obj.IsPreviewing;
            if wasPreviewing
                obj.stopPreview();
            end
            if ~isempty(obj.previewAxes_) && isvalid(obj.previewAxes_)
                delete(obj.previewAxes_)
                obj.previewAxes_ = [];
                obj.previewImage_ = [];
            end

            obj.suppressSettingsCallback_ = true;
            cleanupObj = onCleanup(@() obj.clearSettingsSuppress_());

            obj.DeviceName = string(src.Value);
            obj.resolveDeviceID_();
            obj.resolveMaxResolution_();
            obj.resolveFormat_();
            obj.createVideoInput_();

            clear cleanupObj

            if ~isempty(obj.ddFormat_) && isvalid(obj.ddFormat_)
                obj.ddFormat_.Items = cellstr(obj.AvailableFormats);
                obj.ddFormat_.Value = char(obj.formatString_);
            end
            if wasPreviewing
                obj.startPreview();
            end
            obj.updateInfoLabel_();
            vprintf(1, 'WebcamRecorder: Switched to device "%s"', obj.DeviceName);
        end

        function onFormatDropdown_(obj, src, ~)
            % onFormatDropdown_ Switch capture format from the UI.
            if obj.IsRecording
                src.Value = char(obj.formatString_);
                return
            end

            wasPreviewing = obj.IsPreviewing;
            if wasPreviewing
                obj.stopPreview();
            end
            if ~isempty(obj.previewAxes_) && isvalid(obj.previewAxes_)
                delete(obj.previewAxes_)
                obj.previewAxes_ = [];
                obj.previewImage_ = [];
            end

            obj.suppressSettingsCallback_ = true;
            cleanupObj = onCleanup(@() obj.clearSettingsSuppress_());

            obj.formatString_ = string(src.Value);
            res = WebcamRecorder.parseResolutionFromFormat_(obj.formatString_);
            if ~isempty(res) && ~isequal(obj.RecordingResolution, res)
                obj.RecordingResolution = res;
            end
            obj.createVideoInput_();

            clear cleanupObj

            if wasPreviewing
                obj.startPreview();
            end
            obj.updateInfoLabel_();
        end

        function syncButtonStates_(obj)
            % syncButtonStates_ Synchronize control enable/state values with recorder state.
            if isempty(obj.btnRecord_) || ~isvalid(obj.btnRecord_)
                return
            end

            obj.btnRecord_.Value = obj.IsRecording;
            if obj.IsRecording
                obj.btnRecord_.BackgroundColor = [0.9 0.2 0.2];
                obj.btnRecord_.FontColor = [1 1 1];
            else
                obj.btnRecord_.BackgroundColor = [0.96 0.96 0.96];
                obj.btnRecord_.FontColor = [0 0 0];
            end
            obj.btnRecord_.Enable = strlength(obj.Filename) > 0;

            if ~isempty(obj.btnPreview_) && isvalid(obj.btnPreview_)
                obj.btnPreview_.Value = obj.IsPreviewing;
                if obj.IsPreviewing
                    obj.btnPreview_.BackgroundColor = [0.2 0.7 0.3];
                    obj.btnPreview_.FontColor = [1 1 1];
                else
                    obj.btnPreview_.BackgroundColor = [0.96 0.96 0.96];
                    obj.btnPreview_.FontColor = [0 0 0];
                end
            end

            hasVid = ~isempty(obj.videoInput_) && isvalid(obj.videoInput_);
            if ~isempty(obj.btnSnapshot_) && isvalid(obj.btnSnapshot_)
                obj.btnSnapshot_.Enable = hasVid;
            end
            if ~isempty(obj.ddDevice_) && isvalid(obj.ddDevice_)
                obj.ddDevice_.Enable = ~obj.IsRecording;
            end
            if ~isempty(obj.ddFormat_) && isvalid(obj.ddFormat_)
                obj.ddFormat_.Enable = ~obj.IsRecording;
            end
        end

        function startDurationTimer_(obj)
            % startDurationTimer_ Start the 1 Hz timer used to refresh elapsed time.
            obj.stopDurationTimer_();
            obj.durationTimer_ = timer( ...
                'ExecutionMode', 'fixedRate', ...
                'Period', 1, ...
                'TimerFcn', @(~,~) obj.updateInfoLabel_());
            start(obj.durationTimer_)
        end

        function stopDurationTimer_(obj)
            % stopDurationTimer_ Stop and delete the elapsed-time refresh timer.
            if ~isempty(obj.durationTimer_) && isvalid(obj.durationTimer_)
                stop(obj.durationTimer_)
                delete(obj.durationTimer_)
            end
            obj.durationTimer_ = [];
        end
    end

    methods (Static, Access = private)
        function res = parseResolutionFromFormat_(fmt)
            % parseResolutionFromFormat_ Extract [W H] from a device format string.
            tokens = regexp(char(fmt), '(\d{3,5})\s*x\s*(\d{3,5})', 'tokens');
            if isempty(tokens)
                res = [];
            else
                res = [str2double(tokens{1}{1}), str2double(tokens{1}{2})];
            end
        end
    end
end
