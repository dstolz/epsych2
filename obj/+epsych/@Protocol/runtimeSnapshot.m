function snap = runtimeSnapshot(obj)
% snap = runtimeSnapshot(obj)
%
% Return a runtime execution snapshot from the compiled Protocol. This is
% the only authoritative source of trial data for the RunExpt timer runtime
% path. Parameter identifiers are fully qualified; no prefix stripping
% occurs here or downstream.
%
% Returns:
%   snap - struct with fields:
%     writeparams   {1×M cell}  fully qualified write parameter identifiers
%     readparams    {1×N cell}  fully qualified read parameter identifiers
%     trials        {T×M cell}  trial parameter value matrix
%     ntrials       scalar      total number of trials (rows in trials)
%     writeParamIdx struct      valid MATLAB field name → column index map
%     selectorConfig struct     trialFunc, numReps, randomize, ISI
%
% See also: compile, validate

if obj.COMPILED.ntrials == 0
    error('epsych:Protocol:NotCompiled', ...
        'Protocol must be compiled before requesting a runtime snapshot. Call compile() first.');
end

obj.assertCompiledInvariants_();

snap = struct();
snap.writeparams = obj.COMPILED.writeparams;
snap.readparams  = obj.COMPILED.readparams;
snap.trials      = obj.COMPILED.trials;
snap.ntrials     = obj.COMPILED.ntrials;

snap.writeParamIdx = struct();
for k = 1:length(snap.writeparams)
    fieldName = matlab.lang.makeValidName(snap.writeparams{k});
    snap.writeParamIdx.(fieldName) = k;
end

snap.selectorConfig = struct( ...
    'trialFunc',  obj.Options.trialFunc, ...
    'numReps',    obj.Options.numReps, ...
    'randomize',  obj.Options.randomize, ...
    'ISI',        obj.Options.ISI);
end
