function C = candidates(Data, ParameterMeta)
% C = behavior.Session.candidates(Data, ParameterMeta)
% The fields of a session's trial records that could be its staircase
% parameter, best first.
%
% THE one rule: behavior.Catalog's scan calls it on every file, and the
% analysis takes the first row when Settings.Parameter is "". A candidate is
% a field whose values are numeric scalars (a vector, text or a struct in any
% record rules it out), that holds at least one value, and that is not
% bookkeeping -- TrialIndex, TrialID, RespCode, ResponseCode, TrialType,
% isTest, computerTimestamp, inaccurateTimestamp, BoxID, or a staircase's own
% step fields (*_StepOn*). They are ranked snapshot parameters first, then by
% how many distinct values they take on STIMULUS (TrialType 0) trials -- the
% tracked level moves, a fixed setting does not -- or on every trial when the
% session labels none as stimulus trials.
%
% Parameters:
%   Data          - trial records (struct array)
%   ParameterMeta - table with a Field column (behavior.Session.parameterTable
%                   or a Catalog row's), or [] when the session has no
%                   snapshot
%
% Returns:
%   C - table Field (string), Class (string), NumUnique (double),
%       IsParameter (logical), best candidate first
%
% See also: behavior.Session.resolveParameter, behavior.Catalog

Data = reshape(Data, 1, []);
n = numel(Data);
fields = behavior.Session.fieldsOf_(Data);

if isempty(ParameterMeta)
    parFields = strings(0, 1);
else
    parFields = string(ParameterMeta.Field);
end

bookkeeping = ["TrialIndex" "TrialID" "RespCode" "ResponseCode" "TrialType" ...
    "isTest" "computerTimestamp" "inaccurateTimestamp" "BoxID"];

tt = reshape(behavior.Session.trialTypes_(Data), [], 1);
stimulus = tt == 0;
if ~any(stimulus), stimulus = true(n, 1); end

list = reshape(fields(~ismember(fields, bookkeeping) & ~contains(fields, "_StepOn")), [], 1);
nf = numel(list);
usable = false(nf, 1);
cls = strings(nf, 1);
nu = zeros(nf, 1);
for j = 1:nf
    [v, cls(j)] = behavior.Session.numeric_(Data, list(j), fields);
    usable(j) = cls(j) ~= "" && any(~isnan(v));
    vs = v(stimulus);
    nu(j) = numel(unique(vs(~isnan(vs))));
end
list = list(usable);
isPar = ismember(list, parFields);
C = table(list, cls(usable), nu(usable), isPar, ...
    'VariableNames', {'Field','Class','NumUnique','IsParameter'});
C = sortrows(C, {'IsParameter','NumUnique'}, {'descend','descend'});

end
