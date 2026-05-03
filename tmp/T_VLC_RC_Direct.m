% T_VLC_RC_Direct  Webcam recording test: ffmpeg primary, VLC RC fallback.
% Run this script from MATLAB to test webcam capture.
% ffmpeg must be on the system PATH.

close all force
clc

% ---------------- User settings ----------------
outFile      = 'C:\Temp\capture_direct.ts';
videoDevice  = 'Integrated Camera';   % from: ffmpeg -list_devices true -f dshow -i dummy
recordSeconds = 8;

% VLC fallback settings
vlcExe    = 'C:\Program Files (x86)\VideoLAN\VLC\vlc.exe';
host      = '127.0.0.1';
port      = 4212;
streamName = 'epsych_direct_webcam';
% ----------------------------------------------

logFile = fullfile(fileparts(mfilename('fullpath')), 'T_VLC_RC_Direct_last_run.log');
if isfile(logFile), delete(logFile); end
diary(logFile);
cleanupDiary = onCleanup(@() diary('off')); %#ok<NASGU>

fprintf('--- Webcam recording test ---\n');
fprintf('Log file: %s\n', logFile);
fprintf('Output  : %s\n', outFile);
fprintf('Device  : %s\n\n', videoDevice);

outDir = fileparts(outFile);
if ~isempty(outDir) && ~isfolder(outDir)
    mkdir(outDir);
end
if isfile(outFile), delete(outFile); end

