function held = holdCommittedValues(obj, Parameters)
% held = holdCommittedValues(obj, Parameters)
% Carry just-committed trial values through a pending recompile.
%
% A phase load (or an operator recompile) sets TRIALS.RECOMPILE_REQUESTED, and
% at the next trial boundary ep_TimerFcn_RunTime rebuilds the WHOLE trial
% table from each parameter's design-time Values. No commit path updates
% Values -- gui.components.Parameter_Update and an autoCommit
% gui.components.Parameter_Control write the parameter and its trial-table
% column only -- so an edit committed between the load and that boundary was
% thrown away by the recompile and the next trial ran the old value.
%
% Called by both commit paths after the trial table holds the new value. While
% a recompile is pending, each parameter that can carry one committed value
% has its Values set to it (effectiveDesignValue: the rule a phase save and an
% excluded phase load already apply), so the recompile reproduces the edit.
% With no recompile pending this does nothing: the trial table is then
% authoritative, and leaving Values as the protocol designed them keeps one
% session's edits out of the next Run's compile.
%
% Parameters:
%   obj        - epsych.Runtime instance.
%   Parameters - hw.Parameter array just committed.
%
% Returns:
%   held - the parameters whose Values were brought up to their committed value.
%
% See also: effectiveDesignValue, committedTrialValues, readParameters,
%   gui.components.Parameter_Update, gui.components.Parameter_Control

arguments
    obj
    Parameters hw.Parameter = hw.Parameter.empty(1,0)
end

held = hw.Parameter.empty(1,0);

if isempty(Parameters) || ~isstruct(obj.TRIALS) || isempty(obj.TRIALS) ...
        || ~isfield(obj.TRIALS, 'RECOMPILE_REQUESTED') ...
        || ~any([obj.TRIALS.RECOMPILE_REQUESTED])
    return
end

[committed, perTrial] = committedTrialValues(obj.TRIALS);

for p = Parameters
    if any(strcmp(p.Type, {'Buffer', 'Coefficient Buffer'})), continue, end
    [v, ok] = effectiveDesignValue(p, committed, perTrial);
    if ok && ~isequaln(p.Values, {v})
        p.Values = {v};
        held(end+1) = p;
    end
end

if ~isempty(held)
    vprintf(2, 'Kept %d committed value(s) across the pending recompile: %s', ...
        numel(held), strjoin({held.Name}, ', '))
end
end
