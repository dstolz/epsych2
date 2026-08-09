function s = parameterStruct(obj)
% s = parameterStruct(obj)
% Snapshot every parameter as a plain struct of name -> Value.
%
% This is what a state-matrix builder receives: sendStateMatrix calls the
% configured StateMatrixFcn as `sma = f(iface, P)`, so the builder can write
% P.RewardDuration instead of iface.get_parameter('Reward Duration') and stays
% a plain function with no hardware knowledge.
%
% Invisible parameters are included on purpose. Hidden parameters are where the
% immediate-I/O lines and the triggers live (visibility is what keeps them out
% of the trial table), and a builder needs them just as much as the visible
% trial configuration.
%
% Values come from the hw.Parameter objects, not from the device. That is the
% intended reading: the runtime writes the trial's values into the parameters
% before dispatching it, and Bpod cannot be asked for most of them anyway.
%
% Parameters:
%   obj - hw.Bpod instance.
%
% Returns:
%   s - struct with one field per parameter, keyed by hw.Parameter.validName
%       (the display name run through matlab.lang.makeValidName). Empty struct
%       when the interface has no parameters.
%
% Usage
%   P = iface.parameterStruct();
%   sma = feval(iface.StateMatrixFcn, iface, P);
%
% See also: hw.Bpod.sendStateMatrix, hw.Parameter, documentation/hw/hw_Bpod.md

s = struct();

% Access='Read' here means "not write-only" (see hw.Interface.all_parameters),
% which excludes Serial1Byte/Serial2Byte. Those are momentary: writing one
% emits ['H' ch byte] and the device retains nothing to read back, so reading
% them yields NaN and logs a red line once per channel per trial. A builder has
% nothing to gain from a field that is always NaN.
P = obj.all_parameters(includeInvisible = true, Access = 'Read');
if isempty(P)
    return
end

for i = 1:numel(P)
    field = P(i).validName;

    % Two display names can sanitize to the same field ('Reward Dur' and
    % 'Reward_Dur'), and the later one would silently win. Say so: a builder
    % reading the wrong value is invisible at runtime.
    if isfield(s, field)
        vprintf(2, ['Bpod: parameter "%s" maps to field "%s", which is already taken; ' ...
            'the later parameter wins'], P(i).Name, field);
    end

    s.(field) = P(i).Value;
end

end
