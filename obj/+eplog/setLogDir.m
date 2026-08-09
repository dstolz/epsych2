function d = setLogDir(p)
% d = eplog.setLogDir(p)    write the daily logs to p from now on
% d = eplog.setLogDir('')   clear the override, back to <epsych root>/.error_logs
%
% Stores the choice as getpref('eplog','LogDir') so it survives MATLAB
% restarts, and re-points the live logger immediately: every file sink is
% closed and reopened against the new directory, so the next message lands
% there rather than at the next MATLAB session.
%
% Rigs whose repository sits on a read-only or synced share need their logs
% elsewhere; this is how RunExpt's Customize > Paths > Error Log Path sets
% them. The change is recorded in both the old log and the new one, so a
% reader of either can follow the trail.
%
% Unlike the rest of the package this DOES throw, because it is configuration
% rather than logging: a rejected setting must be visible to the operator
% typing it, not swallowed the way a bad log message is.
%
% Parameters:
%   p - absolute directory path, or '' to clear the override. A relative path
%       is refused: every cd would otherwise start a new log directory, and
%       "Open Current Error Log" would point at whichever one is current.
%
% Returns:
%   d - the directory now in effect (see eplog.defaultLogDir)
%
% Example:
%   eplog.setLogDir('D:\rig_logs')
%   eplog.setLogDir('')          % back to the repository default
%
% See also: eplog.defaultLogDir, eplog.isAbsolutePath, eplog.sink.FileSink

arguments
    p {mustBeTextScalar} = ''
end

p = strtrim(char(p));

if ~isempty(p)
    if ~eplog.isAbsolutePath(p)
        error('eplog:setLogDir:RelativePath', ...
            ['The log directory must be an absolute path; "%s" is relative. ' ...
             'A relative path would follow the working directory.'],p);
    end

    if ~isfolder(p)
        [made,msg] = mkdir(p);
        if ~made
            error('eplog:setLogDir:NotWritable', ...
                'Could not create the log directory "%s": %s',p,msg);
        end
    end
end

% Leave a marker in the log being left behind, and make sure it reaches disk
% before the handle moves.
L = eplog.Logger.instance();
if ~isempty(p)
    vprintf(1,'Log directory changing to: %s',p);
else
    vprintf(1,'Log directory reverting to the EPsych default');
end
L.flush();

if isempty(p)
    if ispref('eplog','LogDir')
        rmpref('eplog','LogDir');
    end
else
    setpref('eplog','LogDir',p);
end

d = eplog.defaultLogDir();

% Re-point the live sinks. reset() also clears a latched open failure, so a
% logger that gave up on an unwritable directory starts working again here.
for k = 1:numel(L.Sinks)
    s = L.Sinks{k};
    if isa(s,'eplog.sink.FileSink')
        s.reset();
        s.Dir = d;
    end
end

vprintf(1,'Log directory: %s',d);
end
