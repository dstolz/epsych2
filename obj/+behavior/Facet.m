classdef Facet
    % f = behavior.Facet(kind)
    % f = behavior.Facet("tag", Index = 1)
    % f = behavior.Facet("manual", Name = "Treatment")
    % One way of grouping sessions: the group-by, color-by or x-axis of a
    % comparison.
    %
    % A Facet names WHICH property of a session puts it in a group, and turns
    % a sessions (or results) table into one label per row. Every consumer --
    % the Compare view, behavior.Aggregate, behavior.Plot, behavior.Stats,
    % the exports and a generated script -- groups through values(), so a
    % session lands in the same group wherever it is shown, and a facet is
    % written down as short text (toText/fromText) that a project file and a
    % script both carry.
    %
    %   f = behavior.Facet.fromText("tag:1");
    %   g = f.values(T);              % "Pre", "Post", "(none)", ...
    %   [levels, idx] = f.order(T);   % the groups in display order
    %
    % Kinds (Kind, and its text):
    %   none            "none"            every row in one group, "(all)"
    %   project         "project"         T.Project
    %   projectpath     "projectpath"     T.ProjectPath ("(root)" when "")
    %   subject         "subject"         T.Subject
    %   tag             "tag:k"           the k-th filename tag
    %   tags            "tags"            all tags joined with "_"
    %   sex, species    "sex", "species"  T.SubjectSex, T.SubjectSpecies
    %   paradigm        "paradigm"        T.Paradigm
    %   protocolversion "protocolversion" T.ProtocolVersion
    %   box             "box"             T.BoxID
    %   date            "date"            yyyy-MM-dd of T.Start
    %   week            "week"            ISO 8601 week, yyyy-'W'ww (2026-W41)
    %   month, year     "month", "year"   yyyy-MM, yyyy
    %   session         "session"         the session's ordinal within its
    %                                     subject, by Start (1, 2, ...)
    %   manual          "manual:<Name>"   T.Group_<Name>, a named grouping
    %
    % A row with nothing to say -- a missing tag position, an empty field,
    % an unassigned subject, an undated session -- is "(none)", never "".
    %
    % The session ordinal counts a SUBJECT's sessions across projects, since
    % a subject that moved from one study to the next is still one animal
    % learning one task.
    %
    % Documentation: documentation/behavior/behavior_Classes.md
    % See also: behavior.Catalog, behavior.Session

    properties (Constant)
        Kinds (1,:) string = ["none" "project" "projectpath" "subject" "tag" "tags" ...
            "sex" "species" "paradigm" "protocolversion" "box" "date" "week" ...
            "month" "year" "session" "manual"]
        NONE (1,1) string = "(none)"
    end

    properties (SetAccess = immutable)
        Kind (1,1) string = "none"
        Index (1,1) double = 0      % tag position (Kind "tag")
        Name (1,1) string = ""      % grouping name (Kind "manual")
    end

    methods
        function obj = Facet(kind, options)
            % f = behavior.Facet(kind, Index = k, Name = name)
            arguments
                kind (1,1) string = "none"
                options.Index (1,1) double = 0
                options.Name (1,1) string = ""
            end
            kind = lower(strtrim(kind));
            if ~ismember(kind, behavior.Facet.Kinds)
                error('behavior:Facet:UnknownKind', 'There is no facet "%s".', kind);
            end
            obj.Kind = kind;
            switch kind
                case "tag"
                    if ~(options.Index >= 1 && options.Index == fix(options.Index))
                        error('behavior:Facet:InvalidIndex', ...
                            'A tag facet needs a tag position of 1 or more (Index).');
                    end
                    obj.Index = options.Index;
                case "manual"
                    if strtrim(options.Name) == ""
                        error('behavior:Facet:InvalidName', ...
                            'A manual facet needs the name of a grouping (Name).');
                    end
                    obj.Name = strtrim(options.Name);
            end
        end

        function v = values(obj, T)
            % v = values(obj, T)
            % One group label per row of a sessions or results table.
            %
            % Parameters:
            %   T - table with (as the kind needs) Project, ProjectPath,
            %       Subject, Tags or TagText, SubjectSex, SubjectSpecies,
            %       Paradigm, ProtocolVersion, BoxID, Start, Key,
            %       Group_<Name>
            %
            % Returns:
            %   v - string column, height(T) rows; "(none)" for no value
            n = height(T);
            none = behavior.Facet.NONE;
            switch obj.Kind
                case "none"
                    v = repmat("(all)", n, 1);
                case "project"
                    v = localText(T.Project);
                case "projectpath"
                    v = string(T.ProjectPath);
                    v(v == "") = "(root)";
                case "subject"
                    v = localText(T.Subject);
                case "tag"
                    tags = localTags(T);
                    v = repmat(none, n, 1);
                    for i = 1:n
                        if numel(tags{i}) >= obj.Index
                            v(i) = tags{i}(obj.Index);
                        end
                    end
                case "tags"
                    tags = localTags(T);
                    v = repmat(none, n, 1);
                    for i = 1:n
                        if ~isempty(tags{i})
                            v(i) = strjoin(tags{i}, "_");
                        end
                    end
                case "sex"
                    v = localText(T.SubjectSex);
                case "species"
                    v = localText(T.SubjectSpecies);
                case "paradigm"
                    v = localText(T.Paradigm);
                case "protocolversion"
                    v = localText(T.ProtocolVersion);
                case "box"
                    b = double(T.BoxID);
                    v = string(b);
                    v(~isfinite(b)) = none;
                case "date"
                    v = localDate(T.Start, 'yyyy-MM-dd');
                case "week"
                    v = localWeek(T.Start);
                case "month"
                    v = localDate(T.Start, 'yyyy-MM');
                case "year"
                    v = localDate(T.Start, 'yyyy');
                case "session"
                    v = string(behavior.Facet.sessionOrdinal(T));
                    v(v == "NaN") = none;
                case "manual"
                    col = "Group_" + matlab.lang.makeValidName(obj.Name);
                    if ismember(col, string(T.Properties.VariableNames))
                        v = localText(T.(col));
                    else
                        v = repmat(none, n, 1);
                    end
            end
            v = reshape(v, [], 1);
        end

        function [levels, idx] = order(obj, T)
            % [levels, idx] = order(obj, T)
            % The distinct groups of values(T) in display order -- numbers
            % (box, session) numerically; tags in the order their phases
            % happened (each level by its earliest session's Start, since a
            % tag names a phase and the alphabet would put "Post" before
            % "Pre"); everything else naturally (dates are written so that
            % this is chronological); "(none)" last -- and each row's
            % position in levels.
            v = obj.values(T);
            u = unique(v);
            isNone = u == behavior.Facet.NONE;
            u = u(~isNone);
            if ismember(obj.Kind, ["box" "session"])
                [~, k] = sort(str2double(u));
            elseif ismember(obj.Kind, ["tag" "tags"])
                k = behavior.Facet.chronologicalOrder_(u, v, T);
            else
                [~, k] = sort(behavior.Facet.naturalKey_(u));
            end
            levels = u(k);
            if any(isNone)
                levels(end+1, 1) = behavior.Facet.NONE;
            end
            levels = reshape(levels, [], 1);
            [~, idx] = ismember(v, levels);
        end

        function txt = label(obj)
            % txt = label(obj)
            % What a legend or an axis calls this facet: "Tag 1", "Group:
            % Treatment", "Protocol version", ...
            switch obj.Kind
                case "none",            txt = "All sessions";
                case "project",         txt = "Project";
                case "projectpath",     txt = "Project path";
                case "subject",         txt = "Subject";
                case "tag",             txt = "Tag " + obj.Index;
                case "tags",            txt = "Tags";
                case "sex",             txt = "Sex";
                case "species",         txt = "Species";
                case "paradigm",        txt = "Paradigm";
                case "protocolversion", txt = "Protocol version";
                case "box",             txt = "Box";
                case "date",            txt = "Date";
                case "week",            txt = "Week";
                case "month",           txt = "Month";
                case "year",            txt = "Year";
                case "session",         txt = "Session #";
                case "manual",          txt = "Group: " + obj.Name;
            end
        end

        function tf = isOrdered(obj)
            % tf = isOrdered(obj)
            % Whether the levels run in a meaningful order -- session
            % ordinal and the calendar facets -- so a colour gradient reads
            % as "earlier to later" rather than as an arbitrary ranking.
            tf = ismember(obj.Kind, ["session" "date" "week" "month" "year"]);
        end

        function txt = toText(obj)
            % txt = toText(obj)
            % "tag:1", "manual:Treatment", or the kind itself ("month").
            switch obj.Kind
                case "tag",    txt = "tag:" + obj.Index;
                case "manual", txt = "manual:" + obj.Name;
                otherwise,     txt = obj.Kind;
            end
        end
    end

    methods (Static)
        function f = fromText(s)
            % f = behavior.Facet.fromText(s)
            % The facet toText wrote. Text that names no facet is "none"
            % (logged at debug level): a saved view must still open when a
            % grouping it named has since been removed or renamed.
            arguments
                s (1,1) string
            end
            % The separator is matched inside the token: MATLAB drops a named
            % token that sits in an optional group.
            tok = regexp(strtrim(s), '^(?<kind>[A-Za-z]+)(?<arg>|:.*)$', 'names', 'once');
            try
                if isempty(tok)
                    error('behavior:Facet:UnknownKind', 'unreadable');
                end
                kind = lower(string(tok.kind));
                arg = regexprep(string(tok.arg), '^:', '');
                switch kind
                    case "tag"
                        f = behavior.Facet("tag", Index = str2double(arg));
                    case "manual"
                        f = behavior.Facet("manual", Name = arg);
                    otherwise
                        if strlength(arg) > 0
                            error('behavior:Facet:UnknownKind', 'unexpected argument');
                        end
                        f = behavior.Facet(kind);
                end
            catch ME
                vprintf(2, 'behavior.Facet: "%s" names no facet (%s); using "none"', s, ME.message)
                f = behavior.Facet("none");
            end
        end

        function F = available(T, groupingNames)
            % F = behavior.Facet.available(T, groupingNames)
            % Every facet worth offering for a sessions table: the fixed
            % kinds, one tag facet per tag position any session has, and one
            % manual facet per named grouping.
            %
            % Parameters:
            %   T             - sessions table (NumTags, or Tags/TagText)
            %   groupingNames - string array of grouping names (default none)
            %
            % Returns:
            %   F - (1,:) behavior.Facet
            arguments
                T table
                groupingNames string = strings(1, 0)
            end
            fixed = ["none" "project" "projectpath" "subject" "tags" "sex" "species" ...
                "paradigm" "protocolversion" "box" "date" "week" "month" "year" "session"];
            if ismember("NumTags", string(T.Properties.VariableNames))
                maxTags = max([0; double(T.NumTags)]);
            else
                maxTags = max([0; cellfun(@numel, localTags(T))]);
            end
            groupingNames = reshape(groupingNames, 1, []);

            nf = numel(fixed);
            F = repmat(behavior.Facet(), 1, nf + maxTags + numel(groupingNames));
            for k = 1:nf
                F(k) = behavior.Facet(fixed(k));
            end
            for k = 1:maxTags
                F(nf + k) = behavior.Facet("tag", Index = k);
            end
            for k = 1:numel(groupingNames)
                F(nf + maxTags + k) = behavior.Facet("manual", Name = groupingNames(k));
            end
        end

        function n = sessionOrdinal(T)
            % n = behavior.Facet.sessionOrdinal(T)
            % Each row's position among its subject's sessions, by Start
            % (ties by Key), NaN for an undated session.
            n = nan(height(T), 1);
            subj = string(T.Subject);
            start = T.Start;
            if ismember("Key", string(T.Properties.VariableNames))
                key = lower(string(T.Key));
            else
                key = strings(height(T), 1);
            end
            for s = reshape(unique(subj), 1, [])
                rows = find(subj == s & ~isnat(start));
                if isempty(rows), continue, end
                K = table(start(rows), key(rows), 'VariableNames', {'T', 'K'});
                [~, k] = sortrows(K, {'T', 'K'});
                n(rows(k)) = 1:numel(rows);
            end
        end
    end

    methods (Static, Access = private)
        function k = chronologicalOrder_(u, v, T)
            % Levels by the earliest Start of a row carrying each, undated
            % levels after the dated ones, ties and the undated in natural order.
            n = numel(u);
            first = inf(n, 1);
            if ismember("Start", string(T.Properties.VariableNames)) && isdatetime(T.Start)
                t = reshape(T.Start, [], 1);
                for i = 1:n
                    ti = t(v == u(i) & ~isnat(t));
                    if ~isempty(ti)
                        first(i) = posixtime(min(ti));
                    end
                end
            end
            [~, nk] = sort(behavior.Facet.naturalKey_(u));
            rank = zeros(n, 1);
            rank(nk) = 1:n;
            [~, k] = sortrows([first rank]);
        end

        function k = naturalKey_(s)
            % Digit runs zero-padded so "Rat 9" sorts before "Rat 10"; case
            % ignored (as behavior.Catalog sorts subjects).
            k = string(regexprep(cellstr(lower(string(s))), '(\d+)', '${pad($1,24,''left'',''0'')}'));
            k = reshape(k, size(s));
        end
    end
