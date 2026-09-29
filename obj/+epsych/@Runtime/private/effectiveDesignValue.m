function [v, ok] = effectiveDesignValue(S, committed, perTrial)
% [v, ok] = effectiveDesignValue(S, committed, perTrial)
% The single value a parameter's design-time Values should hold so that a
% recompile reproduces what the session is running now.
%
% No runtime editing path updates Values, yet a recompile regenerates the trial
% table from Values -- so a parameter the operator has edited is reverted at the
% first trial boundary after one unless its Values is brought up to date. A
% phase save does that to the snapshot it writes (writeParametersProtocol); a
% phase load does it to the parameters it was told to leave alone
% (readParameters' Exclude), since the load schedules exactly such a recompile.
%
% The effective value is the committed trial-table value for a dispatched
% (UpdateEveryTrial) parameter, and the current Value otherwise. A parameter
% that cannot carry one committed value gets ok = false: read-only, trigger or
% operator toggle (hw.Parameter.isTransientControl), StimType,
% expression-driven, randomized, multi-level (roved), managed per trial, or with
% no usable value (empty or NaN).
%
% Parameters:
%   S         - a hw.Parameter.toStruct struct, or a live hw.Parameter: every
%               field read here exists on both. A live parameter's Value is read
%               only when the trial table does not supply the answer, and never
%               for a write-only one, whose get.Value has nothing to return.
%   committed - from committedTrialValues
%   perTrial  - from committedTrialValues
%
% Returns:
%   v  - the value Values should hold ({v}); [] when ok is false
%   ok - false when the parameter should be left as it is
%
% See also: committedTrialValues, writeParametersProtocol, readParameters

v = [];
ok = false;

if strcmp(S.Access, 'Read') || S.isRandom ...
        || strcmp(S.Type, 'StimType') ...
        || strlength(string(S.Expression)) > 0 ...
        || numel(S.Values) > 1 ...
        || hw.Parameter.isTransientControl(S)
    return
end

vn = matlab.lang.makeValidName(S.Name);
if isfield(perTrial, vn), return, end

if S.UpdateEveryTrial && isfield(committed, vn)
    v = committed.(vn);
elseif isstruct(S) || ~strcmp(S.Access, 'Write')
    % A struct's Value is already in hand (toStruct stores a write-only
    % parameter's first design level, so reconciling from it is a no-op).
    v = S.Value;
end

ok = ~(isempty(v) || (isnumeric(v) && any(isnan(v(:)))));
if ~ok
    v = [];
end

end
