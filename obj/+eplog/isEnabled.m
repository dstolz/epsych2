function tf = isEnabled(level)
% tf = eplog.isEnabled(level)
% True when a message at this level would be emitted.
%
% This is the single gate for the whole logger, and the only place GVerbosity
% is interpreted. It is deliberately the cheapest thing in the package: on the
% suppressed path -- the common case at production verbosity -- nothing is
% formatted, no timestamp is taken and no record is built.
%
% Guards the global against values that silently broke the old comparison:
%   NaN       - "level > NaN" is always false, so EVERY message printed
%   Inf       - same
%   []        - reset to the documented default of 1
%   [0 3]     - an array made "if" require all elements, suppressing nothing
%
% A non-numeric level returns true rather than false, so a malformed call site
% is loud instead of silently dropping its message forever.
%
% Parameters:
%   level - numeric verbosity level (see eplog.Level)
%
% Returns:
%   tf - logical scalar
%
% See also: visenabled, vprintf, eplog.Level

% The Code Analyzer flags globals, but GVerbosity is EPsych's established
% public control: RunExpt, RunExpt.verbosity and SelfTest.run all set it, and
% stimgen reads the same global. Taking it as an argument instead would break
% every one of those and split the setting in two.
global GVerbosity

v = GVerbosity;
if isempty(v) || ~isnumeric(v) || ~isscalar(v) || isnan(v)
    v = 1;
    GVerbosity = v;
end

if ~isnumeric(level) || ~isscalar(level)
    tf = true;
    return
end

tf = level <= v;
end
