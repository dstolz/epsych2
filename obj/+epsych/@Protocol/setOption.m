function setOption(obj, name, value)
% setOption(obj, name, value)
%
% Update a protocol option field.
%
% Parameters:
%   name (char) - Option field name (e.g., 'trialFunc', 'compileAtRuntime')
%   value - New value for the option
arguments
    obj
    name (1,:) char
    value
end

if ~isfield(obj.Options, name)
    vprintf(0, 1, 'Unknown option "%s"', name);
    return
end

obj.Options.(name) = value;
