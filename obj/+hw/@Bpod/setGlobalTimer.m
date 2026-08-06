function sma = setGlobalTimer(obj, sma, timerNumber, timerDuration)
% sma = setGlobalTimer(obj, sma, timerNumber, timerDuration)
% Arm one of the five global timers on a state matrix.
%
% A faithful transcription of Bpod's
% Functions/State Matrix Assembler/SetGlobalTimer.m. Global timers run
% independently of states: they are started by a 'GlobalTimerTrig' output
% action and their expiry raises the GlobalTimerN_End event, which addState
% routes through GlobalTimerMatrix rather than InputMatrix.
%
% The duration is stored in SECONDS here and converted to firmware ticks by
% compileMatrix_, which is where the 10 kHz / 1 MHz scaling lives.
%
% Parameters
%   sma           - State matrix from newStateMatrix.
%   timerNumber   - Timer index, 1-5.
%   timerDuration - Duration in seconds, 0 to 3600.
%
% Returns:
%   sma - The state matrix with the timer armed.
%
% Usage
%   sma = iface.setGlobalTimer(sma, 1, 0.025);  % timer 1 fires after 25 ms
%
% See also: hw.Bpod.addState, hw.Bpod.setGlobalCounter, hw.Bpod.sendStateMatrix

arguments
    obj
    sma (1,1) struct
    timerNumber
    timerDuration
end

% Deliberately unvalidated in the arguments block above: declaring these
% `(1,1) double` would let MATLAB CONVERT a char argument to its code point
% instead of rejecting it, turning setGlobalTimer(sma, 1, '5') into a
% 53-second timer. The explicit checks below are Bpod's own.
if ischar(timerDuration) || isstring(timerDuration)
    error('hw:Bpod:TimerNotNumeric', ...
        'Global timer durations must be numbers, in seconds.');
end
if ~isnumeric(timerNumber) || ~isscalar(timerNumber) || rem(timerNumber, 1) > 0 || timerNumber < 1
    error('hw:Bpod:BadTimerNumber', ...
        'Global timer number must be a positive whole number.');
end
if timerDuration < 0
    error('hw:Bpod:NegativeTimer', ...
        'When setting global timers, time (in seconds) must be positive.');
end
if timerDuration > 3600
    error('hw:Bpod:TimerTooLong', 'Global timers can not exceed 1 hour.');
end

nTimers = length(sma.GlobalTimers);
if timerNumber > nTimers
    error('hw:Bpod:TooManyTimers', ...
        'Only %d global timers are available in the current revision.', nTimers);
end

sma.GlobalTimers(timerNumber) = timerDuration;

% Upstream writes GlobalTimersSet (plural) while the blank matrix declares
% GlobalTimerSet (singular), so a matrix that has been through this function
% carries BOTH fields. Preserved verbatim: neither field is read by the
% encoder or the firmware, and "fixing" the name would make matrices built
% here compare unequal to matrices built by Bpod itself.
sma.GlobalTimersSet(timerNumber) = 1;

vprintf(3, 'Bpod: global timer %d armed for %g s', timerNumber, timerDuration);
end
