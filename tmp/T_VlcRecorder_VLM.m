%%

close all force

clear classes

rehash toolboxcache

clc

startup

%

addpath c:\src\epsych2

epsych_startup;

%%

% T_VlcRecorder  Diagnostic test for hw.VlcRecorder (ffmpeg backend).
% Run this from the MATLAB Command Window after calling epsych_startup.
%
% Tests the full recording workflow:
%   connect -> set parameters -> Play (launches VLC display + ffmpeg) ->
%   wait -> Stop (kills ffmpeg, finalises file, closes VLC) -> check file.
%
% Requires:
%   ffmpeg.exe at C:\prgms_on_path\ffmpeg.exe
%   VLC at     C:\Program Files (x86)\VideoLAN\VLC\vlc.exe
%   DirectShow webcam device named "Integrated Camera"

clc
evalin('base', 'global GVerbosity; GVerbosity = 3;');

logFile = fullfile(fileparts(mfilename('fullpath')), 'T_VlcRecorder_VLM_last_run.log');
if isfile(logFile)
    delete(logFile);
end
diary(logFile);
cleanupDiary = onCleanup(@() diary('off')); %#ok<NASGU>
fprintf('Log file: %s\n\n', logFile);

deviceName = 'Integrated Camera';
outFile    = 'C:\Temp\capture_vlcrecorder.ts';
recordSecs = 10;

%% 1. Preconditions
fprintf('--- Precondition checks ---\n');

ffmpegPath = 'C:\prgms_on_path\ffmpeg.exe';
vlcPath    = 'C:\Program Files (x86)\VideoLAN\VLC\vlc.exe';

if isfile(ffmpegPath)
    fprintf('PASS: ffmpeg found at %s\n', ffmpegPath);
else
    fprintf('FAIL: ffmpeg not found at %s\n', ffmpegPath);
end

if isfile(vlcPath)
    fprintf('PASS: VLC found at %s\n', vlcPath);
else
    fprintf('FAIL: VLC not found at %s\n', vlcPath);
end

outDir = fileparts(outFile);
if ~isempty(outDir) && ~isfolder(outDir)
    mkdir(outDir);
end
if isfile(outFile)
    delete(outFile);
    fprintf('  Deleted existing output file.\n');
end
fprintf('\n');

%% 2. Connect
fprintf('--- Connect ---\n');
obj = hw.VlcRecorder();
obj.connect();
fprintf('  IsConnected: %d\n\n', obj.IsConnected);

%% 3. Configure parameters
fprintf('--- Parameters ---\n');
obj.set_parameter('DeviceName',    deviceName);
obj.set_parameter('RecordingFile', outFile);
obj.set_parameter('MediaFile',     'dshow://');
fprintf('  DeviceName    : %s\n', deviceName);
fprintf('  RecordingFile : %s\n', outFile);
fprintf('  MediaFile     : dshow://\n\n');

%% 4. Play (launches VLC display + ffmpeg recording)
fprintf('--- trigger(Play) ---\n');
obj.trigger('Play');
fprintf('  Launched. Recording for %d seconds...\n', recordSecs);
pause(recordSecs);

%% 5. Stop
fprintf('--- trigger(Stop) ---\n');
obj.trigger('Stop');
pause(1);  % allow OS to flush file handles
fprintf('  Stopped.\n\n');

%% 6. Disconnect
obj.disconnect();
fprintf('  Disconnected.\n\n');

%% 7. Verify output file
fprintf('--- Output file check ---\n');
if isfile(outFile)
    d = dir(outFile);
    fprintf('PASS: file created. Size = %d bytes.\n', d.bytes);
    if d.bytes < 1000
        fprintf('WARN: file is very small — recording may not have captured any frames.\n');
    end
else
    fprintf('FAIL: output file not found at %s\n', outFile);
end

fprintf('\nRun log written to: %s\n', logFile);
