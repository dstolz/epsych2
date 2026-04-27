function requestRecompile(self, subjectIdx)
% requestRecompile(self, subjectIdx)
% Request that the Protocol for subjectIdx be recompiled at the next safe
% trial boundary.  Safe means: after the current trial completes and before
% the next trial parameters are dispatched to hardware.
%
% Parameters:
%   subjectIdx - (positive integer) 1-based index into CONFIG / RUNTIME.TRIALS.
%                Defaults to 1 when omitted.
%
% Behavior:
%   Sets RUNTIME.TRIALS(subjectIdx).RECOMPILE_REQUESTED = true.
%   ep_TimerFcn_RunTime reads this flag and applies the recompile at the
%   next inter-trial boundary.  If the experiment is not running or the
%   index is out of range, the call is silently ignored.
arguments
    self
    subjectIdx (1,1) {mustBePositive, mustBeInteger} = 1
end

if self.STATE < PRGMSTATE.RUNNING
    vprintf(1, 'requestRecompile: experiment is not running — request ignored.\n')
    return
end

if subjectIdx > self.RUNTIME.NSubjects
    vprintf(0, 1, 'requestRecompile: subjectIdx %d out of range (NSubjects = %d).', ...
        subjectIdx, self.RUNTIME.NSubjects)
    return
end

self.RUNTIME.TRIALS(subjectIdx).RECOMPILE_REQUESTED = true;

vprintf(1, 'Recompile scheduled for subject %d at next trial boundary.\n', subjectIdx)
