function x = extra_(Data, info)
% x = behavior.Catalog.extra_(Data, info)
%
% Everything the catalog needs from inside a session beyond
% epsych.SessionFiles.summarize's row, computed from the Data and normalized
% snapshot that summarize already loaded (its Extra callback), so a session is
% opened once per scan:
%
%   Fields        - (1,:) string, the trial records' fields
%   Candidates    - table Field/Class/NumUnique/IsParameter: numeric scalar
%                   fields that are not bookkeeping, snapshot parameters first,
%                   then by how many distinct values they take on stimulus
%                   (TrialType 0) trials
%   Outcome       - counts of Hit, Miss, CorrectReject, FalseAlarm, Abort
%                   (epsych.BitMask.decode of RespCode)
%   TrialTypes    - table TrialType/Count: the TrialType field where a record
%                   has one, else the TrialType_k bit of its RespCode
%   NumTest       - records flagged isTest
%   SubjectName, SubjectSex, SubjectSpecies, SubjectWeight - from the
%                   snapshot's subject ("" / NaN when the file has none)
%   ParameterMeta - table Field/Name/Unit/Min/Max/Type/Interface/Module: every
%                   parameter in the snapshot's protocol, Field being the DATA
%                   field it is saved under (matlab.lang.makeValidName)
%
% See also: behavior.Catalog.describeFile_, epsych.SessionFiles.summarize

x = behavior.Catalog.blankExtra_();
Data = reshape(Data, 1, []);
n = numel(Data);

if isstruct(Data)
    x.Fields = reshape(string(fieldnames(Data)), 1, []);
end

% --- Subject -------------------------------------------------------------
subj = info.Subject;
x.SubjectName = localText(subj, 'Name');
x.SubjectSex = localText(subj, 'Sex');
x.SubjectSpecies = localText(subj, 'Species');
try
    w = double(subj.Weight);
    if isscalar(w), x.SubjectWeight = w; end
catch
end

x.ParameterMeta = behavior.Session.parameterTable(info.Protocol);   % the one parser

% --- Outcomes and trial types --------------------------------------------
rc = localNumeric(Data, 'RespCode', x.Fields);
scored = ~isnan(rc);
[M, N] = epsych.BitMask.decode(rc(scored));
for f = string(fieldnames(x.Outcome))'
    x.Outcome.(f) = double(N.(f));
end

tt = localNumeric(Data, 'TrialType', x.Fields);
fromBits = nan(n, 1);
idx = find(scored);
for k = 0:5
    hit = M.(sprintf('TrialType_%d', k));
    fromBits(idx(hit & isnan(fromBits(idx)))) = k;
end
tt(isnan(tt)) = fromBits(isnan(tt));

known = tt(~isnan(tt));
if ~isempty(known)
    [u, ~, g] = unique(known);
    x.TrialTypes = table(u, accumarray(g, 1), 'VariableNames', {'TrialType', 'Count'});
end

x.NumTest = sum(localNumeric(Data, 'isTest', x.Fields) > 0);

% --- Candidate parameters --------------------------------------------------
% behavior.Session.candidates is the one rule, shared with the analysis.
x.Candidates = behavior.Session.candidates(Data, x.ParameterMeta);

end




function [v, cls] = localNumeric(Data, f, fields)
% [v, cls] = localNumeric(Data, f, fields)
%
% A field as a column of doubles, NaN where a record's value is empty or not a
% numeric/logical scalar. cls is the class of the first usable value, or ""
% when the field is absent or some record holds something that is not a
% numeric scalar (a vector, text, a struct): such a field cannot be a staircase
% level or a response code.

n = numel(Data);
v = nan(n, 1);
cls = "";
if ~ismember(f, fields), return, end

usable = true;
for k = 1:n
    val = Data(k).(f);
    if isempty(val), continue, end
    if (isnumeric(val) || islogical(val)) && isscalar(val)
        v(k) = double(val);
        if cls == "", cls = string(class(val)); end
    else
        usable = false;
    end
end
if ~usable, cls = ""; end

end




function t = localText(s, name)
% Text from a field of a struct or a property of an object, "" when there is
% none: a snapshot's Subject is an epsych.Subject, a struct, or [].
t = "";
try
    v = s.(name);
    if (ischar(v) || isstring(v)) && ~isempty(v)
        t = string(v(1,:));
    end
catch
end
end
