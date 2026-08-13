function tf = isTransientControl(P)
% tf = hw.Parameter.isTransientControl(P)
% Report whether a parameter holds transient session-control state rather than
% experiment configuration, and so must not be restored from a saved phase.
%
% Two kinds qualify:
%   - Triggers (isTrigger). A trigger fires; its value is an artifact of the
%     last firing, not a setting.
%   - Writable Boolean parameters the trial dispatcher never refreshes
%     (UpdateEveryTrial == false and SetOnce == false). These are the
%     operator's live toggles and
%     momentary buttons -- Deliver Trials, Reminder, Shape, Observe, Pellet.
%     Restoring one re-asserts a button press from whenever the phase was
%     saved: a phase saved mid-session with "Deliver Trials" active would
%     start delivering trials the moment it loads.
%
% The UpdateEveryTrial term is what separates a control toggle from a genuine
% Boolean setting. A parameter the dispatcher DOES refresh (e.g.
% RepeatDelayOnAbort) is overwritten from the trial table on the next trial
% regardless, so its saved value is design state and restoring it is both
% meaningful and safe. The same reasoning covers SetOnce parameters: the
% dispatcher writes them from the trial table at session start, so their saved
% value is a deliberate setting, not a button press. A parameter the
% dispatcher never touches keeps whatever
% it is given, which is precisely why restoring it is not safe. Non-Boolean
% types are never treated as transient, so a one-time numeric setup value
% (a filter cutoff, a gain) still travels with the phase.
%
% That inference is a default, not a law: a session toggle the operator sets
% once and leaves set (CatchTrialsEnabled, the "Present Catch Trials"
% checkbox) is a setting the dispatcher happens not to own, and it looks
% identical to a momentary button from here. PersistWithPhase is how such a
% parameter declares itself, and it overrides the inference. Triggers are
% still transient regardless -- a trigger's value is the residue of the last
% firing, so there is nothing there worth saving.
%
% Parameters:
%   P - hw.Parameter handle, or a struct produced by hw.Parameter.toStruct
%       (as parsed from a phase file by epsych.Runtime.phaseParameterData).
%
% Returns:
%   tf - True when the parameter's Value must be left to the live session.
%
% See also: epsych.Runtime.readParameters, epsych.Runtime.writeParametersProtocol

if P.isTrigger
    tf = true;
    return
end

% Legacy structs predate UpdateEveryTrial (and SetOnce, and PersistWithPhase);
% assume the dispatcher refreshes the parameter, which restores the
% pre-existing behavior for those files.
updateEveryTrial = true;
setOnce = false;
persistWithPhase = false;
if isstruct(P)
    if isfield(P, 'UpdateEveryTrial')
        updateEveryTrial = logical(P.UpdateEveryTrial);
    end
    if isfield(P, 'SetOnce')
        setOnce = logical(P.SetOnce);
    end
    if isfield(P, 'PersistWithPhase')
        persistWithPhase = logical(P.PersistWithPhase);
    end
else
    updateEveryTrial = P.UpdateEveryTrial;
    setOnce = P.SetOnce;
    persistWithPhase = P.PersistWithPhase;
end

tf = isequal(char(string(P.Type)), 'Boolean') && ~updateEveryTrial && ~setOnce ...
    && ~persistWithPhase;

end
