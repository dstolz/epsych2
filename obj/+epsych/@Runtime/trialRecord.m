function data = trialRecord(obj)
% data = trialRecord(obj)
% Read what a completed trial is recorded with: the value of every readable
% parameter, as a struct keyed by each parameter's valid name.
%
% This is the trial-end sweep. With the defaults it is exactly
% all_parameters(Access='Read', asStruct=true, valueOnly=true) -- one backend
% call per interface through a cached hw.ReadPlan -- and the trial loop calls
% it between a trial ending and the next one being dispatched, while the
% subject waits. Two session settings change what it reads and returns, both
% off by default because both change what a saved file holds:
%
%   RecordBuffers = false          'Buffer' and 'Coefficient Buffer'
%       parameters are not read and have no field in the record.
%   RecordStimulusSettings = true  a 'StimType' value is recorded as its
%       settings struct (stimgen.StimType.toStruct) rather than the live
%       object; several stimuli on one parameter become a cell of structs,
%       and a parameter with no stimulus stays [].
%
% Parameters:
%   obj - epsych.Runtime
%
% Returns:
%   data - struct, one field per recorded parameter
%
% See also: epsych.Runtime.all_parameters, hw.ReadPlan, ep_TimerFcn_RunTime

if obj.RecordBuffers && ~obj.RecordStimulusSettings
    data = obj.all_parameters(Access = 'Read', asStruct = true, valueOnly = true);
    return
end

P = obj.all_parameters(Access = 'Read');
types = {P.Type};

if ~obj.RecordBuffers
    keep = ~ismember(types, {'Buffer', 'Coefficient Buffer'});
    P = P(keep);
    types = types(keep);
end

% The same cached plan all_parameters keeps, rebuilt only when the list of
% parameters asked for changes.
plan = obj.ReadPlanCache_;
if isempty(plan) || ~isvalid(plan) || ~plan.matches(P)
    plan = hw.ReadPlan(P);
    obj.ReadPlanCache_ = plan;
end
data = plan.readStruct();

if obj.RecordStimulusSettings
    for k = find(strcmp(types, 'StimType'))
        f = P(k).validName;
        data.(f) = localStimulusSettings(data.(f));
    end
end
end


function s = localStimulusSettings(v)
% The settings of whatever a StimType parameter holds. Anything that is not
% a stimulus object (an empty parameter, a value some backend substituted)
% is recorded as it is.
if isempty(v) || ~isa(v, 'stimgen.StimType')
    s = v;
elseif isscalar(v)
    s = v.toStruct();
else
    s = arrayfun(@(x) x.toStruct(), v, 'UniformOutput', false);
end
end
