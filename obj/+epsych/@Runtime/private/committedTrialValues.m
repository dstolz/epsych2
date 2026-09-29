function [committed, perTrial] = committedTrialValues(TRIALS)
% [committed, perTrial] = committedTrialValues(TRIALS)
% The trial table's committed value for each dispatched parameter.
%
% Between trial boundaries the trial table, not the hw.Parameter, holds what a
% dispatched parameter will run next: a deferred commit
% (gui.components.Parameter_Update without the immediate modifier) lands there
% first and dispatch copies it onto the parameter.
%
% Reads subject 1, whose protocol a phase save snapshots (see
% RunExpt.ExptDispatch); subjects sharing that protocol share its parameter
% handles, so there is only one design-time Values list to reconcile anyway.
%
% Returns (both keyed by hw.Parameter validName; empty structs before a run):
%   committed - the column's value, for each writeparam column whose rows all agree
%   perTrial  - true for each column whose rows differ: a parameter managed per
%               trial (e.g. by a staircase trial selector) has no single value
%
% See also: effectiveDesignValue, writeParametersProtocol, readParameters

committed = struct;
perTrial = struct;
if ~(isstruct(TRIALS) && ~isempty(TRIALS) && isfield(TRIALS, 'trials') && isfield(TRIALS, 'writeParamIdx') ...
        && iscell(TRIALS(1).trials) && isstruct(TRIALS(1).writeParamIdx))
    return
end

T = TRIALS(1);
fn = fieldnames(T.writeParamIdx);
for k = 1:numel(fn)
    col = T.trials(:, T.writeParamIdx.(fn{k}));
    if all(cellfun(@(c) isequaln(c, col{1}), col))
        committed.(fn{k}) = col{1};
    else
        perTrial.(fn{k}) = true;
    end
end

end
