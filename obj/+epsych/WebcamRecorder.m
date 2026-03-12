classdef WebcamRecorder < handle
    % WebcamRecorder   Minimal standalone camera and audio recorder
    %
    %   RECORDER = epsych.WebcamRecorder(...) creates a small handle class
    %   for programmatic camera recording using Image Acquisition Toolbox.
    %   Video frames are acquired from a videoinput object on a recorder-
    %   owned timer, audio is captured through audiorecorder, and outputs
    %   are written as separate video, audio, and metadata files.
    %
    %   Example:
    %       recorder = epsych.WebcamRecorder(TargetFrameRate = 10);
    %       recorder.start();
    %       pause(5);
    %       recorder.stop();
    %       disp(recorder.artifacts())

    properties
        Adaptor (1,:) char = ''
        DeviceID (1,1) double {mustBePositive,mustBeInteger} = 1
        VideoFormat (1,:) char = ''
        TargetFrameRate (1,1) double {mustBePositive} = 10
        OutputDir (1,1) string = string(pwd)
        BaseName (1,:) char = 'webcam_recording'
        RecordAudio (1,1) logical = true
        AudioSampleRate (1,1) double {mustBePositive,mustBeInteger} = 44100
        AudioBitsPerSample (1,1) double {mustBeMember(AudioBitsPerSample,[8 16 24])} = 16
        AudioNumChannels (1,1) double {mustBeMember(AudioNumChannels,[1 2])} = 1
        AudioDeviceID = []
        VideoProfile (1,:) char = 'Motion JPEG AVI'
    end

    properties (SetAccess = protected)
        VideoFile (1,1) string = ""
        AudioFile (1,1) string = ""
        MetadataFile (1,1) string = ""
        RecordingStem (1,1) string = ""
        StartTime datetime = NaT
        StopTime datetime = NaT
        IsRecording (1,1) logical = false
        DeviceInfo struct = struct
        AudioInfo struct = struct
        LastError (1,1) string = ""
        FrameElapsedSeconds (1,:) double = []
        FrameWallClock datetime = datetime.empty(1,0)
        FrameCount (1,1) double {mustBeNonnegative,mustBeInteger} = 0
        FailedFrameCount (1,1) double {mustBeNonnegative,mustBeInteger} = 0
    end

    properties (SetAccess = private, Hidden)
        VideoInput
        CaptureTimer (1,1) timer
        Writer
        AudioRecorder
        RecordingTic
    end

    methods
        function obj = WebcamRecorder(options)
            arguments
                options.Adaptor (1,:) char = ''
                options.DeviceID (1,1) double {mustBePositive,mustBeInteger} = 1
                options.VideoFormat (1,:) char = ''
                options.TargetFrameRate (1,1) double {mustBePositive} = 10
                options.OutputDir = pwd
                options.BaseName (1,:) char = 'webcam_recording'
                options.RecordAudio (1,1) logical = true
                options.AudioSampleRate (1,1) double {mustBePositive,mustBeInteger} = 44100
                options.AudioBitsPerSample (1,1) double {mustBeMember(options.AudioBitsPerSample,[8 16 24])} = 16
                options.AudioNumChannels (1,1) double {mustBeMember(options.AudioNumChannels,[1 2])} = 1
                options.AudioDeviceID = []
                options.VideoProfile (1,:) char = 'Motion JPEG AVI'
            end

            obj.Adaptor = options.Adaptor;
            obj.DeviceID = options.DeviceID;
            obj.VideoFormat = options.VideoFormat;
            obj.TargetFrameRate = options.TargetFrameRate;
            obj.OutputDir = string(options.OutputDir);
            obj.BaseName = options.BaseName;
            obj.RecordAudio = options.RecordAudio;
            obj.AudioSampleRate = options.AudioSampleRate;
            obj.AudioBitsPerSample = options.AudioBitsPerSample;
            obj.AudioNumChannels = options.AudioNumChannels;
            obj.AudioDeviceID = options.AudioDeviceID;
            obj.VideoProfile = options.VideoProfile;

            obj.configure_video_input();
            obj.create_capture_timer();
        end

        function delete(obj)
            try
                obj.stop();
            catch me
                obj.LastError = string(me.message);
            end

            try
                if ~isempty(obj.CaptureTimer) && isvalid(obj.CaptureTimer)
                    stop(obj.CaptureTimer);
                    delete(obj.CaptureTimer);
                end
            catch
            end

            try
                if ~isempty(obj.VideoInput) && isvalid(obj.VideoInput)
                    delete(obj.VideoInput);
                end
            catch
            end

            try
                if ~isempty(obj.AudioRecorder)
                    stop(obj.AudioRecorder);
                end
            catch
            end
        end

        function start(obj)
            if obj.IsRecording
                return
            end

            obj.ensure_output_directory();
            obj.reset_recording_state();
            obj.initialize_output_paths();
            obj.open_writer();
            obj.prepare_audio_recorder();

            try
                flushdata(obj.VideoInput);
                start(obj.VideoInput);
                obj.StartTime = datetime('now');
                obj.RecordingTic = tic;

                if obj.RecordAudio && ~isempty(obj.AudioRecorder)
                    record(obj.AudioRecorder);
                end

                obj.capture_frame();
                start(obj.CaptureTimer);
                obj.IsRecording = true;
                vprintf(2,'WebcamRecorder started: %s',char(obj.VideoFile))
            catch me
                obj.LastError = string(me.message);
                obj.cleanup_active_resources();
                rethrow(me)
            end
        end

        function stop(obj)
            if ~obj.IsRecording && (isnat(obj.StartTime) || ~isnat(obj.StopTime))
                return
            end

            if ~isempty(obj.CaptureTimer) && isvalid(obj.CaptureTimer)
                stop(obj.CaptureTimer);
            end

            if obj.RecordAudio && ~isempty(obj.AudioRecorder)
                try
                    stop(obj.AudioRecorder);
                catch me
                    obj.LastError = string(me.message);
                end
            end

            if ~isempty(obj.VideoInput) && isvalid(obj.VideoInput)
                try
                    if isprop(obj.VideoInput,'Running') && strcmpi(obj.VideoInput.Running,'on')
                        stop(obj.VideoInput);
                    end
                catch me
                    obj.LastError = string(me.message);
                end
            end

            obj.StopTime = datetime('now');

            obj.finalize_audio_file();
            obj.close_writer();
            obj.write_metadata_file();
            obj.cleanup_active_resources();

            obj.IsRecording = false;
            vprintf(2,'WebcamRecorder stopped: %s',char(obj.MetadataFile))
        end

        function tf = isRecording(obj)
            tf = obj.IsRecording;
        end

        function out = artifacts(obj)
            out = struct(...
                'videoFile', obj.VideoFile, ...
                'audioFile', obj.AudioFile, ...
                'metadataFile', obj.MetadataFile);
        end

        function metadata = get_metadata(obj)
            metadata = obj.build_metadata();
        end
    end

    methods (Access = protected)
        function configure_video_input(obj)
            info = epsych.WebcamRecorder.image_acquisition_info();
            adaptors = string(info.InstalledAdaptors);
            if isempty(adaptors)
                error('EPsych:WebcamRecorder:NoAdaptors', ...
                    'Image Acquisition Toolbox is installed but no camera adaptors were found.')
            end

            if isempty(obj.Adaptor)
                obj.Adaptor = char(adaptors(1));
            elseif ~ismember(string(obj.Adaptor), adaptors)
                error('EPsych:WebcamRecorder:InvalidAdaptor', ...
                    'Adaptor "%s" is not installed. Available adaptors: %s', ...
                    obj.Adaptor, strjoin(cellstr(adaptors), ', '))
            end

            adaptorInfo = imaqhwinfo(obj.Adaptor);
            if isempty(adaptorInfo.DeviceInfo)
                error('EPsych:WebcamRecorder:NoDevices', ...
                    'Adaptor "%s" has no available devices.', obj.Adaptor)
            end

            deviceInfo = obj.lookup_device_info(adaptorInfo.DeviceInfo, obj.DeviceID);
            obj.DeviceID = obj.normalize_device_id(deviceInfo.DeviceID);
            obj.DeviceInfo = deviceInfo;

            if isempty(obj.VideoFormat)
                obj.VideoFormat = char(string(deviceInfo.SupportedFormats{1}));
            elseif ~ismember(obj.VideoFormat, deviceInfo.SupportedFormats)
                error('EPsych:WebcamRecorder:InvalidFormat', ...
                    'Format "%s" is not supported by device %d.', obj.VideoFormat, obj.DeviceID)
            end

            obj.VideoInput = videoinput(obj.Adaptor, obj.DeviceID, obj.VideoFormat);
            obj.VideoInput.ReturnedColorSpace = 'rgb';
            if isprop(obj.VideoInput,'Timeout')
                obj.VideoInput.Timeout = max(5, 5 / obj.TargetFrameRate);
            end
        end

        function create_capture_timer(obj)
            period = max(1 / obj.TargetFrameRate, 0.02);
            obj.CaptureTimer = timer( ...
                'Name', 'epsych_WebcamRecorder', ...
                'ExecutionMode', 'fixedRate', ...
                'BusyMode', 'drop', ...
                'TasksToExecute', inf, ...
                'Period', period, ...
                'TimerFcn', @obj.capture_frame, ...
                'ErrorFcn', @obj.capture_error);
        end

        function prepare_audio_recorder(obj)
            obj.AudioFile = "";
            obj.AudioRecorder = [];
            obj.AudioInfo = struct;

            if ~obj.RecordAudio
                return
            end

            try
                if isempty(obj.AudioDeviceID)
                    obj.AudioRecorder = audiorecorder( ...
                        obj.AudioSampleRate, ...
                        obj.AudioBitsPerSample, ...
                        obj.AudioNumChannels);
                else
                    obj.AudioRecorder = audiorecorder( ...
                        obj.AudioSampleRate, ...
                        obj.AudioBitsPerSample, ...
                        obj.AudioNumChannels, ...
                        obj.AudioDeviceID);
                end

                obj.AudioFile = obj.OutputDir + filesep + obj.RecordingStem + ".wav";
                obj.AudioInfo = struct(...
                    'sampleRate', obj.AudioSampleRate, ...
                    'bitsPerSample', obj.AudioBitsPerSample, ...
                    'numChannels', obj.AudioNumChannels, ...
                    'deviceID', obj.AudioDeviceID);
            catch me
                obj.AudioRecorder = [];
                obj.AudioFile = "";
                obj.AudioInfo = struct('error', me.message);
                vprintf(0,'WebcamRecorder audio disabled: %s',me.message)
            end
        end

        function initialize_output_paths(obj)
            obj.RecordingStem = obj.recording_stem();
            stem = obj.RecordingStem;
            obj.VideoFile = obj.OutputDir + filesep + stem + ".avi";
            obj.MetadataFile = obj.OutputDir + filesep + stem + "_metadata.mat";
            if ~obj.RecordAudio
                obj.AudioFile = "";
            end
        end

        function open_writer(obj)
            obj.Writer = VideoWriter(char(obj.VideoFile), obj.VideoProfile);
            obj.Writer.FrameRate = obj.TargetFrameRate;
            open(obj.Writer);
        end

        function capture_frame(obj, varargin)
            if isempty(obj.VideoInput) || isempty(obj.Writer)
                return
            end

            try
                frame = getsnapshot(obj.VideoInput);
                writeVideo(obj.Writer, frame);
                obj.FrameCount = obj.FrameCount + 1;
                obj.FrameElapsedSeconds(end+1) = toc(obj.RecordingTic); %#ok<AGROW>
                obj.FrameWallClock(end+1) = datetime('now'); %#ok<AGROW>
            catch me
                obj.FailedFrameCount = obj.FailedFrameCount + 1;
                obj.LastError = string(me.message);
            end
        end

        function capture_error(obj, varargin)
            if ~isempty(varargin) && numel(varargin) >= 2
                event = varargin{2};
                if isprop(event,'Data')
                    obj.LastError = string(event.Data.Message);
                end
            end
        end

        function finalize_audio_file(obj)
            if isempty(obj.AudioRecorder) || strlength(obj.AudioFile) == 0
                return
            end

            try
                audioData = getaudiodata(obj.AudioRecorder,'double');
                if ~isempty(audioData)
                    audiowrite(char(obj.AudioFile), audioData, obj.AudioSampleRate);
                end
            catch me
                obj.LastError = string(me.message);
            end
        end

        function close_writer(obj)
            if isempty(obj.Writer)
                return
            end

            try
                close(obj.Writer);
            catch me
                obj.LastError = string(me.message);
            end

            obj.Writer = [];
        end

        function write_metadata_file(obj)
            if strlength(obj.MetadataFile) == 0
                return
            end

            metadata = obj.build_metadata(); %#ok<NASGU>
            save(char(obj.MetadataFile), 'metadata');
        end

        function metadata = build_metadata(obj)
            metadata = struct(...
                'startTime', obj.StartTime, ...
                'stopTime', obj.StopTime, ...
                'elapsedSeconds', obj.elapsed_seconds(), ...
                'adaptor', string(obj.Adaptor), ...
                'deviceID', obj.DeviceID, ...
                'videoFormat', string(obj.VideoFormat), ...
                'targetFrameRate', obj.TargetFrameRate, ...
                'frameCount', obj.FrameCount, ...
                'failedFrameCount', obj.FailedFrameCount, ...
                'frameElapsedSeconds', obj.FrameElapsedSeconds, ...
                'frameWallClock', obj.FrameWallClock, ...
                'videoFile', obj.VideoFile, ...
                'audioFile', obj.AudioFile, ...
                'metadataFile', obj.MetadataFile, ...
                'deviceInfo', obj.DeviceInfo, ...
                'audioInfo', obj.AudioInfo, ...
                'lastError', obj.LastError);
        end

        function elapsedValue = elapsed_seconds(obj)
            if isnat(obj.StartTime)
                elapsedValue = 0;
            elseif isnat(obj.StopTime)
                elapsedValue = toc(obj.RecordingTic);
            else
                elapsedValue = seconds(obj.StopTime - obj.StartTime);
            end
        end

        function cleanup_active_resources(obj)
            if ~isempty(obj.CaptureTimer) && isvalid(obj.CaptureTimer)
                try
                    stop(obj.CaptureTimer);
                catch
                end
            end

            if ~isempty(obj.VideoInput) && isvalid(obj.VideoInput)
                try
                    if isprop(obj.VideoInput,'Running') && strcmpi(obj.VideoInput.Running,'on')
                        stop(obj.VideoInput);
                    end
                catch
                end
            end

            if ~isempty(obj.AudioRecorder)
                try
                    stop(obj.AudioRecorder);
                catch
                end
            end
        end

        function reset_recording_state(obj)
            obj.FrameElapsedSeconds = [];
            obj.FrameWallClock = datetime.empty(1,0);
            obj.FrameCount = 0;
            obj.FailedFrameCount = 0;
            obj.RecordingStem = "";
            obj.StartTime = NaT;
            obj.StopTime = NaT;
            obj.LastError = "";
        end

        function ensure_output_directory(obj)
            if ~isfolder(obj.OutputDir)
                mkdir(obj.OutputDir);
            end
        end

        function stem = recording_stem(obj)
            timestamp = string(datetime('now','Format','yyyyMMdd_HHmmss'));
            stem = string(obj.BaseName) + "_" + timestamp;
        end

        function deviceInfo = lookup_device_info(obj, deviceInfoList, deviceID)
            if nargin < 3 || isempty(deviceID)
                deviceInfo = deviceInfoList(1);
                return
            end

            tf = arrayfun(@(item) obj.normalize_device_id(item.DeviceID) == deviceID, deviceInfoList);
            if ~any(tf)
                available = arrayfun(@(item) obj.normalize_device_id(item.DeviceID), deviceInfoList);
                error('EPsych:WebcamRecorder:InvalidDeviceID', ...
                    'Device %d was not found for adaptor "%s". Available devices: %s', ...
                    deviceID, obj.Adaptor, num2str(available))
            end

            deviceInfo = deviceInfoList(find(tf, 1, 'first'));
        end
    end

    methods (Static)
        function info = image_acquisition_info()
            if exist('imaqhwinfo','file') ~= 2
                error('EPsych:WebcamRecorder:MissingIMAQ', ...
                    'Image Acquisition Toolbox is required for epsych.WebcamRecorder.')
            end

            info = imaqhwinfo;
        end

        function devices = list_video_devices(adaptor)
            arguments
                adaptor (1,:) char = ''
            end

            info = epsych.WebcamRecorder.image_acquisition_info();
            adaptors = string(info.InstalledAdaptors);
            if isempty(adaptors)
                devices = struct([]);
                return
            end

            if isempty(adaptor)
                adaptor = char(adaptors(1));
            end

            adaptorInfo = imaqhwinfo(adaptor);
            devices = adaptorInfo.DeviceInfo;
        end

        function deviceID = normalize_device_id(rawID)
            if iscell(rawID)
                rawID = rawID{1};
            end
            deviceID = double(rawID);
        end
    end
end