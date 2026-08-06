function t = trigger(obj, name)
% t = trigger(obj, name)
% Fire one or more trigger parameters.
%
% Two triggers matter to the runtime, and the order dispatchNextTrial fires
% them in decides what each one may do:
%
%   x_ResetTrig_<BoxID>  fires BEFORE this trial's parameter values are
%                        written, so it only clears the trial record and
%                        resynchronizes the link.
%   x_NewTrial_<BoxID>   fires AFTER them, so this is where the state matrix
%                        is built, uploaded, and started.
%
% Returns:
%   t - Timestamp as a `now` serial date number. hw.Parameter.Trigger
%       assigns this straight into lastUpdated (1,1) double, so a datetime
%       would throw.
%
% See also: epsych.Runtime.dispatchNextTrial, hw.Bpod.sendStateMatrix,
%           documentation/hw/hw_Bpod.md

if isa(name, 'hw.Parameter')
    P = name;
else
    % all_parameters includes triggers by default, so find_parameter needs
    % no extra option here.
    P = obj.find_parameter(name, includeInvisible = true);
end

if isempty(P) || ~obj.IsConnected
    t = now;
    return
end

for i = 1:numel(P)
    wire = hw.Interface.getHardwareParameterName(P(i));

    if strncmp(wire, 'x_ResetTrig_', 12)
        resetTrial_(obj);
    elseif strncmp(wire, 'x_NewTrial_', 11)
        startTrial_(obj);
    else
        % Never throw from a trigger: dispatchNextTrial runs inside a timer
        % callback and an exception here would leave outputs energized.
        vprintf(1, 'hw.Bpod: trigger "%s" has no device action', wire);
    end
end

t = now;
end


% ------------------------------------------------------------------------
function resetTrial_(obj)
% resetTrial_(obj)
% Clear the accumulating trial record and resynchronize with the device.
%
% Deliberately does NOT compile or upload a state matrix. dispatchNextTrial
% fires this trigger before writing the trial's parameter values, so a
% matrix built here would be built from the PREVIOUS trial's values on every
% trial: a one-trial lag that silently corrupts staircases and go/no-go
% stimulus assignment without raising anything.

drainDeviceBurst_(obj);

% Whatever survived the drain is by definition unparseable, and the protocol
% has no resync marker, so it is dropped rather than carried into the next
% trial's event stream.
obj.flushInput_();

obj.rxBuf_ = uint8([]);
obj.epiHdr_ = [];
obj.pendingEventCount_ = 0;
obj.matrixRunning_ = false;
obj.awaitingEpilogue_ = false;
obj.epilogueTic_ = [];

obj.stateCodes_ = [];
obj.stateTimes_ = [];
obj.eventCodes_ = [];
obj.eventTimes_ = [];
obj.lastSoftCode_ = 0;
obj.currentState_ = 0;
obj.trialComplete_ = false;
obj.trialAborted_ = false;
obj.trialTic_ = [];

% Re-assert the output shadow. This flushes any write that set_parameter
% deferred while the last matrix was running, and it also re-establishes
% agreement with the device, which resets valves, PWM, BNC, and wire lines
% by itself at a clean matrix end or on 'X'.
obj.writeOutputs_();
end


% ------------------------------------------------------------------------
function startTrial_(obj)
% startTrial_(obj)
% Build, upload if changed, and start the state matrix. Returns immediately.
%
% Compiling here rather than at x_ResetTrig_ is the whole point of splitting
% the two triggers: dispatchNextTrial orders ResetTrig -> parameter writes ->
% NewTrial, so this is the first moment the parameter table holds this
% trial's values.

if ~obj.usesStateMatrix()
    % Immediate I/O mode. There is no matrix to run, so the host owns trial
    % timing: a custom GUI, a TrialSelector, or FORCE_TRIAL decides when the
    % trial is over. Just stamp the trial and leave the outputs alone.
    obj.trialTic_ = tic;
    obj.trialNum_ = obj.trialNum_ + 1;
    vprintf(3, 'hw.Bpod: trial %d started in immediate I/O mode', obj.trialNum_);
    return
end

sma = buildMatrix_(obj);

% sendStateMatrix owns the whole sequence: validate, permute into manifest
% order, set nStates, publish StateNames, encode, and skip the 'P' upload when
% the payload is byte-identical to the last one. Do not try to pre-compile here
% to decide whether to upload -- compileMatrix_ is pure and reads the PERMUTED
% matrix, so calling it before sendStateMatrix has permuted anything raises
% hw:Bpod:MatrixShapeMismatch on the first trial (nStates is still 0).
obj.sendStateMatrix(sma);

% Clear the completion latch defensively. ResetTrig normally did this, but a
% custom paradigm may fire NewTrial on its own, and a stale true here would
% end the trial on the very next timer tick.
obj.trialComplete_ = false;
obj.trialAborted_ = false;

obj.write_(uint8('R'));

obj.matrixRunning_ = true;
obj.awaitingEpilogue_ = false;
obj.currentState_ = 1;      % the firmware always starts in the first state
obj.trialTic_ = tic;
obj.trialNum_ = obj.trialNum_ + 1;

vprintf(2, 'hw.Bpod: trial %d running (%d states)', obj.trialNum_, numel(obj.StateNames));

% Return now. The device streams the trial to us unsolicited; waiting for it
% here would block the session timer for the length of the trial, which is
% exactly what Bpod's own RunStateMatrix does and why its MATLAB layer is
% not used.
end


% ------------------------------------------------------------------------
function sma = buildMatrix_(obj)
% sma = buildMatrix_(obj)
% Run the configured builder against this trial's parameter values.
%
% The builder signature is `sma = f(iface, P)`, where P is the parameter
% struct read here, after dispatchNextTrial has written this trial's values.

f = str2func(obj.StateMatrixFcn);

try
    sma = f(obj, obj.parameterStruct());
catch ME
    % Log with the trial number before rethrowing: the timer's ErrorFcn
    % stops the session and closes the interface, which drives the outputs
    % low, but it cannot say which builder failed or when.
    vprintf(0, 1, 'hw.Bpod: state matrix builder "%s" failed before trial %d', ...
        obj.StateMatrixFcn, obj.trialNum_ + 1);
    vprintf(0, 1, ME);
    rethrow(ME)
end
end


% ------------------------------------------------------------------------
function drainDeviceBurst_(obj)
% drainDeviceBurst_(obj)
% Consume any end-of-trial burst still in flight, bounded in wall time.
%
% `if (MatrixFinished)` sits outside `if (RunningStateMatrix)` in the
% firmware, so even an 'X' abort produces the full framed sentinel, the
% 10-byte epilogue header, and one uint32 per recorded event. Left in the
% buffer those bytes are read as the next trial's events.
%
% There is no pause or drawnow in this loop on purpose: both process the
% event queue, which can re-enter the session timer callback mid-dispatch.
% The pump is resumable, so a burst only half consumed here is either
% finished by the next tick or discarded with rxBuf_ by the caller.

DRAIN_BUDGET = 0.25;   % seconds; a trial boundary, but still not a place to stall

if ~(obj.matrixRunning_ || obj.awaitingEpilogue_)
    return
end

t0 = tic;
while (obj.matrixRunning_ || obj.awaitingEpilogue_) && toc(t0) < DRAIN_BUDGET
    obj.pump();
end

if obj.matrixRunning_ || obj.awaitingEpilogue_
    vprintf(1, ['hw.Bpod: device was still streaming %.0f ms into the trial ' ...
        'boundary; discarding the remainder'], DRAIN_BUDGET * 1000);
end
end
