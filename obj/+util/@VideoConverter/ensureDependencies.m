function [ok, exePath, probePath, msg] = ensureDependencies(preferredExe)
% [ok,exePath,probePath,msg] = util.VideoConverter.ensureDependencies(preferredExe)
% Put the FFmpeg Toolbox Add-On on the path if it can be located (only
% needed for the ffmpeginfo fallback probe -- execution never depends on
% it) and resolve ffmpeg.exe/ffprobe.exe.
%
% Degrades gracefully: returns ok=false and exePath="" rather than
% throwing, mirroring hw.VlcRecorder.findVlcExe(). Never calls
% ffmpegpath() speculatively -- it throws when the 'ffmpeg'/'exepath'
% preference is unset, so callers must never rely on it being callable.
arguments
    preferredExe (1,1) string = ""
end

ok = false;
probePath = "";
msg = "";

if exist('ffmpegpath', 'file') ~= 2
    roots = string.empty(1,0);
    appdata = getenv('APPDATA');
    if ~isempty(appdata)
        roots(end+1) = string(fullfile(appdata, 'MathWorks', 'MATLAB Add-Ons', 'Collections'));
    end
    try
        roots(end+1) = string(fullfile(userpath, 'Add-Ons', 'Collections'));
    catch
    end
    for r = roots
        if exist('ffmpegpath', 'file') == 2
            break
        end
        if ~isfolder(r)
            continue
        end
        c = dir(fullfile(r, '*FFmpeg*'));
        c = c([c.isdir]);
        for j = 1:numel(c)
            cand = fullfile(c(j).folder, c(j).name);
            if isfile(fullfile(cand, 'ffmpegpath.m'))
                addpath(cand);   % collection root only; private/ is auto-scoped by MATLAB
                break
            end
        end
    end
end

exePath = util.VideoConverter.findFfmpegExe(preferredExe);
if exePath == ""
    msg = "ffmpeg.exe not found; set the FfmpegExe property, add it to PATH, or run ffmpegsetup.";
    return
end

[st, ~] = system(sprintf('"%s" -hide_banner -version', exePath));
if st ~= 0
    msg = sprintf('ffmpeg at "%s" is not executable.', exePath);
    exePath = "";
    return
end

pp = fullfile(fileparts(char(exePath)), 'ffprobe.exe');
if isfile(pp)
    probePath = string(pp);
end

% ffmpeginfo (the toolbox duration-probe fallback) calls ffmpegpath(),
% which throws if this preference is unset -- so make it usable here,
% but only ever fill in a missing value, and log that we did.
if isempty(getpref('ffmpeg', 'exepath', ''))
    setpref('ffmpeg', 'exepath', char(exePath));
    vprintf(1, 'util.VideoConverter: set ffmpeg exepath preference to %s', exePath);
end

ok = true;
end
