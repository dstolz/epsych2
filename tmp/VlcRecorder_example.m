% VlcRecorder_example.m
% Example script demonstrating hw.VlcRecorder for webcam recording.
%
% Records 10 seconds of webcam video to C:\Temp\vlcrecorder_example.ts
% while displaying a live preview in VLC.
%
% Requirements:
%   - ffmpeg.exe at C:\prgms_on_path\ffmpeg.exe
%   - VLC at C:\Program Files (x86)\VideoLAN\VLC\vlc.exe
%   - A DirectShow webcam named "Integrated Camera"
%   - EPsych on the MATLAB path (run epsych_startup if needed)
%
% See also: documentation/hw/hw_VlcRecorder.md

%% Configuration
deviceName  = 'Integrated Camera';      % DirectShow webcam device name
outFile     = 'C:\Temp\vlcrecorder_example.ts';  % output recording file
recordSecs  = 10;                        % recording duration in seconds

%% Create output directory if needed
if ~isfolder(fileparts(outFile))
    mkdir(fileparts(outFile));
end

%% Create and connect
obj = hw.VlcRecorder();
obj.connect();

%% Set parameters
obj.set_parameter('DeviceName',    deviceName);
obj.set_parameter('RecordingFile', outFile);
obj.set_parameter('MediaFile',     'dshow://');

%% Start — opens VLC live preview and begins recording
obj.trigger('Play');
fprintf('Recording for %d seconds...\n', recordSecs);
pause(recordSecs);

%% Stop — finalises the recording file and closes VLC
obj.trigger('Stop');
obj.disconnect();

%% Check result
if isfile(outFile)
    d = dir(outFile);
    fprintf('Done. Output file: %s  (%d bytes)\n', outFile, d.bytes);
else
    fprintf('Output file not found: %s\n', outFile);
end
