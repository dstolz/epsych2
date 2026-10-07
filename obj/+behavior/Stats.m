classdef Stats
    % behavior.Stats  Descriptive statistics over a results table, by group.
    %
    % The numbers under a Compare plot and in a report: for each level of a
    % facet, how many sessions (or subjects) had a value, their mean, spread,
    % median and quartiles, and -- when asked -- a bootstrap confidence
    % interval on the mean. Nothing here tests a hypothesis: v1 of the
    % offline analysis is descriptive by decision, and the inferential layer
    % (two-sample tests, mixed models) is a later milestone with its own
    % class so that a p-value can never appear by accident.
    %
    %   T = behavior.Aggregate.thresholds(results, sessions);
    %   D = behavior.Stats.describe(T, "Threshold", GroupBy = behavior.Facet("tag", Index = 1));
    %   D = behavior.Stats.describe(T, "Threshold", GroupBy = f, Unit = "subject", BootstrapCI = true);
    %   disp(behavior.Stats.sentence(D))
    %
    % UNIT. "session" (default) describes the per-session values; "subject"
    % first collapses each subject's sessions to their median within a level
    % (behavior.Aggregate.bySubject) and describes those, so an animal with
    % many sessions does not outweigh one with few. The table says which.
    %
    % BOOTSTRAP. The CI is bootci on the mean (percentile method, NumBoot
    % resamples, ConfidenceLevel), computed only where the group has at least
    % MIN_BOOT values -- below that the interval would describe the resampling,
    % not the data -- and NaN otherwise. bootci draws from the global random
    % stream, which a trial selector may be using, so a Seed is applied and
    % the stream's state is put back afterwards exactly as psychophysics.Staircase
    % does for its own bootstrap.
    %
    % Every statistic is the Statistics and Machine Learning Toolbox's own
    % (mean, std, median, prctile, bootci), not a re-derivation.
    %
    % See also: behavior.Aggregate, behavior.Facet, behavior.Plot, bootci

    properties (Constant)
        % Fewest values a bootstrap interval is computed from.
        MIN_BOOT = 5
    end

    methods (Static)
        function D = describe(T, value, options)
            % D = behavior.Stats.describe(T, value, Name = Value)
            % Descriptive statistics of one value column, per facet level.
            %
            % Parameters:
            %   T               - behavior.Aggregate.thresholds table
            %   value           - a column name (behavior.Aggregate.valueColumns)
            %   GroupBy         - behavior.Facet (default none: one row, "(all)")
            %   Unit            - "session" (default) or "subject"
            %   BootstrapCI     - compute CILo/CIHi on the mean (default false)
            %   ConfidenceLevel - default 0.95
            %   NumBoot         - resamples (default 1000)
            %   Seed            - for the bootstrap (default 1)
            %
            % Returns:
            %   D - table Level, N, Mean, SD, SEM, Median, Q1, Q3, Min, Max,
            %       CILo, CIHi, one row per level in the facet's order (a
            %       level with no finite value keeps its row with N = 0).
            %       D.Properties.UserData records Value, Unit, Facet (text),
            %       BootstrapCI, ConfidenceLevel, NumBoot.
            arguments
                T table
                value (1,1) string
                options.GroupBy (1,1) behavior.Facet = behavior.Facet("none")
                options.Unit (1,1) string {mustBeMember(options.Unit, ["session", "subject"])} = "session"
                options.BootstrapCI (1,1) logical = false
                options.ConfidenceLevel (1,1) double {mustBeInRange(options.ConfidenceLevel, 0, 1, "exclusive")} = 0.95
                options.NumBoot (1,1) double {mustBeInteger, mustBePositive} = 1000
                options.Seed (1,1) double {mustBeInteger, mustBeNonnegative} = 1
            end

            if ~ismember(value, string(T.Properties.VariableNames))
                error('behavior:Stats:UnknownColumn', ...
                    'The table has no column "%s"; see behavior.Aggregate.valueColumns.', value);
            end

            if options.Unit == "subject"
                S = behavior.Aggregate.bySubject(T, value, GroupBy = options.GroupBy);
                levels = unique(S.Level, 'stable');
                % bySubject orders levels as the facet does; keep that order.
                [facetLevels, ~] = options.GroupBy.order(T);
                levels = facetLevels(ismember(facetLevels, levels));
                x = S.Median;
                lvl = S.Level;
            else
                [levels, ~] = options.GroupBy.order(T);
                x = double(T.(value));
                lvl = options.GroupBy.values(T);
            end
            x = reshape(x, [], 1);
            lvl = reshape(string(lvl), [], 1);
            levels = reshape(string(levels), [], 1);

            m = numel(levels);
            N = zeros(m, 1); Mean = nan(m, 1); SD = nan(m, 1); SEM = nan(m, 1);
            Median = nan(m, 1); Q1 = nan(m, 1); Q3 = nan(m, 1); Min = nan(m, 1); Max = nan(m, 1);
            CILo = nan(m, 1); CIHi = nan(m, 1);

            restore = [];
            if options.BootstrapCI
                restore = behavior.Stats.seedGlobalStream_(options.Seed);
            end
            for k = 1:m
                xi = x(lvl == levels(k));
                xi = xi(isfinite(xi));
                N(k) = numel(xi);
                if N(k) == 0, continue, end
                Mean(k) = mean(xi);
                SD(k) = std(xi);
                SEM(k) = SD(k) / sqrt(N(k));
                Median(k) = median(xi);
                q = prctile(xi, [25 75]);
                Q1(k) = q(1);
                Q3(k) = q(2);
                Min(k) = min(xi);
                Max(k) = max(xi);
                if options.BootstrapCI && N(k) >= behavior.Stats.MIN_BOOT
                    ci = bootci(options.NumBoot, {@mean, xi}, 'Alpha', 1 - options.ConfidenceLevel, ...
                        'Type', 'percentile');
                    CILo(k) = ci(1);
                    CIHi(k) = ci(2);
                end
            end
            delete(restore);

            D = table(levels, N, Mean, SD, SEM, Median, Q1, Q3, Min, Max, CILo, CIHi, ...
                'VariableNames', {'Level','N','Mean','SD','SEM','Median','Q1','Q3','Min','Max','CILo','CIHi'});
            D.Properties.UserData = struct('Value', value, 'Unit', options.Unit, ...
                'Facet', options.GroupBy.toText(), 'FacetLabel', options.GroupBy.label(), ...
                'BootstrapCI', options.BootstrapCI, 'ConfidenceLevel', options.ConfidenceLevel, ...
                'NumBoot', options.NumBoot);
        end

        function s = sentence(D)
            % s = behavior.Stats.sentence(D)
            % The describe() table in one line per level, for a status line or a
            % report: "Threshold by Tag 1, per session: Pre n=12, median 19.6
            % (IQR 18.9-20.4), mean 19.7 +/- 0.3 SEM; Post ...".
            arguments
                D table
            end
            u = D.Properties.UserData;
            head = sprintf('%s by %s, per %s', u.Value, u.FacetLabel, u.Unit);
            if height(D) == 0
                s = string(head) + ": no values";
                return
            end
            parts = strings(height(D), 1);
            for k = 1:height(D)
                if D.N(k) == 0
                    parts(k) = sprintf('%s n=0', D.Level(k));
                    continue
                end
                parts(k) = sprintf('%s n=%d, median %.3g (IQR %.3g-%.3g), mean %.3g +/- %.2g SEM', ...
                    D.Level(k), D.N(k), D.Median(k), D.Q1(k), D.Q3(k), D.Mean(k), D.SEM(k));
                if u.BootstrapCI && isfinite(D.CILo(k))
                    parts(k) = parts(k) + sprintf(', %g%% CI %.3g-%.3g', ...
                        100 * u.ConfidenceLevel, D.CILo(k), D.CIHi(k));
                end
            end
            s = string(head) + ": " + strjoin(parts, "; ");
        end
    end

    methods (Static, Access = private)
        function restore = seedGlobalStream_(seed)
            % Seed the global stream for a reproducible bootstrap and hand back
            % an onCleanup that puts the caller's state back, whatever happens.
            g = RandStream.getGlobalStream();
            state = g.State;
            restore = onCleanup(@() behavior.Stats.restoreState_(g, state));
            rng(seed);
        end

        function restoreState_(g, state)
            g.State = state;
        end
    end
end
