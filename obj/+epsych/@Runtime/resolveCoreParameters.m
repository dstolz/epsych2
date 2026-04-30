function resolveCoreParameters(obj, subjectIdx)
% resolveCoreParameters(obj, subjectIdx)
% Locate and cache mandatory trigger parameters for one subject.
%
% Searches for the NewTrial, ResetTrig, and TrialComplete trigger parameters
% scoped to the subject's box and stores them in obj.CORE(subjectIdx).
% Errors immediately if any required trigger is missing.
%
% Parameters:
%   obj                           Runtime state object.
%   subjectIdx (1,1) double       Index of the subject to resolve.
%
% Returns:
%   None. Populates obj.CORE(subjectIdx).NewTrial, .ResetTrig, and .TrialComplete.

arguments
    obj (1,1) epsych.Runtime
    subjectIdx (1,1) double {mustBeInteger,mustBePositive}
end

bmn = ["NewTrial","ResetTrig","TrialComplete"];
for cc = bmn
    trigStr = sprintf('_%s~%d', cc, obj.TRIALS(subjectIdx).Subject.BoxID);
    p = obj.find_parameter(trigStr, includeInvisible=true, silenceParameterNotFound=true);

    if isempty(p)
        error('epsych:RunExpt:MissingTrigger', ...
            'Failed to find trigger parameter "%s" for box %d. Check that your protocol includes the required triggers.', ...
            trigStr, obj.TRIALS(subjectIdx).Subject.BoxID);
    end

    obj.CORE(subjectIdx).(cc) = p;
end

end
