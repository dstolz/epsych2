%% Minimal standalone webcam recorder example
%
% This script exercises epsych.WebcamRecorder without integrating it into
% the EPsych runtime. It records a short clip, then prints the output
% artifact locations.

outputDir = fullfile(tempdir, 'epsych_webcam_demo');

recorder = epsych.WebcamRecorder( ...
    TargetFrameRate = 10, ...
    OutputDir = outputDir, ...
    BaseName = 'demo_recording', ...
    RecordAudio = true);

cleanupRecorder = onCleanup(@() delete(recorder)); %#ok<NASGU>

recorder.start();
pause(5);
recorder.stop();

artifacts = recorder.artifacts();
disp(artifacts)