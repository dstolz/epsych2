function [ok, reason] = phaseValueOverridable(S, P)
% [ok, reason] = epsych.Runtime.phaseValueOverridable(S, P)
% Whether a phase entry's value can be replaced for one load
% (readParameters' Override) and still mean what the operator typed.
%
% An override is a single value standing in for the file's, so it only makes
% sense where the parameter would run one fixed value: not one an Expression
% recomputes on every dispatch (set.Value re-evaluates it over whatever was
% written), not one randomized per trial, not one roved over several levels,
% and not a stimulus, buffer, read-only, or session-control parameter.
% gui.components.PhaseSelector greys an editable cell by this rule and
% readParameters refuses an override by it, so the two cannot disagree.
%
% Parameters:
%   S - the phase file's entry for the parameter (hw.Parameter.toStruct
%       shape; a legacy JSON entry may lack Values and Expression)
%   P - the live hw.Parameter it resolves to
%
% Returns:
%   ok     - true when the value can be overridden
%   reason - why not, for the operator; '' when ok
%
% See also: epsych.Runtime.readParameters, gui.selectPhaseParameters

ok = false;
valueTypes = {'Float','Integer','Boolean','String','File'};

S.PersistWithPhase = P.PersistWithPhase;
if strcmp(S.Access, 'Read') || strcmp(P.Access, 'Read')
    reason = 'read-only';
elseif hw.Parameter.isTransientControl(S)
    reason = 'session control: a phase load never sets it';
elseif ~ismember(char(S.Type), valueTypes)
    reason = sprintf('%s parameter', S.Type);
elseif localExpression(S, P)
    reason = 'computed by an expression';
elseif S.isRandom
    reason = 'randomized every trial';
elseif isfield(S, 'Values') && numel(hw.Parameter.normalizeValues(S.Values)) > 1
    reason = sprintf('roved over %d levels', numel(hw.Parameter.normalizeValues(S.Values)));
else
    ok = true;
    reason = '';
end
end


function tf = localExpression(S, P)
% readParameters keeps the live Expression when the file's is empty, so an
% entry without one still ends up expression-driven if the parameter has one.
fileExpr = "";
if isfield(S, 'Expression')
    fileExpr = string(S.Expression);
end
tf = strlength(fileExpr) > 0 || strlength(P.Expression) > 0;
end
