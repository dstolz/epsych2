function close_interface(obj)
% close_interface(obj)
% Abort any running matrix, drive every output low, and release the serial port.
%
% This is an animal-welfare path, not just cleanup: the firmware resets valves,
% PWM, BNC and wire outputs ONLY on a clean matrix end or on 'X', so a session
% that errors mid-trial leaves a valve energized until something forces it low.
% It is reached from disconnect(), from RunExpt's close request, and from
% delete(), and it must therefore be safe to call twice, safe when the interface
% never connected, and safe when the serialport handle is already dead.
%
% Every step runs in its own try/catch for the same reason: a failure to abort
% must not skip the step that closes the valves, and a failure to close the
% valves must not skip releasing the port.
%
% Parameters:
%   obj - hw.Bpod instance to shut down.
%
% See also: documentation/hw/hw_Bpod.md, hw.Bpod.abortMatrix, hw.Bpod.writeOutputs_

% How long to spend swallowing the device's post-abort burst, and how long the
% line must stay quiet before we call it drained. Both are bounded: this runs on
% the way out, but it still runs on the MATLAB thread.
DRAIN_SECONDS = 0.25;
QUIET_SECONDS = 0.05;

if obj.linkReady_
    % --- 1. Abort any live matrix ----------------------------------------
    try
        obj.abortMatrix();
    catch ME
        vprintf(0, 1, ME);
    end

    % --- 2. Drain the burst 'X' provokes ----------------------------------
    % In the firmware, `if (MatrixFinished)` sits OUTSIDE
    % `if (RunningStateMatrix)`, so an aborted trial still emits the full
    % sentinel + 10-byte epilogue header + timestamp block. Left in the driver's
    % buffer it would be parsed as opcodes by whoever opens the port next.
    try
        local_drainBurst(obj, DRAIN_SECONDS, QUIET_SECONDS);
    catch ME
        vprintf(0, 1, ME);
    end

    % --- 3. Force every output low ----------------------------------------
    % Absolute masks, never Bpod's toggle-based ManualOverride: after an abort
    % the host cannot know what the device toggled last.
    try
        obj.resetShadow_();
        obj.writeOutputs_(Force = true);
    catch ME
        vprintf(0, 1, ME);
    end

    % --- 4. Tell the firmware the client is gone --------------------------
    % Firmware case 'Z' clears ConnectedToClient, drops the status LED, and
    % replies with the single byte '1' (49). The reply is read only to keep it
    % out of the next session's buffer; its value is not checked, and a timeout
    % here is not worth a warning on a port that is about to close.
    try
        obj.write_(uint8('Z'));
        obj.readExactly_(1, min(obj.Timeout, 0.25));
    catch ME
        vprintf(0, 1, ME);
    end

    vprintf(1, 'Bpod: disconnected from %s', obj.Port);
end

% --- Release ------------------------------------------------------------
% linkReady_ goes down first so nothing that runs during teardown (a listener,
% a queued pump) can issue another transaction on a closing port.
obj.linkReady_ = false;
obj.matrixRunning_ = false;
obj.awaitingEpilogue_ = false;
obj.pendingEventCount_ = 0;
obj.epiHdr_ = [];
obj.rxBuf_ = uint8([]);

try
    obj.closePort_();
catch ME
    vprintf(0, 1, ME);
end
obj.HW = [];

end


function local_drainBurst(obj, maxSeconds, quietSeconds)
% local_drainBurst(obj, maxSeconds, quietSeconds)
% Read and discard whatever the device is still emitting, until the line has
% been quiet for quietSeconds or maxSeconds have elapsed.
%
% Deliberately does not parse: at this point the trial record is already gone
% and the only goal is an empty receive buffer.
overall = tic;
quiet = tic;
while toc(overall) < maxSeconds
    n = obj.bytesAvailable_();
    if n > 0
        obj.readNow_(n);
        quiet = tic;
    elseif toc(quiet) >= quietSeconds
        return
    else
        pause(0.005);
    end
end
end
