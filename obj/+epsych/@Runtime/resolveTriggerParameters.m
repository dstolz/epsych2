function resolveTriggerParameters(obj, subjectIdx)
% resolveTriggerParameters(obj, subjectIdx)
% Locate and cache mandatory trigger parameters for one subject.
%
% Searches for the NewTrial, ResetTrig, and TrialComplete trigger parameters
% scoped to the subject's box and stores them in obj.TRIGGERS(subjectIdx).
% Errors immediately if any required trigger is missing.
%
% Parameters:
%   obj                           Runtime state object.
%   subjectIdx (1,1) double       Index of the subject to resolve.
%
% Returns:
%   None. Populates obj.TRIGGERS(subjectIdx).NewTrial, .ResetTrig, and .TrialComplete.
%
% See also: documentation/epsych/epsych_Runtime.md (Required Triggers section)

arguments
    obj (1,1) epsych.Runtime
    subjectIdx (1,1) double {mustBeInteger,mustBePositive}
end

for cc = obj.REQUIRED_TRIGGERS
    trigStr = sprintf('x_%s_%d', cc, obj.TRIALS(subjectIdx).Subject.BoxID);
    p = obj.find_parameter(trigStr, includeInvisible=true, includeTriggers=true, silenceParameterNotFound=true);

    if isempty(p)
        error('epsych:RunExpt:MissingTrigger', ...
            'Failed to find trigger parameter "%s" for box %d. Check that your protocol includes the required triggers.', ...
            trigStr, obj.TRIALS(subjectIdx).Subject.BoxID);
    end

    % A software trigger nothing has written yet reads back EMPTY:
    % hw.Module.add_parameter fills Values, not Value, so a protocol built
    % in code (or reloaded from a file saved that way) arrives here with no
    % Value at all. ep_TimerFcn_RunTime polls TrialComplete on every tick
    % and an empty read has no truth value, so seed it here -- once, at the
    % one place that already owns the required-trigger contract -- rather
    % than leaving every paradigm to remember. Software only: assigning
    % Value on a hardware-backed parameter would write to the device.
    if isempty(p.Value) && isa(p.Parent, 'hw.Software')
        p.Value = 0;
        vprintf(1, 'Trigger "%s" had no value; seeded to 0 for subject %d', p.Name, subjectIdx);
    end

    vprintf(3, 'Resolved required trigger "%s" for subject %d: parameter "%s"; found on %s - %s', cc, subjectIdx, p.Name, p.Parent.Type, p.Parent.Module.Name);

    obj.TRIGGERS(subjectIdx).(cc) = p;
end

end