outFileVlc = strrep(outFile, '\', '/');
[~, ~, ext] = fileparts(outFile);
switch lower(ext)
    case '.mp4';  mux = 'mp4';
    case '.mkv';  mux = 'mkv';
    case '.avi';  mux = 'avi';
    case '.ogv';  mux = 'ogg';
    case '.mov';  mux = 'mov';
    otherwise;    mux = 'ts';
end

% -------------------------------------------------------
% Strategy 0: ffmpeg dshow capture (most reliable on Windows).
% -------------------------------------------------------
fprintf('--- Strategy 0: ffmpeg dshow ---\n');
ffCmd = sprintf('ffmpeg -y -f dshow -i video="%s" -t %d -vcodec libx264 -preset ultrafast -crf 28 "%s"', ...
    videoDevice, recordSeconds, outFile);
fprintf('Command: %s\n', ffCmd);
[rc, out] = system(ffCmd);
fprintf('%s\n', strtrim(out));
if rc ~= 0
    fprintf('ffmpeg exit code: %d\n', rc);
end
success = checkOutput(outFile);
if success, fprintf('Strategy 0 (ffmpeg) succeeded.\n'); end

% -------------------------------------------------------
% Strategy 1: VLC command-line with --sout baked in.
% -------------------------------------------------------
if ~success
    fprintf('\n--- Strategy 1: VLC command-line --sout ---\n');
    system('taskkill /F /IM vlc.exe >nul 2>&1');
    pause(0.5);
    if isfile(outFile), delete(outFile); end

    s1sout = sprintf('#transcode{vcodec=h264,acodec=none,vb=1500,fps=30}:std{access=file,mux=%s,dst=%s}', ...
        mux, outFileVlc);
    vlcArgs = sprintf('dshow:// :dshow-caching=200 --sout="%s" --sout-keep --run-time=%d vlc://quit', ...
        s1sout, recordSeconds);
    vlcCmd = sprintf('start "" "%s" %s', vlcExe, vlcArgs);
    fprintf('Command: %s\n', vlcCmd);
    system(vlcCmd);
    pause(recordSeconds + 4);
    success = checkOutput(outFile);
    if success, fprintf('Strategy 1 (VLC CLI) succeeded.\n'); end
end

% -------------------------------------------------------
% Strategy 2: VLC RC + VLM (file-only sout, no duplicate).
% -------------------------------------------------------
if ~success
    fprintf('\n--- Strategy 2: VLC RC VLM file-only ---\n');
    system('taskkill /F /IM vlc.exe >nul 2>&1');
    pause(0.5);
    rcLaunchCmd = sprintf('start "" "%s" --extraintf rc --rc-host %s:%d --rc-quiet', vlcExe, host, port);
    system(rcLaunchCmd);
    pause(1.5);
    c = connectRc(host, port);
    cleanupObj = onCleanup(@() safeDisconnect(c)); %#ok<NASGU>
    fprintf('Connected to VLC RC.\n');
    readAvailable(c);  % flush banner

    if isfile(outFile), delete(outFile); end
    soutFile = sprintf('transcode{vcodec=h264,acodec=none,vb=1500,fps=30}:std{access=file,mux=%s,dst=%s}', ...
        mux, outFileVlc);
    runVlmStrategy(c, streamName, 'dshow:// :dshow-caching=200', soutFile, recordSeconds);
    success = checkOutput(outFile);
    if success, fprintf('Strategy 2 (VLC RC VLM file-only) succeeded.\n'); end
end

if ~success
    fprintf('\nFAIL: all strategies failed to create output file at %s\n', outFile);
end

fprintf('\nRun log written to: %s\n', logFile);



function runVlmStrategy(c, streamName, mediaUri, sout, recordSeconds)
% runVlmStrategy(c, streamName, mediaUri, sout, recordSeconds)
% Configure and run one VLM recording strategy.
sendRc(c, sprintf('control %s stop', streamName));
sendRc(c, sprintf('del %s', streamName));
sendRc(c, sprintf('new %s broadcast enabled', streamName));
sendRc(c, sprintf('setup %s input %s', streamName, mediaUri));
sendRc(c, sprintf('setup %s output %s', streamName, sout));
sendRc(c, sprintf('setup %s enabled', streamName));
sendRc(c, sprintf('control %s play', streamName));
pause(recordSeconds);
sendRc(c, sprintf('control %s stop', streamName));
pause(1.0);
sendRc(c, sprintf('show %s', streamName));
sendRc(c, sprintf('del %s', streamName));
end


function tf = checkOutput(outFile)
% tf = checkOutput(outFile)
% Print output status and return true when a non-empty file exists.
if isfile(outFile)
    d = dir(outFile);
    fprintf('Output file exists. Size = %d bytes\n', d.bytes);
    tf = d.bytes > 0;
else
    fprintf('Output file not found at %s\n', outFile);
    tf = false;
end
end


function tf = isVlcRunning() %#ok<DEFNU>
% tf = isVlcRunning()
% Return true when a vlc.exe process is present.
[~, out] = system('tasklist /FI "IMAGENAME eq vlc.exe" /FO CSV /NH');
out = lower(string(out));
tf = contains(out, 'vlc.exe');
end


function c = connectRc(host, port)
% c = connectRc(host, port)
% Connect to VLC RC socket with retries while VLC starts.
maxAttempts = 25;
for k = 1:maxAttempts
    try
        c = tcpclient(host, port, Timeout = 2);
        pause(0.2);
        flush(c);
        return
    catch
        pause(0.25);
    end
end
error('Could not connect to VLC RC at %s:%d', host, port);
end


function response = sendRc(c, cmd)
% response = sendRc(c, cmd)
% Send one RC command and print any response text.
write(c, uint8([cmd newline]));
pause(0.25);
response = readAvailable(c);
fprintf('> %s\n', cmd);
if ~isempty(strtrim(response))
    fprintf('< %s\n', strtrim(response));
end
end


function out = readAvailable(c)
% out = readAvailable(c)
% Read all currently available bytes from VLC RC socket.
out = '';
while c.NumBytesAvailable > 0
    out = [out char(read(c, c.NumBytesAvailable, 'uint8'))];
    pause(0.05);
end
end


function safeDisconnect(c)
% safeDisconnect(c)
% Close the RC connection without throwing.
try
    delete(c);
catch
end
end
