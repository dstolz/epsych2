function OpenCurrentErrorLog(~, useExternalViewer)
% OpenCurrentErrorLog(self)
% OpenCurrentErrorLog(self, useExternalViewer)
% Open today's EPsych error log outside the MATLAB editor.
%
% Flushes the logger so the tail of the session is on disk, creates the
% current daily log file if it does not yet exist, then hands it to an
% application outside MATLAB.
%
% Parameters:
%	useExternalViewer	- false (default) opens the file through the operating
%                         system's file association. true launches the
%                         application configured in Customize > Paths >
%                         Error Log Viewer, which is how an operator whose
%                         .txt association points at MATLAB gets the log in a
%                         plain text viewer instead of the editor.
%
% The log's location follows Customize > Paths > Error Log Path; see
% eplog.setLogDir.
%
% See also: eplog.Logger, eplog.setLogDir, epsych.RunExpt.defaultLogViewer

% No arguments block: the object input is unused here, and an arguments block
% must name every input including the ignored one.
if nargin < 2 || isempty(useExternalViewer), useExternalViewer = false; end
useExternalViewer = logical(useExternalViewer);

% The file sink buffers, and MATLAB offers no fflush; without this the last
% few messages -- usually the ones the operator opened the log to read -- are
% still in the buffer.
L = eplog.Logger.instance();
L.flush();

logPath = L.LogFile;
if isempty(logPath)
    % The logger is running without a file sink, so there is nothing to open.
    errordlg('File logging is disabled for this session, so there is no error log to open.', ...
        'Open Error Log','modal');
    return
end

logDir = fileparts(logPath);
if ~isfolder(logDir)
    mkdir(logDir);
end

fid = fopen(logPath,'at');
if fid < 0
    errordlg(sprintf('Unable to access the current error log.\n\n%s', logPath), ...
        'Open Error Log','modal');
    return
end
fclose(fid);

viewer = '';
if useExternalViewer
    % The Customize dialog persists an empty string to mean "platform default",
    % so the fallback is applied to the stored VALUE, not to getpref's default
    % -- once the preference exists, the getpref default never fires again.
    viewer = strtrim(char(getpref('ep_RunExpt_Logging','ExternalViewer','')));
    if isempty(viewer)
        viewer = epsych.RunExpt.defaultLogViewer();
    end
end

try
    launchViewer_(logPath, viewer);
catch ME
    vprintf(0,1,ME);
    if isempty(viewer)
        errordlg(sprintf('Unable to open the current error log.\n\n%s', logPath), ...
            'Open Error Log','modal');
    else
        errordlg(sprintf(['Unable to open the current error log with "%s".\n\n%s\n\n' ...
            'Set a different application in Customize > Paths > Error Log Viewer.'], ...
            viewer, logPath), 'Open Error Log','modal');
    end
end
end

% -----------------------------------------------------------------------
function launchViewer_(logPath, viewer)
% Hand logPath to viewer, or to the OS default when viewer is empty.
% Every branch returns immediately: a modal viewer that blocked here would
% block the session window with it.

if isempty(viewer)
    if ispc
        winopen(logPath);
        return
    elseif ismac
        % -t is the default TEXT editor rather than the .txt association, so
        % this stays out of the MATLAB editor even when MATLAB owns the type.
        cmd = sprintf('open -t "%s"', logPath);
    else
        cmd = sprintf('xdg-open "%s" &', logPath);
    end
else
    if ispc
        % The empty "" is start's title argument. Without it, start reads the
        % quoted program path as the window title and opens a bare console.
        cmd = sprintf('start "" "%s" "%s"', viewer, logPath);
    elseif ismac
        cmd = sprintf('open -a "%s" "%s"', viewer, logPath);
    else
        cmd = sprintf('"%s" "%s" &', viewer, logPath);
    end
end

[status, cmdout] = system(cmd);
if status ~= 0
    error('EPsych:RunExpt:OpenCurrentErrorLogFailed', ...
        'Command failed while opening error log: %s', strtrim(cmdout));
end
end
