function flushOutputs(obj, options)
% flushOutputs(obj)
% flushOutputs(obj, Force=false)
% Push any deferred output-shadow state to the device.
%
% set_parameter updates the shadow and calls writeOutputs_, which skips groups
% that have not changed and defers entirely while a state matrix is running.
% This is the public way to say "make the hardware match the shadow now",
% used after a trial ends to re-assert manual overrides the firmware zeroed,
% and by GUIs that drive valves or port LEDs directly.
%
% While a matrix is running this is still a no-op even with Force=true: the
% state machine rewrites all four output groups at every transition, so an
% override would survive at most one 100 us tick. The shadow is retained and
% lands at the next call made outside a trial.
%
% Parameters:
%   obj           - hw.Bpod instance.
%   options.Force - logical (default=true). Re-send every group even when it
%                   matches the last write. Pass false to send only changes.
%
% Usage
%   iface.set_parameter('Valve1', true);  % updates the shadow
%   iface.flushOutputs();                 % ... and makes the hardware match
%
% See also: hw.Bpod.writeOutputs_, hw.Bpod.resetShadow_, documentation/hw/hw_Bpod.md

arguments
    obj
    options.Force (1,1) logical = true
end

obj.writeOutputs_(Force = options.Force);

end
