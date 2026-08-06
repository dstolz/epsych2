function [tf, name] = isVarRef(value)
% [tf, name] = teensy.isVarRef(value)
% Test whether a value is an "@Name" reference to a teensy.Variable.
%
% Numeric fields in the teensy model may hold either a literal double or a
% reference to a teensy.Variable written as "@Name". This function is the single
% place that decides which of the two a value is, so the model classes, the
% compiler, the simulator and the GUI never disagree about a field's meaning.
%
% Parameters
%   value - Any value. Only a char row vector or a scalar string can be a
%       reference; everything else is a literal.
%
% Returns
%   tf   - true when value is a well-formed "@Name" reference.
%   name - Referenced variable name without the leading "@", or "" when tf is
%       false.
%
% Example
%   [tf, name] = teensy.isVarRef("@HoldTime");   % tf = true,  name = "HoldTime"
%   tf = teensy.isVarRef(2.5);                   % tf = false
%   tf = teensy.isVarRef("@2bad");               % tf = false (not an identifier)
%
% See also: teensy.varRef, teensy.Variable

arguments
    value = []
end

tf = false;
name = "";

if ~(ischar(value) || isstring(value))
    return
end

if ischar(value) && ~isempty(value) && ~isrow(value)
    return
end

s = string(value);
if ~isscalar(s) || strlength(s) < 2 || ~startsWith(s, "@")
    return
end

candidate = extractAfter(s, 1);
if ~isvarname(char(candidate))
    return
end

tf = true;
name = candidate;
