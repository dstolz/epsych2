classdef VlcRecorderGroup < handle
    %VLCRECORDERGROUP Coordinate multiple VLC webcam recorder instances.
    %
    % When a camera config provides RecordingFile and/or StreamPort, VLC
    % begins writing those outputs as soon as the webcam launch succeeds.
    %
    % Example:
    %   webcams = VlcRecorder.listWebcams();
    %   configs(1) = struct( ...
    %       'Name', "Front", ...
    %       'WebcamName', webcams(1), ...
    %       'RecordingFile', fullfile(tempdir, 'front.ts'), ...
    %       'StreamPort', 8080);
    %   configs(2) = struct( ...
    %       'Name', "Side", ...
    %       'WebcamName', webcams(2), ...
    %       'RecordingFile', fullfile(tempdir, 'side.ts'), ...
    %       'StreamPort', 8081);
    %   group = VlcRecorderGroup(configs);
    %   group.launchWebcams();
    %   group.connect();
    %   pause(10)
    %   group.quit();

    properties
        Host (1,1) string = "127.0.0.1"
        BasePort (1,1) double = 4212
        VlcPath (1,1) string = "C:\Program Files\VideoLAN\VLC\vlc.exe"
        Timeout (1,1) double = 5
    end

    properties (SetAccess = private)
        Cameras (1,:) struct = struct([])
        StreamUrls string = strings(0, 1)
    end

    properties (Access = private)
        Recorders (1,:) cell = cell(1, 0)
    end

    methods
        function obj = VlcRecorderGroup(cameraConfigs, varargin)
            if nargin < 1
                cameraConfigs = struct([]);
            end

            parser = inputParser;
            parser.FunctionName = 'VlcRecorderGroup';
            addParameter(parser, 'Host', obj.Host, @(x) ischar(x) || isstring(x));
            addParameter(parser, 'BasePort', obj.BasePort, @(x) isscalar(x) && isnumeric(x) && isfinite(x) && x > 0);
            addParameter(parser, 'VlcPath', obj.VlcPath, @(x) ischar(x) || isstring(x));
            addParameter(parser, 'Timeout', obj.Timeout, @(x) isscalar(x) && isnumeric(x) && isfinite(x) && x > 0);
            parse(parser, varargin{:});

            obj.Host = string(parser.Results.Host);
            obj.BasePort = round(parser.Results.BasePort);
            obj.VlcPath = string(parser.Results.VlcPath);
            obj.Timeout = parser.Results.Timeout;

            normalizedConfigs = obj.normalizeCameraConfigs(cameraConfigs);
            normalizedConfigs = obj.applyCameraDefaults(normalizedConfigs);
            obj.validateCameraConfigs(normalizedConfigs);
            obj.Cameras = normalizedConfigs;
            obj.StreamUrls = strings(numel(normalizedConfigs), 1);
        end

        function streamUrls = launchWebcams(obj)
            obj.requireConfiguredCameras();

            if ~isempty(obj.Recorders)
                error('VlcRecorderGroup:AlreadyLaunched', ...
                    'This VlcRecorderGroup already has active recorder instances. Call quit() before relaunching.');
            end

            recorderCount = numel(obj.Cameras);
            recorders = cell(1, recorderCount);
            streamUrls = strings(recorderCount, 1);
            launchedCount = 0;

            try
                for idx = 1:recorderCount
                    cameraConfig = obj.Cameras(idx);
                    recorder = VlcRecorder(cameraConfig.VlcPath, cameraConfig.Host, cameraConfig.Port);
                    recorder.timeout = cameraConfig.Timeout;
                    optionPairs = obj.cameraOptionPairs(cameraConfig);

                    streamUrls(idx) = recorder.launchWebcam( ...
                        cameraConfig.WebcamName, optionPairs{:});

                    recorders{idx} = recorder;
                    launchedCount = idx;
                end
            catch me
                obj.shutdownRecorders(recorders(1:launchedCount));
                rethrow(me)
            end

            obj.Recorders = recorders;
            obj.StreamUrls = streamUrls;
        end

        function connect(obj)
            obj.requireRecorders();
            connectedCount = 0;

            try
                for idx = 1:numel(obj.Recorders)
                    obj.Recorders{idx}.connect();
                    connectedCount = idx;
                end
            catch me
                obj.disconnectRecorders(obj.Recorders(1:connectedCount));
                rethrow(me)
            end
        end

        function disconnect(obj)
            obj.disconnectRecorders(obj.Recorders);
        end

        function startRecording(obj)
            obj.requireRecorders();
            startedCount = 0;

            try
                for idx = 1:numel(obj.Recorders)
                    obj.Recorders{idx}.startRecording();
                    startedCount = idx;
                end
            catch me
                obj.stopRecorders(obj.Recorders(1:startedCount));
                rethrow(me)
            end
        end

        function stopRecording(obj)
            obj.stopRecorders(obj.Recorders);
        end

        function tf = recording(obj)
            tf = false(numel(obj.Recorders), 1);
            for idx = 1:numel(obj.Recorders)
                tf(idx) = obj.Recorders{idx}.recording();
            end
        end

        function out = status(obj)
            obj.requireRecorders();
            out = strings(numel(obj.Recorders), 1);
            for idx = 1:numel(obj.Recorders)
                out(idx) = obj.Recorders{idx}.status();
            end
        end

        function out = info(obj)
            obj.requireRecorders();
            out = strings(numel(obj.Recorders), 1);
            for idx = 1:numel(obj.Recorders)
                out(idx) = obj.Recorders{idx}.info();
            end
        end

        function out = raw(obj, command)
            obj.requireRecorders();
            out = strings(numel(obj.Recorders), 1);
            for idx = 1:numel(obj.Recorders)
                out(idx) = obj.Recorders{idx}.raw(command);
            end
        end

        function quit(obj)
            obj.shutdownRecorders(obj.Recorders);
            obj.Recorders = cell(1, 0);
            obj.StreamUrls = strings(numel(obj.Cameras), 1);
        end

        function delete(obj)
            try
                obj.quit();
            catch
            end
        end
    end

    methods (Access = private)
        function configs = normalizeCameraConfigs(~, cameraConfigs)
            if isempty(cameraConfigs)
                configs = repmat(VlcRecorderGroup.emptyCameraConfig(), 0, 1);
                return;
            end

            if ischar(cameraConfigs) || isstring(cameraConfigs)
                webcamNames = string(cameraConfigs(:));
                configs = repmat(VlcRecorderGroup.emptyCameraConfig(), numel(webcamNames), 1);
                for idx = 1:numel(webcamNames)
                    configs(idx).WebcamName = webcamNames(idx);
                end
                return;
            end

            if iscell(cameraConfigs)
                try
                    webcamNames = string(cameraConfigs(:));
                catch
                    error('VlcRecorderGroup:InvalidCameraConfigs', ...
                        'Cell cameraConfigs must contain only webcam name text values.');
                end
                configs = repmat(VlcRecorderGroup.emptyCameraConfig(), numel(webcamNames), 1);
                for idx = 1:numel(webcamNames)
                    configs(idx).WebcamName = webcamNames(idx);
                end
                return;
            end

            if ~isstruct(cameraConfigs)
                error('VlcRecorderGroup:InvalidCameraConfigs', ...
                    'cameraConfigs must be a struct array, string array, char vector, or cellstr array.');
            end

            configs = repmat(VlcRecorderGroup.emptyCameraConfig(), numel(cameraConfigs), 1);
            for idx = 1:numel(cameraConfigs)
                configs(idx) = VlcRecorderGroup.mergeCameraConfig(cameraConfigs(idx));
            end
        end

        function configs = applyCameraDefaults(obj, configs)
            for idx = 1:numel(configs)
                if strlength(configs(idx).Name) == 0
                    configs(idx).Name = "Camera " + string(idx);
                end
                if strlength(configs(idx).Host) == 0
                    configs(idx).Host = obj.Host;
                end
                if isempty(configs(idx).Port)
                    configs(idx).Port = obj.BasePort + idx - 1;
                else
                    configs(idx).Port = round(configs(idx).Port);
                end
                if strlength(configs(idx).VlcPath) == 0
                    configs(idx).VlcPath = obj.VlcPath;
                end
                if isempty(configs(idx).Timeout)
                    configs(idx).Timeout = obj.Timeout;
                end
                if strlength(configs(idx).RecordingMux) == 0
                    configs(idx).RecordingMux = "ts";
                end
                if strlength(configs(idx).StreamPath) == 0
                    configs(idx).StreamPath = "/webcam";
                end
                if strlength(configs(idx).StreamMux) == 0
                    configs(idx).StreamMux = "ts";
                end
                if strlength(configs(idx).StreamBind) == 0
                    configs(idx).StreamBind = "0.0.0.0";
                end
                if isempty(configs(idx).ShowPreview)
                    configs(idx).ShowPreview = true;
                else
                    configs(idx).ShowPreview = logical(configs(idx).ShowPreview);
                end
                if isempty(configs(idx).LiveCaching)
                    configs(idx).LiveCaching = 300;
                else
                    configs(idx).LiveCaching = round(configs(idx).LiveCaching);
                end
                if strlength(configs(idx).ExtraArgs) == 0
                    configs(idx).ExtraArgs = "--no-video-title-show";
                end
            end
        end

        function validateCameraConfigs(~, configs)
            if isempty(configs)
                error('VlcRecorderGroup:NoCameras', ...
                    'At least one camera configuration is required.');
            end

            webcamKeys = strings(numel(configs), 1);
            hostPorts = strings(numel(configs), 1);
            streamPorts = strings(0, 1);
            recordingFiles = strings(0, 1);

            for idx = 1:numel(configs)
                cameraConfig = configs(idx);
                webcamName = strtrim(string(cameraConfig.WebcamName));
                if strlength(webcamName) == 0
                    error('VlcRecorderGroup:InvalidWebcam', ...
                        'Camera configuration %d must define a non-empty WebcamName.', idx);
                end

                webcamKeys(idx) = lower(webcamName);

                if ~cameraConfig.ShowPreview && strlength(cameraConfig.RecordingFile) == 0 && isempty(cameraConfig.StreamPort)
                    error('VlcRecorderGroup:NoOutputs', ...
                        'Camera "%s" must enable ShowPreview, RecordingFile, or StreamPort.', char(cameraConfig.Name));
                end
                if ~(isscalar(cameraConfig.Port) && isnumeric(cameraConfig.Port) && isfinite(cameraConfig.Port) && cameraConfig.Port > 0)
                    error('VlcRecorderGroup:InvalidPort', ...
                        'Camera "%s" has an invalid RC port.', char(cameraConfig.Name));
                end

                if ~(isscalar(cameraConfig.Timeout) && isnumeric(cameraConfig.Timeout) && isfinite(cameraConfig.Timeout) && cameraConfig.Timeout > 0)
                    error('VlcRecorderGroup:InvalidTimeout', ...
                        'Camera "%s" has an invalid timeout.', char(cameraConfig.Name));
                end

                hostPorts(idx) = lower(strtrim(cameraConfig.Host)) + ":" + string(cameraConfig.Port);

                if ~isempty(cameraConfig.StreamPort)
                    if ~(isscalar(cameraConfig.StreamPort) && isnumeric(cameraConfig.StreamPort) && isfinite(cameraConfig.StreamPort) && cameraConfig.StreamPort > 0)
                        error('VlcRecorderGroup:InvalidStreamPort', ...
                            'Camera "%s" has an invalid HTTP stream port.', char(cameraConfig.Name));
                    end
                    streamPorts(end+1, 1) = lower(strtrim(cameraConfig.StreamBind)) + ":" + string(round(cameraConfig.StreamPort)); %#ok<AGROW>
                end

                if strlength(cameraConfig.RecordingFile) > 0
                    recordingFiles(end+1, 1) = VlcRecorderGroup.normalizePathKey(cameraConfig.RecordingFile); %#ok<AGROW>
                end
            end

            VlcRecorderGroup.errorOnDuplicates(webcamKeys, ...
                'VlcRecorderGroup:AmbiguousWebcamName', ...
                ['VLC DirectShow selects webcams by friendly name only, so duplicate WebcamName values ', ...
                'cannot be launched reliably in the same VlcRecorderGroup. Rename one camera in Windows ', ...
                'or use a backend that exposes unique device identifiers.']);

            VlcRecorderGroup.errorOnDuplicates(hostPorts, ...
                'VlcRecorderGroup:DuplicatePort', ...
                'Each camera requires a unique VLC RC host/port combination.');

            if ~isempty(streamPorts)
                VlcRecorderGroup.errorOnDuplicates(streamPorts, ...
                    'VlcRecorderGroup:DuplicateStreamPort', ...
                    'Each camera requires a unique HTTP stream bind/port combination.');
            end

            if ~isempty(recordingFiles)
                VlcRecorderGroup.errorOnDuplicates(recordingFiles, ...
                    'VlcRecorderGroup:DuplicateRecordingFile', ...
                    'Each camera requires a unique recording output path.');
            end
        end

        function pairs = cameraOptionPairs(~, cameraConfig)
            pairs = { ...
                'AudioDevice', cameraConfig.AudioDevice, ...
                'RecordingFile', cameraConfig.RecordingFile, ...
                'RecordingMux', cameraConfig.RecordingMux, ...
                'FrameRate', cameraConfig.FrameRate, ...
                'StreamPort', cameraConfig.StreamPort, ...
                'StreamPath', cameraConfig.StreamPath, ...
                'StreamMux', cameraConfig.StreamMux, ...
                'StreamBind', cameraConfig.StreamBind, ...
                'ShowPreview', cameraConfig.ShowPreview, ...
                'LiveCaching', cameraConfig.LiveCaching, ...
                'ExtraArgs', cameraConfig.ExtraArgs};
        end

        function requireConfiguredCameras(obj)
            if isempty(obj.Cameras)
                error('VlcRecorderGroup:NoCameras', ...
                    'At least one camera configuration is required.');
            end
        end

        function requireRecorders(obj)
            if isempty(obj.Recorders)
                error('VlcRecorderGroup:NotLaunched', ...
                    'No VLC recorders have been launched. Call launchWebcams() first.');
            end
        end

        function disconnectRecorders(~, recorders)
            for idx = 1:numel(recorders)
                if isempty(recorders{idx})
                    continue;
                end
                try
                    recorders{idx}.disconnect();
                catch
                end
            end
        end

        function stopRecorders(~, recorders)
            firstError = [];
            for idx = 1:numel(recorders)
                if isempty(recorders{idx})
                    continue;
                end
                try
                    recorders{idx}.stopRecording();
                catch me
                    if isempty(firstError)
                        firstError = me;
                    end
                end
            end

            if ~isempty(firstError)
                rethrow(firstError)
            end
        end

        function shutdownRecorders(~, recorders)
            for idx = 1:numel(recorders)
                if isempty(recorders{idx})
                    continue;
                end
                try
                    recorders{idx}.quit();
                catch
                end
            end
        end
    end

    methods (Static, Access = private)
        function cameraConfig = emptyCameraConfig()
            cameraConfig = struct( ...
                'Name', "", ...
                'WebcamName', "", ...
                'AudioDevice', "", ...
                'RecordingFile', "", ...
                'RecordingMux', "", ...
                'FrameRate', [], ...
                'StreamPort', [], ...
                'StreamPath', "", ...
                'StreamMux', "", ...
                'StreamBind', "", ...
                'ShowPreview', [], ...
                'LiveCaching', [], ...
                'ExtraArgs', "", ...
                'VlcPath', "", ...
                'Host', "", ...
                'Port', [], ...
                'Timeout', []);
        end

        function cameraConfig = mergeCameraConfig(inputConfig)
            cameraConfig = VlcRecorderGroup.emptyCameraConfig();
            configFields = fieldnames(cameraConfig);

            for fieldIdx = 1:numel(configFields)
                fieldName = configFields{fieldIdx};
                if isfield(inputConfig, fieldName)
                    cameraConfig.(fieldName) = VlcRecorderGroup.normalizeCameraField(fieldName, inputConfig.(fieldName));
                end
            end
        end

        function value = normalizeCameraField(fieldName, value)
            switch fieldName
                case {'Name', 'WebcamName', 'AudioDevice', 'RecordingFile', 'RecordingMux', ...
                        'StreamPath', 'StreamMux', 'StreamBind', 'ExtraArgs', 'VlcPath', 'Host'}
                    value = string(value);
                case {'Port', 'StreamPort', 'Timeout', 'LiveCaching', 'FrameRate'}
                    if isempty(value)
                        return;
                    end
                    value = double(value);
                case 'ShowPreview'
                    if isempty(value)
                        return;
                    end
                    value = logical(value);
            end
        end

        function pathKey = normalizePathKey(pathValue)
            pathText = char(string(pathValue));
            if isempty(pathText)
                pathKey = "";
                return;
            end

            if VlcRecorderGroup.isAbsolutePath(pathText)
                fullPath = pathText;
            else
                fullPath = fullfile(pwd, pathText);
            end

            fullPath = strrep(fullPath, '/', '\');
            pathKey = lower(string(fullPath));
        end

        function tf = isAbsolutePath(pathText)
            tf = ~isempty(regexp(pathText, '^[A-Za-z]:[\\/]', 'once')) || startsWith(pathText, '\\');
        end

        function errorOnDuplicates(values, identifier, messageText)
            if isempty(values)
                return;
            end

            [uniqueValues, ~, groupIndex] = unique(values, 'stable');
            counts = accumarray(groupIndex, 1);
            duplicateValues = uniqueValues(counts > 1);
            if ~isempty(duplicateValues)
                error(identifier, '%s Duplicate values: %s', ...
                    messageText, char(strjoin(duplicateValues, ', ')));
            end
        end
    end
end