end




function v = localText(x)
% A column as text, "(none)" where it is empty or missing.
v = string(x);
v = reshape(v, [], 1);
v(ismissing(v) | strtrim(v) == "") = behavior.Facet.NONE;
end




function v = localDate(t, fmt)
v = string(t, fmt);
v = reshape(v, [], 1);
v(isnat(t(:)) | ismissing(v)) = behavior.Facet.NONE;
end




function tags = localTags(T)
% Each row's tags as a (1,:) string: the Tags cell column a catalog carries,
% else TagText split at "_".
n = height(T);
tags = cell(n, 1);
if ismember("Tags", string(T.Properties.VariableNames))
    c = T.Tags;
    for i = 1:n
        if iscell(c)
            t = c{i};
        else
            t = c(i, :);
        end
        t = reshape(string(t), 1, []);
        tags{i} = t(~ismissing(t) & t ~= "");
    end
else
    for i = 1:n
        t = string(T.TagText(i));
        if t == "" || ismissing(t)
            tags{i} = strings(1, 0);
        else
            tags{i} = split(t, "_")';
        end
    end
end
end




function v = localWeek(t)
% ISO 8601 week, "2026-W41". datetime formats have no week-of-year symbol,
% so it is built from week(t,'iso-weekofyear') and the ISO week-year: the
% year of the week's Thursday, which is what keeps 2026-12-31 (a Thursday
% of week 53) and 2027-01-01 in one week.
t = reshape(t, [], 1);
isoDay = mod(weekday(t) - 2, 7) + 1;              % Monday 1 ... Sunday 7
thursday = t + days(4 - isoDay);
v = compose("%04d-W%02d", year(thursday), week(t, 'iso-weekofyear'));
v(isnat(t)) = behavior.Facet.NONE;
end
