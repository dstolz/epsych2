function tf = isEnabled(level,dest)
% tf = eplog.isEnabled(level)             would this message be emitted anywhere
% tf = eplog.isEnabled(level,'console')   would it reach the command window
% tf = eplog.isEnabled(level,'log')       would it reach the error log
% tf = eplog.isEnabled(level,'any')       either of the above (the default)
%
% The verbosity gate for the whole logger, and the only place the verbosity
% globals are interpreted.
%
% There are two of them, because the command window and the error log answer
% different questions. GVerbosity keeps the console readable, so it stays low
% during a session; GLogVerbosity decides what is on the record afterwards, and
% defaults to Inf so EVERY message is written to the error log regardless of
% what the operator is watching. Turning the console quiet no longer throws
% away the detail that explains a failure after the fact.
%
%   GVerbosity    - console verbosity, an integer normally between -1 and 4
%                   (see eplog.Level). Default 1.
%   GLogVerbosity - error-log verbosity, same scale. Default Inf (log
%                   everything). Lower it to restore the old behaviour where a
%                   suppressed message costs nothing at all.
%
% This is deliberately the cheapest thing in the package: on the suppressed
% path nothing is formatted, no timestamp is taken and no record is built. With
% the default GLogVerbosity nothing is suppressed, so a level-4 trace in a
% per-trial loop now pays for formatting and a file write -- lower
% GLogVerbosity on a rig where that matters.
%
% Guards both globals against values that silently broke the old comparison:
%   NaN       - "level > NaN" is always false, so EVERY message printed
%   []        - reset to the documented default
%   [0 3]     - an array made "if" require all elements, suppressing nothing
% Inf is repaired on GVerbosity, where it meant "print everything including
% trace", but is legal on GLogVerbosity, where it is the documented default.
%
% A non-numeric level returns true rather than false, so a malformed call site
% is loud instead of silently dropping its message forever.
%
% Parameters:
%   level - numeric verbosity level (see eplog.Level)
%   dest  - 'any' (default), 'console' or 'log'
%
% Returns:
%   tf - logical scalar
%
% See also: visenabled, vprintf, eplog.Level, eplog.sink.Sink

% The Code Analyzer flags globals, but these are EPsych's established public
% controls: RunExpt, RunExpt.verbosity and SelfTest.run all set GVerbosity, and
% stimgen reads it through the bridge. Taking them as arguments instead would
% break every one of those and split each setting in two.
global GVerbosity GLogVerbosity

if ~isnumeric(level) || ~isscalar(level)
    tf = true;
    return
end

if nargin < 2 || isempty(dest)
    dest = 'any';
end

% One character is enough to tell the three apart, and everything here is
% inlined rather than factored into per-destination helpers: a MATLAB function
% call costs more than the whole comparison it would wrap.
d = char(dest);
askLog     = d(1) ~= 'c';
askConsole = d(1) ~= 'l';

tf = false;

if askLog
    v = GLogVerbosity;
    % Inf is the documented default here rather than a fault, so only NaN and
    % the shape errors are repaired.
    if isempty(v) || ~isnumeric(v) || ~isscalar(v) || isnan(v)
        v = Inf;
        GLogVerbosity = v;
    end
    tf = level <= v;
end

% Short-circuited on the 'any' path: with the default GLogVerbosity the answer
% is already true and the console global is never touched.
if ~tf && askConsole
    v = GVerbosity;
    % ~isfinite, not isnan: a stray Inf turned every console message on --
    % including stimgen's level-4 buffer traces, once its logging routed here.
    if isempty(v) || ~isnumeric(v) || ~isscalar(v) || ~isfinite(v)
        v = 1;
        GVerbosity = v;
    end
    tf = level <= v;
end
end
