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
epsych.ProtocolDesigner('S:/RIG3_Backup_2025/epsych_files/Protocols/TEST.eprot')

%%
gui = stimgen.calibration.CalibrationGui();



%%

% T_VlcRecorder  Diagnostic test for hw.VlcRecorder (VLC-only backend).
% Run this from the MATLAB Command Window after calling epsych_startup.
%
% Tests the full recording workflow:
%   connect -> set parameters -> Play (launches VLC with --sout for
%   simultaneous display + recording) -> wait -> Stop (kills VLC,
%   finalises file) -> check file.
%
% Requires:
%   VLC at C:\Program Files (x86)\VideoLAN\VLC\vlc.exe
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
outFile    = 'C:\Temp\capture_vlcrecorder.mp4';
recordSecs = 10;

%% 1. Preconditions
fprintf('--- Precondition checks ---\n');

vlcPath = 'C:\Program Files (x86)\VideoLAN\VLC\vlc.exe';

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

P.Play.Trigger;


%% 3. Configure parameters
fprintf('--- Parameters ---\n');
P = obj.all_parameters(asStruct=true,includeTriggers=true,includeInvisible=true);
P.DeviceName.Value = deviceName;
P.RecordingFile.Value = outFile;
P.MediaFile.Value = 'dshow://';
fprintf('  DeviceName    : %s\n', P.DeviceName.Value);
fprintf('  RecordingFile : %s\n', P.RecordingFile.Value);
fprintf('  MediaFile     : %s\n\n',P.MediaFile.Value);

%% 4. Play (launches VLC with --sout for display + recording)
fprintf('--- trigger(Play) ---\n');
P.StartRecord.Trigger;
fprintf('  Launched. Recording for %d seconds...\n', recordSecs);
pause(recordSecs);

%% 5. Stop
fprintf('--- trigger(Stop) ---\n');
P.StopRecord.Trigger;
pause(1);  % allow VLC to flush file buffers
fprintf('  Stopped.\n\n');

%% 6. Disconnect
P.Stop.Trigger;

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
