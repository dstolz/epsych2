function OpenCurrentErrorLog(~)
% OpenCurrentErrorLog(self)
% Open today's EPsych error log with the OS-associated text editor.
%
% Creates the current daily log file under .error_logs if it does not yet
% exist, then launches it through the operating system shell so the
% machine's default text application handles the file.

logDir = fullfile(epsych_path,'.error_logs');
if ~isfolder(logDir)
    mkdir(logDir);
end

logPath = fullfile(logDir, sprintf('error_log_%s.txt', datestr(now,'ddmmmyyyy')));

fid = fopen(logPath,'at');
if fid < 0
    errordlg(sprintf('Unable to access the current error log.\n\n%s', logPath), ...
        'Open Error Log','modal');
    return
end
fclose(fid);

try
    if ispc
        winopen(logPath);
    elseif ismac
        [status, cmdout] = system(sprintf('open "%s"', logPath));
    else
        [status, cmdout] = system(sprintf('xdg-open "%s"', logPath));
    end

    if ~ispc && status ~= 0
        error('EPsych:RunExpt:OpenCurrentErrorLogFailed', ...
            'Command failed while opening error log: %s', strtrim(cmdout));
    end
catch ME
    vprintf(0,1,ME);
    errordlg(sprintf('Unable to open the current error log.\n\n%s', logPath), ...
        'Open Error Log','modal');
end
end