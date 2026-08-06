function sendSoftCode(obj, code)
% sendSoftCode(obj, code)
% Inject a soft event into the running state matrix.
%
% Sends ['V' 'S' code]. The state machine sees it as the event named
% SoftCode<code>, which a state can list in its StateChangeConditions, so this
% is how the host drives a transition from MATLAB - the hook for closed-loop
% stimulus delivery or an experimenter-triggered state change.
%
% The wire byte is ONE-BASED: sendSoftCode(1) produces SoftCode1. Verified in
% the firmware, which maps the byte with
%
%   CurrentEvent = SoftEvent + Ev - 1        with Ev == 28 at that point
%
% (Bpod_MainModule_0_6.ino:424-427; Ev has been advanced past the 16 port, 4
% BNC and 8 wire events). SoftCode1 is event code 28 in the zero-based stream,
% so SoftEvent must be 1. Bpod's own SendBpodSoftCode.m agrees - it writes
% ['VS' Code] with no adjustment. Sending code-1 would emit event 27, which is
% Wire4Low: a silent, plausible-looking wrong transition rather than an error.
%
% There is no reply. The firmware always consumes the two data bytes but only
% acts on them while a matrix is running, so calling this between trials is
% harmless and simply does nothing on the device.
%
% Parameters:
%   obj  - hw.Bpod instance.
%   code - Soft code 1-10, matching the SoftCode1..SoftCode10 event names.
%
% Usage
%   iface.sendSoftCode(3);   % fires SoftCode3 in the running matrix
%
% See also: hw.Bpod.EVENT_NAMES, hw.Bpod.addState, documentation/hw/hw_Bpod.md

arguments
    obj
    code (1,1) double {mustBeInteger, mustBeInRange(code, 1, 10)}
end

if ~obj.linkReady_ || isempty(obj.HW)
    vprintf(0, 1, 'Bpod: cannot send SoftCode%d, the interface is not connected', code);
    return
end

if ~obj.matrixRunning_
    vprintf(2, ['Bpod: SoftCode%d sent with no state matrix running; ' ...
        'the firmware will read the bytes and ignore them'], code);
end

try
    obj.write_(uint8([double('V') double('S') code]));
    vprintf(2, 'Bpod: sent SoftCode%d', code);
catch ME
    vprintf(0, 1, 'Bpod: sending SoftCode%d failed: %s', code, ME.message);
end

end
