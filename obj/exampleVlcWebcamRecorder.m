%% Minimal VLC webcam streaming and recording example
%
% This script exercises the VlcRecorder helper against a local DirectShow
% webcam on Windows. It launches VLC with the selected camera, opens a
% local HTTP stream, and records the same capture to disk.
%
% Requirements:
%   1. VLC must be installed.
%   2. VLC must support DirectShow capture on Windows.
%   3. The webcam device name must be visible to either webcamlist or the
%      Windows camera device enumeration used by VlcRecorder.listWebcams().

webcams = VlcRecorder.listWebcams();
if isempty(webcams)
    error('EPsych:exampleVlcWebcamRecorder:NoWebcams', ...
        'No webcam devices were found for VLC capture.')
end

outputDir = fullfile(tempdir, 'epsych_vlc_webcam_demo');
if ~isfolder(outputDir)
    mkdir(outputDir)
end

outputFile = fullfile(outputDir, 'vlc_webcam_capture.ts');
streamPort = 8080;

vlc = VlcRecorder();
cleanupVlc = onCleanup(@() delete(vlc)); %#ok<NASGU>

streamUrl = vlc.launchWebcam(webcams(1), ...
    'RecordingFile', outputFile, ...
    'RecordingMux', 'ts', ...
    'StreamPort', streamPort, ...
    'StreamPath', '/webcam', ...
    'ShowPreview', true);

vlc.connect();

fprintf('Recording to: %s\n', outputFile)
fprintf('Streaming on: %s\n', streamUrl)
pause(10)

vlc.quit();