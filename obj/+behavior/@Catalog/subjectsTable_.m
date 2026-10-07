function T = subjectsTable_(S)
% T = subjectsTable_(S)
%
% One row per (Project, Subject) in the Sessions table S, in its order (S is
% already sorted naturally). Sex and Species are what the subject's files say
% most often, "" when none says anything: the folder tree decides who a
% subject is, the files only describe it.

[g, project, subject] = findgroups(S.Project, S.Subject);
n = numel(project);

numSessions = zeros(n, 1);
first = NaT(n, 1);
last = NaT(n, 1);
sex = strings(n, 1);
species = strings(n, 1);
order = zeros(n, 1);
for i = 1:n
    in = g == i;
    numSessions(i) = sum(in);
    first(i) = min(S.Start(in));
    last(i) = max(S.Start(in));
    sex(i) = localMode(S.SubjectSex(in));
    species(i) = localMode(S.SubjectSpecies(in));
    order(i) = find(in, 1);
end

T = table(subject, project, numSessions, first, last, sex, species, 'VariableNames', ...
    {'Subject','Project','NumSessions','FirstSession','LastSession','Sex','Species'});
[~, k] = sort(order);
T = T(k, :);

end




function m = localMode(v)
% The most frequent non-empty text, "" when there is none.
m = "";
v = v(strlength(v) > 0);
if isempty(v), return, end
[u, ~, g] = unique(v);
[~, k] = max(accumarray(g, 1));
m = u(k);
end
