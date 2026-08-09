function resetShadow_(obj)
% resetShadow_(obj)
% Zero the absolute output shadow. Performs no I/O.
%
% The shadow (valves_, pwm_, bncOut_, wireOut_) is this class's model of what
% the output lines should be. Bpod's own ManualOverride is toggle-based and
% keeps its state in a global console GUI, so it is never used; every write
% this class makes carries the complete, absolute mask instead.
%
% Because this touches nothing on the wire it is used in two ways:
%   - Before forcing the device low (resetShadow_ then writeOutputs_(Force=true)),
%     which is what close_interface and delete rely on for animal welfare.
%   - To re-sync the model after the firmware has zeroed the lines by itself.
%     The firmware resets valves, PWM, BNC and wire on a clean matrix end and
%     on 'X', so after either event the truthful shadow is all zeros.
%
% Parameters:
%   obj - hw.Bpod instance.
%
% See also: hw.Bpod.writeOutputs_, hw.Bpod.flushOutputs, documentation/hw/hw_Bpod.md

obj.valves_  = zeros(1, 8);
obj.pwm_     = zeros(1, 8);
obj.bncOut_  = zeros(1, 2);
obj.wireOut_ = zeros(1, 4);

end
