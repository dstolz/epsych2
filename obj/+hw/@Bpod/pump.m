function pump(obj)
% pump(obj)
% Service the device byte stream once. Public escape hatch for the byte pump.
%
% The pump is what replaces Bpod's blocking RunStateMatrix loop: it drains
% whatever the device has pushed since the last call, decodes complete
% messages, walks the state matrix, and closes the trial when the end-of-trial
% epilogue arrives. It is normally driven implicitly, because get.mode and
% get_parameter both call it and the runtime touches both on every 10 ms tick.
%
% This wrapper exists so that pumping is not *only* an implicit side effect of
% those two reads. A custom gui.BoxGUI that wants to plot events as they arrive,
% a smoke test with no epsych.Runtime, or a future runtime that stops polling
% mode every tick can all drive the trial engine explicitly by calling this.
% Calling it more often than necessary is harmless: the pump is resumable, and
% re-entrant calls are dropped by pump_'s own guard.
%
% Never throws. It runs inside a timer callback, where an exception would stop
% the session with the device mid-trial and its outputs still energized.
%
% Parameters:
%   obj - hw.Bpod instance to service.
%
% See also: hw.Bpod.pump_, hw.Bpod.get_parameter, hw.Bpod.mode

% Offline or half-connected: nothing has been handshaken, so there is no stream
% to drain and no trial to close.
if ~obj.linkReady_
    return
end

try
    obj.pump_();
catch ME
    % pump_ already degrades internally; this is the last barrier between an
    % unexpected transport failure and the session timer.
    vprintf(0, 1, ME);
end

end
