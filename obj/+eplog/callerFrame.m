function [name,line,file] = callerFrame()
% [name,line,file] = eplog.callerFrame()
% Identify the function that raised a log message.
%
% Walks dbstack and returns the first frame that belongs to neither the eplog
% package nor vprintf itself. The old logger hardcoded frame index 3, which
% assumed exactly "caller -> vprintf -> logmessage". That assumption broke in
% three real cases:
%
%   * exception logging, which recursed through vprintf and so recorded
%     vprintf's own line number instead of the catch site
%   * call sites inside anonymous functions or cellfun bodies
%   * calls typed at the command window, where the stack is shorter
%
% Scanning by file makes the depth irrelevant, so wrappers added later cannot
% silently mis-attribute every line in the log. A fourth case arrived with the
% stimgen log bridge, which adds two frames of its own between the call site
% and this function.
%
% Returns:
%   name - calling function name, 'base' when called from the command window
%   line - line number within that function, 0 when unknown
%   file - full path of that function's file, '' when unknown
%
% See also: eplog.Logger, vprintf

name = 'base';
line = 0;
file = '';

st = dbstack('-completenames');

% st(1) is callerFrame itself.
for k = 2:numel(st)
    if localIsLoggerFile(st(k).file), continue; end
    name = st(k).name;
    line = st(k).line;
    file = st(k).file;
    return
end

% Every frame belonged to the logger: the call came straight from the command
% window or from a script the stack does not name. Fall back to the outermost
% logger frame rather than reporting nothing.
if numel(st) >= 2
    name = st(end).name;
    line = st(end).line;
    file = st(end).file;
end
end


function tf = localIsLoggerFile(f)
persistent pkgMark vpName bridgeName
if isempty(pkgMark)
    pkgMark    = [filesep '+eplog' filesep];
    vpName     = [filesep 'vprintf.m'];
    % stimbridge.LogBridge forwards stimgen's messages into this logger, so it
    % sits between stimgen.util.vprintf and eplog.Logger.emit. Without this
    % marker every one of stimgen's ~100 call sites would be attributed to
    % LogBridge.emit at a fixed line -- the whole caller column, silently lost.
    bridgeName = [filesep 'LogBridge.m'];
end
tf = ~isempty(f) && (contains(f,pkgMark) || endsWith(f,vpName) || endsWith(f,bridgeName));
end
