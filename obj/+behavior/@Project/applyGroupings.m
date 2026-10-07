function T = applyGroupings(P, T)
% T = applyGroupings(P, T)
% A sessions table with the project's decisions as columns: one
% Group_<matlab.lang.makeValidName(Name)> string column per grouping (the
% session's own override, else its subject's level, else "(none)"), plus
% Hidden (logical), Window (the override text, "" = the settings' window)
% and Comment (the session's comment). Columns of those names already in T
% are replaced. This is what behavior.Facet's "manual:<Name>" kind reads.
%
% Parameters:
%   T - table with Key and Subject columns (behavior.Catalog.Sessions, or
%       any table derived from it)
%
% Returns:
%   T - T with the columns added, rows in the same order

arguments
    P
    T table
end

n = height(T);
keys = behavior.Project.normKey_(reshape(string(T.Key), [], 1));
subjects = behavior.Project.normKey_(reshape(string(T.Subject), [], 1));

for g = 1:numel(P.Groupings)
    G = P.Groupings(g);
    v = repmat(behavior.Facet.NONE, n, 1);
    if ~isempty(G.Subjects)
        [in, loc] = ismember(subjects, behavior.Project.normKey_([G.Subjects.Subject]));
        levels = [G.Subjects.Level];
        v(in) = levels(loc(in));
    end
    if ~isempty(G.Sessions)
        [in, loc] = ismember(keys, behavior.Project.normKey_([G.Sessions.Key]));
        levels = [G.Sessions.Level];
        v(in) = levels(loc(in));
    end
    T.(behavior.Project.groupColumn_(G.Name)) = v;
end

[in, loc] = ismember(keys, behavior.Project.normKey_(P.Sessions.Key));
hidden = false(n, 1);
window = strings(n, 1);
comment = strings(n, 1);
hidden(in) = P.Sessions.Hidden(loc(in));
window(in) = P.Sessions.Window(loc(in));
comment(in) = P.Sessions.Comment(loc(in));
T.Hidden = hidden;
T.Window = window;
T.Comment = comment;

end
