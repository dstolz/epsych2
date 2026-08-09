function s = varRef(name)
% s = teensy.varRef(name)
% Build the "@Name" string that points a numeric field at a teensy.Variable.
%
% Use this instead of hand-assembling "@" strings so the reference syntax stays
% in one place. An already-decorated name is accepted and returned unchanged,
% which makes the function safe to apply twice.
%
% Parameters
%   name - Variable name, with or without a leading "@". Must be a valid MATLAB
%       identifier once the "@" is stripped.
%
% Returns
%   s - Scalar string of the form "@Name".
%
% Example
%   c = teensy.Condition.analogThreshold("Mic", "Above", teensy.varRef("Level"));
%
% See also: teensy.isVarRef, teensy.Variable

arguments
    name (1,1) string
end

name = strtrim(name);
if startsWith(name, "@")
    name = extractAfter(name, 1);
end

if ~isvarname(char(name))
    error('teensy:varRef:InvalidName', ...
        'A variable reference must be a valid MATLAB identifier; got "%s".', name);
end

s = "@" + name;
