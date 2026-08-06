function sma = setGlobalCounter(obj, sma, counterNumber, targetEventName, threshold)
% sma = setGlobalCounter(obj, sma, counterNumber, targetEventName, threshold)
% Attach one of the five global counters to an event and set its threshold.
%
% A faithful transcription of Bpod's
% Functions/State Matrix Assembler/SetGlobalCounter.m, with
% `BpodSystem.EventNames` replaced by hw.Bpod.EVENT_NAMES.
%
% Counters tally an event across ALL states. When the count reaches the
% threshold the firmware raises GlobalCounterN_End, which addState routes
% through GlobalCounterMatrix. Counts reset on every 'R'
% (Bpod_MainModule_0_6.ino:322-324) and can also be cleared mid-trial with
% the 'GlobalCounterReset' output action.
%
% The event is stored as a 1-BASED index into hw.Bpod.EVENT_NAMES.
% compileMatrix_ subtracts 1 to reach the firmware's 0-based event codes, so
% the "no event attached" sentinel is 255 here and 254 on the wire. See
% newStateMatrix for why that distinction matters.
%
% Parameters
%   sma             - State matrix from newStateMatrix.
%   counterNumber   - Counter index, 1-5.
%   targetEventName - Event to count; one of hw.Bpod.EVENT_NAMES.
%   threshold       - Whole number of events that triggers the counter.
%
% Returns:
%   sma - The state matrix with the counter configured.
%
% Usage
%   % counter 1 fires after 5 pokes in port 1, in any state
%   sma = iface.setGlobalCounter(sma, 1, 'Port1In', 5);
%
% See also: hw.Bpod.addState, hw.Bpod.setGlobalTimer, hw.Bpod.sendStateMatrix

arguments
    obj
    sma (1,1) struct
    counterNumber
    targetEventName (1,:) char
    threshold
end

% counterNumber and threshold are left unvalidated above on purpose: a
% `(1,1) double` declaration would CONVERT a char to its code point rather
% than reject it, so setGlobalCounter(sma, 1, 'Port1In', '5') would quietly
% become a threshold of 53. The checks below are Bpod's own.
if ischar(threshold) || isstring(threshold)
    error('hw:Bpod:ThresholdNotNumeric', 'Global counter thresholds must be numbers.');
end
if ~isnumeric(counterNumber) || ~isscalar(counterNumber) || rem(counterNumber, 1) > 0 || counterNumber < 1
    error('hw:Bpod:BadCounterNumber', ...
        'Global counter number must be a positive whole number.');
end
if threshold < 0
    error('hw:Bpod:NegativeThreshold', 'Global counter thresholds must be positive.');
end
if rem(threshold, 1) > 0
    error('hw:Bpod:FractionalThreshold', 'Global counter thresholds must be whole numbers.');
end

nCounters = length(sma.GlobalCounterThresholds);
if counterNumber > nCounters
    error('hw:Bpod:TooManyCounters', ...
        'Only %d global counters are available in the current Bpod version.', nCounters);
end

TargetEventCode = find(strcmp(targetEventName, obj.EVENT_NAMES));
if isempty(TargetEventCode)
    error('hw:Bpod:BadCounterEvent', ...
        'Error setting global counter. Target event ''%s'' is invalid syntax.', targetEventName);
end

sma.GlobalCounterThresholds(counterNumber) = threshold;
sma.GlobalCounterEvents(counterNumber) = TargetEventCode;
sma.GlobalCounterSet(counterNumber) = 1;

vprintf(3, 'Bpod: global counter %d attached to %s, threshold %d', ...
    counterNumber, targetEventName, threshold);
end
