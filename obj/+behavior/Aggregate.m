classdef Aggregate
    % behavior.Aggregate  Tidy tables across sessions, from analysis results.
    %
    % behavior.Session.analyze describes ONE session as a struct. Everything
    % that looks across sessions -- the Table tab, the Compare plots, the
    % export, the generated script's summary -- wants those structs as one
    % table with a row per session, carrying both the numbers and every
    % column a behavior.Facet can group by. That table is built here, and
    % only here, so the GUI, a script and an export cannot disagree about a
    % column's name or meaning:
    %
    %   T = behavior.Aggregate.thresholds(results, catalog.Sessions);
    %   V = behavior.Aggregate.valueColumns();            % what Compare can plot
    %   S = behavior.Aggregate.bySubject(T, "Threshold", GroupBy = behavior.Facet("tag", Index = 1));
    %
    % Everything is static and pure: tables in, tables out, no state, no
    % graphics, no preference. Rows keep the order of the results given.
    %
    % THE JOIN. A result names its session by Key, and the sessions table (a
    % behavior.Catalog's, usually after behavior.Project.applyGroupings) is
    % joined on that key with behavior.Catalog.keyEquals, so the per-session
    % facts a facet reads (Project, Subject, Tags, SubjectSex, Paradigm,
    % Start, Group_<Name>, Hidden, Comment, ...) ride along with the numbers.
    % A result whose key the table lacks -- a session loaded from a bare
    % path -- keeps the identity the result itself carries and leaves the
    % rest empty, so a script over files alone still gets a table.
    %
    % DERIVED COLUMNS. Tag1..TagN (N = the most tags any session has, "(none)"
    % where a session has fewer) make a tag position a plain column for a
    % table view or an export; SessionOrdinal and DaysSinceFirst count each
    % SUBJECT's sessions by Start across the whole table (one animal learning
    % one task), NaN where Start is unknown; Date is Start at midnight.
    %
    % See also: behavior.Session.analyze, behavior.Facet, behavior.Stats,
    %   behavior.Plot, behavior.Export

    properties (Constant)
        % Per-session columns the sessions table contributes when it has them.
        SESSION_COLUMNS = ["Project" "ProjectPath" "Subject" "Tags" "TagText" "NumTags" ...
            "Start" "SubjectSex" "SubjectSpecies" "Paradigm" "ProtocolVersion" "BoxID" ...
            "Trials" "QCFile" "NotesText" "NumNotes" "Hidden" "HiddenReason" "Window" "Comment"]
    end

    methods (Static)
        function T = thresholds(results, sessions)
            % T = behavior.Aggregate.thresholds(results)
            % T = behavior.Aggregate.thresholds(results, sessions)
            % One row per analysis result, joined with the sessions table.
            %
            % Parameters:
            %   results  - struct array or cell array of behavior.Session.analyze
            %              results (an empty one gives the empty table with
            %              every column).
            %   sessions - table with a Key column (behavior.Catalog.Sessions,
            %              optionally through behavior.Project.applyGroupings);
            %              [] or omitted joins nothing.
            %
            % Returns:
            %   T - table, one row per result, in the results' order.
            arguments
                results
                sessions = []
            end

            R = behavior.Aggregate.asStructArray_(results);
            n = numel(R);
            T = behavior.Aggregate.emptyTable_();

            if n > 0
                base = behavior.Aggregate.identityFromResults_(R);
                nums = behavior.Aggregate.numbersFromResults_(R);
                T = [base nums];
                T = behavior.Aggregate.joinSessions_(T, sessions);
                T = behavior.Aggregate.addTagColumns_(T);
                T = behavior.Aggregate.addOrdinals_(T);
            end
        end

        function V = valueColumns()
            % V = behavior.Aggregate.valueColumns()
            % The columns of thresholds() a plot or a summary can be asked for.
            %
            % Returns:
            %   V - table Name, Label, Kind. Kind is "parameter" (in the tracked
            %       parameter's unit), "rate" (0-1), "index" (d', A', c) or
            %       "count".
            V = cell2table({ ...
                "Threshold",            "Reversal threshold",      "parameter"
                "FitThreshold",         "Fitted threshold",        "parameter"
                "WeightedThreshold",    "Weighted threshold",      "parameter"
                "MedianBlockThreshold", "Median block threshold",  "parameter"
                "MinBlockThreshold",    "Min block threshold",     "parameter"
                "MaxBlockThreshold",    "Max block threshold",     "parameter"
                "ThresholdStd",         "Reversal std",            "parameter"
                "FitBeta",              "Fitted slope",            "index"
                "DPrime",               "d'",                      "index"
                "APrime",               "A'",                      "index"
                "Criterion",            "Criterion",               "index"
                "HitRate",              "Hit rate",                "rate"
                "FARate",               "False-alarm rate",        "rate"
                "AbortRate",            "Abort rate",              "rate"
                "ReversalCount",        "Reversals",               "count"
                "NumIncluded",          "Trials included",         "count"
                "NumTrials",            "Trials",                  "count"}, ...
                'VariableNames', {'Name', 'Label', 'Kind'});
            V.Name = string(V.Name);
            V.Label = string(V.Label);
            V.Kind = string(V.Kind);
        end

        function S = bySubject(T, value, options)
            % S = behavior.Aggregate.bySubject(T, value, GroupBy = facet)
            % One row per subject (and facet level): how that subject's sessions
            % summarize. The per-subject point the Compare plots draw beside the
            % session points, and the unit behavior.Stats.describe can work in.
            %
            % Parameters:
            %   T       - thresholds() table
            %   value   - a valueColumns() name
            %   GroupBy - behavior.Facet (default none: one row per subject)
            %
            % Returns:
            %   S - table Subject, Level, N (sessions with a finite value),
            %       Median, Mean, SD, Min, Max, First, Last (by Start), in
            %       natural subject order and the facet's level order.
            arguments
                T table
                value (1,1) string
                options.GroupBy (1,1) behavior.Facet = behavior.Facet("none")
            end

            behavior.Aggregate.mustHaveColumn_(T, value);
            S = table(strings(0,1), strings(0,1), zeros(0,1), nan(0,1), nan(0,1), nan(0,1), ...
                nan(0,1), nan(0,1), nan(0,1), nan(0,1), ...
                'VariableNames', {'Subject','Level','N','Median','Mean','SD','Min','Max','First','Last'});
            if height(T) == 0
                return
            end

            lvl = options.GroupBy.values(T);
            [levels, ~] = options.GroupBy.order(T);
            subjects = behavior.Aggregate.naturalUnique(string(T.Subject));
            x = double(T.(value));
            start = behavior.Aggregate.startColumn_(T);

            rows = cell(numel(subjects) * numel(levels), 10);
            r = 0;
            for s = reshape(subjects, 1, [])
                for L = reshape(levels, 1, [])
                    in = string(T.Subject) == s & lvl == L;
                    if ~any(in), continue, end
                    r = r + 1;
                    xi = x(in);
                    ok = isfinite(xi);
                    ti = start(in);
                    [~, order] = sort(ti);          % NaT sorts last
                    xo = xi(order);
                    xo = xo(isfinite(xo));
                    if isempty(xo)
                        first = NaN; last = NaN;
                    else
                        first = xo(1); last = xo(end);
                    end
                    rows(r, :) = {s, L, sum(ok), median(xi(ok)), mean(xi(ok)), std(xi(ok)), ...
                        min(xi(ok), [], 'all'), max(xi(ok), [], 'all'), first, last};
                end
            end
            rows = rows(1:r, :);
            if ~isempty(rows)
                S = cell2table(rows, 'VariableNames', S.Properties.VariableNames);
                S.Subject = string(S.Subject);
                S.Level = string(S.Level);
            end
        end

        function u = naturalUnique(names)
            % Unique names in natural order (SUBJ-ID-959 before SUBJ-ID-1254).
            names = reshape(string(names), [], 1);
            u = unique(names, 'stable');
            key = regexprep(u, '(\d+)', '${sprintf(''%010d'', str2double($1))}');
            [~, idx] = sort(lower(key));
            u = u(idx);
        end
    end

    methods (Static, Access = private)
        function R = asStructArray_(results)
            % Results as one struct array, whatever shape they came in.
            if iscell(results)
                results = results(~cellfun(@isempty, results));
                if isempty(results)
                    R = struct([]);
                else
                    R = [results{:}];
                end
            elseif isstruct(results)
                R = results;
            elseif isempty(results)
                R = struct([]);
            else
                error('behavior:Aggregate:InvalidResults', ...
                    'results must be a struct array or a cell array of behavior.Session.analyze results.');
            end
            R = reshape(R, [], 1);
        end

        function T = emptyTable_()
            % The thresholds() table with no rows, every column typed.
            T = behavior.Aggregate.joinSessions_( ...
                [behavior.Aggregate.identityFromResults_(struct([])), ...
                 behavior.Aggregate.numbersFromResults_(struct([]))], []);
            T = behavior.Aggregate.addTagColumns_(T);
            T = behavior.Aggregate.addOrdinals_(T);
        end

        function T = identityFromResults_(R)
            % Key, Project, Subject, Tags, TagText, Start from the results.
            n = numel(R);
            key = strings(n, 1); project = strings(n, 1); subject = strings(n, 1);
            tags = cell(n, 1); tagText = strings(n, 1); numTags = zeros(n, 1);
            start = NaT(n, 1);
            for k = 1:n
                key(k) = string(R(k).Key);
                project(k) = string(R(k).Project);
                subject(k) = string(R(k).Subject);
                t = reshape(string(R(k).Tags), 1, []);
                tags{k} = t;
                tagText(k) = strjoin(t, "|");
                numTags(k) = numel(t);
                if isdatetime(R(k).Start) && ~isempty(R(k).Start)
                    start(k) = R(k).Start(1);
                end
            end
            T = table(key, project, strings(n, 1), subject, tags, tagText, numTags, start, ...
                'VariableNames', {'Key','Project','ProjectPath','Subject','Tags','TagText','NumTags','Start'});
        end

        function T = numbersFromResults_(R)
            % Every scalar the result carries, one column each.
            n = numel(R);
            g = @(f) reshape(arrayfun(@(r) behavior.Aggregate.scalar_(r, f), R), n, 1);
            gs = @(f) reshape(arrayfun(@(r) string(r.(f)), R), n, 1);

            fitThreshold = nan(n, 1); fitAlpha = nan(n, 1); fitBeta = nan(n, 1);
            fitConverged = false(n, 1); fitLo = nan(n, 1); fitHi = nan(n, 1);
            weighted = nan(n, 1);
            dprime = nan(n, 1); aprime = nan(n, 1); crit = nan(n, 1);
            hit = nan(n, 1); fa = nan(n, 1); abortRate = nan(n, 1); numTrials = nan(n, 1);
            qc = strings(n, 1); numQC = zeros(n, 1); msgs = strings(n, 1);
            for k = 1:n
                F = R(k).Fit;
                if isstruct(F) && ~isempty(F)
                    fitThreshold(k) = behavior.Aggregate.scalar_(F, 'Threshold');
                    fitAlpha(k) = behavior.Aggregate.scalar_(F, 'Alpha');
                    fitBeta(k) = behavior.Aggregate.scalar_(F, 'Beta');
                    fitConverged(k) = isfield(F, 'Converged') && isscalar(F.Converged) && logical(F.Converged);
                    if isfield(F, 'CI') && isstruct(F.CI)
                        fitLo(k) = behavior.Aggregate.scalar_(F.CI, 'ThresholdLo');
                        fitHi(k) = behavior.Aggregate.scalar_(F.CI, 'ThresholdHi');
                    end
                end
                W = R(k).Weighted;
                if isstruct(W) && ~isempty(W) && isfield(W, 'Valid') && W.Valid
                    weighted(k) = behavior.Aggregate.scalar_(W, 'Threshold');
                end
                M = R(k).Metrics;
                if isstruct(M) && ~isempty(M)
                    dprime(k) = behavior.Aggregate.scalar_(M, 'DPrime');
                    aprime(k) = behavior.Aggregate.scalar_(M, 'APrime');
                    crit(k) = behavior.Aggregate.scalar_(M, 'Criterion');
                    if isfield(M, 'Rate') && isstruct(M.Rate)
                        hit(k) = behavior.Aggregate.scalar_(M.Rate, 'Hit');
                        fa(k) = behavior.Aggregate.scalar_(M.Rate, 'FalseAlarm');
                        abortRate(k) = behavior.Aggregate.scalar_(M.Rate, 'Abort');
                    end
                    if isfield(M, 'N') && isstruct(M.N)
                        numTrials(k) = behavior.Aggregate.scalar_(M.N, 'Total');
                    end
                end
                flags = reshape(string(R(k).QC), 1, []);
                qc(k) = strjoin(flags, "|");
                numQC(k) = numel(flags);
                msgs(k) = strjoin(reshape(string(R(k).Messages), 1, []), " ");
            end

            T = table(gs('Parameter'), reshape(arrayfun(@(r) logical(r.ParameterAuto), R), n, 1), ...
                gs('Unit'), gs('Window'), g('NumIncluded'), g('NumStimulus'), g('NumCatch'), ...
                g('Threshold'), g('ThresholdStd'), g('ReversalCount'), ...
                g('MinBlockThreshold'), g('MedianBlockThreshold'), g('MeanBlockThreshold'), g('MaxBlockThreshold'), ...
                weighted, fitThreshold, fitAlpha, fitBeta, fitConverged, fitLo, fitHi, ...
                dprime, aprime, crit, hit, fa, abortRate, numTrials, ...
                qc, numQC, msgs, gs('SettingsHash'), g('Elapsed'), ...
                'VariableNames', {'Parameter','ParameterAuto','Unit','Window','NumIncluded','NumStimulus','NumCatch', ...
                'Threshold','ThresholdStd','ReversalCount', ...
                'MinBlockThreshold','MedianBlockThreshold','MeanBlockThreshold','MaxBlockThreshold', ...
                'WeightedThreshold','FitThreshold','FitAlpha','FitBeta','FitConverged','FitCILo','FitCIHi', ...
                'DPrime','APrime','Criterion','HitRate','FARate','AbortRate','NumTrials', ...
                'QC','NumQC','Messages','SettingsHash','Elapsed'});
        end

        function x = scalar_(s, f)
            % One finite-or-NaN double from a struct field, NaN when absent/empty.
            x = NaN;
            if ~isfield(s, f), return, end
            v = s.(f);
            if isempty(v) || ~(isnumeric(v) || islogical(v)), return, end
            x = double(v(1));
        end

        function T = joinSessions_(T, sessions)
            % Carry the sessions table's per-session facts onto matching rows.
            % Columns the table lacks are created empty, so every thresholds()
            % table has the same columns whether or not a catalog was given.
            n = height(T);
            carried = behavior.Aggregate.SESSION_COLUMNS;
            carried = carried(~ismember(carried, ["Project" "Subject" "Tags" "TagText" "NumTags" "Start"]));
            % Defaults for what the sessions table may contribute.
            defaults = struct('ProjectPath', strings(n, 1), 'SubjectSex', strings(n, 1), ...
                'SubjectSpecies', strings(n, 1), 'Paradigm', strings(n, 1), 'ProtocolVersion', strings(n, 1), ...
                'BoxID', nan(n, 1), 'Trials', nan(n, 1), 'QCFile', strings(n, 1), ...
                'NotesText', strings(n, 1), 'NumNotes', nan(n, 1), ...
                'Hidden', false(n, 1), 'HiddenReason', strings(n, 1), 'Window', strings(n, 1), 'Comment', strings(n, 1));
            for c = carried
                if ~ismember(c, string(T.Properties.VariableNames))
                    T.(c) = defaults.(c);
                end
            end
            if isempty(sessions) || ~istable(sessions) || height(sessions) == 0 || n == 0
                return
            end

            have = string(sessions.Properties.VariableNames);
            sk = reshape(string(sessions.Key), [], 1);
            tk = reshape(string(T.Key), [], 1);
            if ispc
                sk = lower(strrep(sk, '\', '/'));
                tk = lower(strrep(tk, '\', '/'));
            end
            [found, where] = ismember(tk, sk);
            if ~any(found), return, end
            src = sessions(where(found), :);
            dst = find(found);

            % Identity columns the result lacks are filled from the catalog.
            for c = ["Project" "Subject" "ProjectPath"]
                if ismember(c, have)
                    T.(c)(dst) = string(src.(c));
                end
            end
            if ismember("Tags", have)
                T.Tags(dst) = behavior.Aggregate.tagCells_(src.Tags);
                T.TagText(dst) = cellfun(@(t) strjoin(t, "|"), T.Tags(dst));
                T.NumTags(dst) = cellfun(@numel, T.Tags(dst));
            end
            if ismember("Start", have)
                T.Start(dst) = src.Start;
            end
            for c = carried
                if ismember(c, have)
                    v = src.(c);
                    if isstring(T.(c))
                        if iscell(v)
                            v = cellfun(@(x) strjoin(reshape(string(x), 1, []), "|"), v);
                        end
                        T.(c)(dst) = string(v);
                    elseif islogical(T.(c))
                        T.(c)(dst) = logical(v);
                    else
                        T.(c)(dst) = double(v);
                    end
                end
            end
            % Every grouping column rides along as the facet reads it.
            for c = have(startsWith(have, "Group_"))
                col = repmat(behavior.Facet.NONE, n, 1);
                col(dst) = string(src.(c));
                T.(c) = col;
            end
        end

        function c = tagCells_(tags)
            % Tags column as a cell of (1,:) string rows, whatever the table held.
            if iscell(tags)
                c = cellfun(@(t) reshape(string(t), 1, []), tags, 'UniformOutput', false);
            else
                c = arrayfun(@(t) reshape(string(t), 1, []), tags, 'UniformOutput', false);
            end
            c = reshape(c, [], 1);
        end

        function T = addTagColumns_(T)
            % Tag1..TagN as plain string columns, "(none)" where a session has fewer.
            n = height(T);
            if n == 0
                T.Tag1 = strings(0, 1);
                return
            end
            tags = behavior.Aggregate.tagCells_(T.Tags);
            N = max(1, max(cellfun(@numel, tags)));
            for p = 1:N
                col = repmat(behavior.Facet.NONE, n, 1);
                for k = 1:n
                    if numel(tags{k}) >= p
                        col(k) = tags{k}(p);
                    end
                end
                T.("Tag" + p) = col;
            end
        end

        function T = addOrdinals_(T)
            % Date, SessionOrdinal and DaysSinceFirst per subject, by Start.
            n = height(T);
            start = behavior.Aggregate.startColumn_(T);
            T.Date = dateshift(start, 'start', 'day');
            ordinal = nan(n, 1);
            days = nan(n, 1);
            if n > 0
                subj = string(T.Subject);
                for s = reshape(unique(subj), 1, [])
                    in = find(subj == s & ~isnat(start));
                    [~, order] = sort(start(in));
                    ordinal(in(order)) = 1:numel(in);
                    first = min(start(in));
                    days(in) = seconds(start(in) - first) / 86400;
                end
            end
            T.SessionOrdinal = ordinal;
            T.DaysSinceFirst = days;
        end

        function start = startColumn_(T)
            start = T.Start;
            if ~isdatetime(start)
                start = NaT(height(T), 1);
            end
            start = reshape(start, [], 1);
        end

        function mustHaveColumn_(T, name)
            if ~ismember(name, string(T.Properties.VariableNames))
                error('behavior:Aggregate:UnknownColumn', ...
                    'The table has no column "%s"; see behavior.Aggregate.valueColumns.', name);
            end
        end
    end
end
