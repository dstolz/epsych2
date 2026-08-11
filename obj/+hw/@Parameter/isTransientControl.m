function tf = isTransientControl(P)
% tf = hw.Parameter.isTransientControl(P)
% Report whether a parameter holds transient session-control state rather than
% experiment configuration, and so must not be restored from a saved phase.
%
% Two kinds qualify:
%   - Triggers (isTrigger). A trigger fires; its value is an artifact of the
%     last firing, not a setting.
%   - Writable Boolean parameters the trial dispatcher never refreshes
%     (UpdateEveryTrial == false). These are the operator's live toggles and
%     momentary buttons -- Deliver Trials, Reminder, Shape, Observe, Pellet.
%     Restoring one re-asserts a button press from whenever the phase was
%     saved: a phase saved mid-session with "Deliver Trials" active would
%     start delivering trials the moment it loads.
%
% The UpdateEveryTrial term is what separates a control toggle from a genuine
% Boolean setting. A parameter the dispatcher DOES refresh (e.g.
% RepeatDelayOnAbort) is overwritten from the trial table on the next trial
% regardless, so its saved value is design state and restoring it is both
% meaningful and safe. A parameter the dispatcher never touches keeps whatever
% it is given, which is precisely why restoring it is not safe. Non-Boolean
% types are never treated as transient, so a one-time numeric setup value
% (a filter cutoff, a gain) still travels with the phase.
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

% Legacy structs predate UpdateEveryTrial; assume the dispatcher refreshes the
% parameter, which restores the pre-existing behavior for those files.
updateEveryTrial = true;
if isstruct(P)
    if isfield(P, 'UpdateEveryTrial')
        updateEveryTrial = logical(P.UpdateEveryTrial);
    end
else
    updateEveryTrial = P.UpdateEveryTrial;
end

tf = isequal(char(string(P.Type)), 'Boolean') && ~updateEveryTrial;

end
