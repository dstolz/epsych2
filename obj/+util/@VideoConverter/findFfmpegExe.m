function exePath = findFfmpegExe(preferredExe)
% exePath = util.VideoConverter.findFfmpegExe()
% exePath = util.VideoConverter.findFfmpegExe(preferredExe)
% Locate ffmpeg.exe from an explicit path, the 'ffmpeg'/'exepath'
% preference (read directly via getpref -- never via ffmpegpath(), which
% throws when the preference is unset), common install locations, or the
% system PATH. Returns "" when ffmpeg cannot be found; never throws
% (mirrors hw.VlcRecorder.findVlcExe's degrade contract).
arguments
    preferredExe (1,1) string = ""
end

cands = string.empty(1,0);
if preferredExe ~= ""
    cands(end+1) = preferredExe;
end
p = getpref('ffmpeg', 'exepath', '');
if ~isempty(p)
    cands(end+1) = string(p);
end
cands(end+1) = "C:\prgms\ffmpeg\bin\ffmpeg.exe";
pf = getenv('ProgramFiles');
if ~isempty(pf)
    cands(end+1) = string(fullfile(pf, 'ffmpeg', 'bin', 'ffmpeg.exe'));
end

exePath = "";
for c = cands
    if c ~= "" && isfile(c)
        exePath = c;
        return
    end
end

[st, out] = system('where ffmpeg.exe');
if st == 0
    lines = strtrim(splitlines(strtrim(out)));
    lines = lines(~cellfun('isempty', lines));
    if ~isempty(lines)
        exePath = string(lines{1});
    end
end
end
