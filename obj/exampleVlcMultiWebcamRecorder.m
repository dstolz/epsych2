%% Minimal multi-camera VLC webcam recording example
%
% This script launches one VLC instance per webcam so multiple DirectShow
% devices can be streamed and recorded simultaneously from MATLAB.
%
% Requirements:
%   1. VLC must be installed.
%   2. At least two webcam devices must be available.
%   3. Each camera must use a unique RC port and HTTP stream port.

webcams = VlcRecorder.listWebcams();
if numel(webcams) < 2
    error('EPsych:exampleVlcMultiWebcamRecorder:NotEnoughWebcams', ...
        'At least two webcams are required for the multi-camera example.')
end

outputDir = fullfile(tempdir, 'epsych_vlc_multi_webcam_demo');
if ~isfolder(outputDir)
    mkdir(outputDir)
end

configs(1) = struct( ...
    'Name', "Camera 1", ...
    'WebcamName', webcams(1), ...
    'RecordingFile', fullfile(outputDir, 'camera1.ts'), ...
    'StreamPort', 8080, ...
    'StreamPath', "/camera1", ...
    'ShowPreview', true);
configs(2) = struct( ...
    'Name', "Camera 2", ...
    'WebcamName', webcams(2), ...
    'RecordingFile', fullfile(outputDir, 'camera2.ts'), ...
    'StreamPort', 8081, ...
    'StreamPath', "/camera2", ...
    'ShowPreview', true);

group = VlcRecorderGroup(configs);
cleanupGroup = onCleanup(@() delete(group)); %#ok<NASGU>

streamUrls = group.launchWebcams();
group.connect();

fprintf('Camera 1 stream: %s\n', streamUrls(1))
fprintf('Camera 2 stream: %s\n', streamUrls(2))

pause(10)
group.quit();