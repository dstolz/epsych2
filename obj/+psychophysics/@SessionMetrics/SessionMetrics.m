classdef SessionMetrics < psychophysics.Psych
    % S = psychophysics.SessionMetrics(RUNTIME)
    % S = psychophysics.SessionMetrics(DATA)
    % S = psychophysics.SessionMetrics(..., TrialWindow=value)
    % Session-level behavioral summary over a configurable window of trials.
    %
    % SessionMetrics collapses the trial record to the handful of numbers an
    % experimenter watches during a session -- trial counts, outcome rates,
    % d' and criterion -- computed over whichever trials a TrialWindow
    % selects. Every metric comes from the decoded response bitmask and the
    % trial-type masks the psychophysics.Psych base class already provides,
    % so the same object serves any paradigm that writes RespCode.
    %
    % Like every psychophysics.Psych subclass it works online (construct with
    % a Runtime and it follows NewData events) or offline (construct with a
    % saved DATA struct array).
    %
    % Key properties:
    %   TrialWindow    - Trials included in the summary. Accepts anything
    %       psychophysics.TrialWindow.parse understands, e.g. "all", 50
    %       (the last 50), [20 100], or "last 20".
    %   ExcludedTrials - Trials dropped from the summary regardless of the
    %       window (inherited); the two are intersected.
    %   infCorrection  - Rate bounds applied before the z-transform in d'
    %       and criterion, matching psychophysics.Detection.
    %   Results        - Computed counts, rates, and sensitivity measures.
    %
    % Key methods:
    %   summary   - Table of every metric with display text, for GUIs and logs
    %   metric    - Value and formatted text for one named metric
    %   catalogue - Static: the metric definitions this class computes
    %
    % Denominators follow the paradigm: hit and miss rates are scored over
    % stimulus trials, false alarm and correct reject rates over catch
    % trials, and the abort rate over every included trial. A paradigm that
    % never labels trial types (no TrialType field and no TrialType bits in
    % RespCode) scores all outcomes over the whole window instead, so
    % single-trial-type paradigms still report sensible rates.
    %
    % Example:
    %   S = psychophysics.SessionMetrics(RUNTIME, TrialWindow="last 20");
    %   S.TrialWindow = [20 100];      % trials 20 through 100
    %   disp(S.Results.Rate.Hit)
    %   disp(S.summary())
    %
    % See also: psychophysics.TrialWindow, gui.SessionPerformance,
    % psychophysics.Detection, documentation/psychophysics/psychophysics_SessionMetrics.md

    properties (SetObservable)
        % TrialWindow - Trials included in the summary. Declared without a
        % class constraint because property validation runs ahead of the
        % setter, which is where the shorthand forms ("last 20", 50,
        % [20 100]) are converted to a psychophysics.TrialWindow.
        TrialWindow = psychophysics.TrialWindow

        % infCorrection - Rate bounds applied before the z-transform, so a
        % perfect or empty rate cannot send d' to infinity
        infCorrection (1,2) double {mustBeInRange(infCorrection,0,1,"exclusive")} = [0.05 0.95]
    end

    properties (SetAccess = protected)
        Results = []  % Computed session summary; filled by the constructor
    end

    methods
        function obj = SessionMetrics(source, options)
            % S = psychophysics.SessionMetrics(source, Name=Value)
            %
            % Parameters:
            %   source            - epsych.Runtime for online updates, or a per-trial
            %                       DATA struct array for offline analysis.
            %   TrialWindow       - Trials to include; see psychophysics.TrialWindow.parse.
            %   StimulusTrialType - BitMask identifying stimulus trials (default TrialType_0).
            %   CatchTrialType    - BitMask identifying catch trials (default TrialType_1).
            %   ExcludedTrials    - Logical mask or 1-based indices to drop.
            %   infCorrection     - Rate bounds for d' and criterion.
            arguments
                source = []
                options.TrialWindow = psychophysics.TrialWindow
                options.StimulusTrialType (1,1) epsych.BitMask = epsych.BitMask.TrialType_0
                options.CatchTrialType (1,1) epsych.BitMask = epsych.BitMask.TrialType_1
                options.ExcludedTrials = []
                options.infCorrection (1,2) double = [0.05 0.95]
            end

            obj@psychophysics.Psych(source, [], ExcludedTrials=options.ExcludedTrials);

            obj.StimulusTrialType = options.StimulusTrialType;
            obj.CatchTrialType    = options.CatchTrialType;
            obj.infCorrection     = options.infCorrection;
            obj.TrialWindow       = options.TrialWindow;

            obj.recomputeResults_();
        end

        function set.TrialWindow(obj, value)
            % obj.TrialWindow = value
            % Accepts a psychophysics.TrialWindow or any shorthand its parse
            % method understands, then recomputes. Listeners observing this
            % property see results that are already up to date.
            obj.TrialWindow = psychophysics.TrialWindow.parse(value);
            obj.recomputeResults_();
        end

        function set.infCorrection(obj, value)
            obj.infCorrection = value;
            obj.recomputeResults_();
        end

        function T = summary(obj)
            % T = summary(obj)
            % Every metric in catalogue order, as a table ready for display.
            %
            % Returns:
            %   T - Table with one row per metric and variables:
            %       Name   - Programmatic metric name
            %       Label  - Display label
            %       Group  - "Counts", "Rates", or "Sensitivity"
            %       Kind   - Outcome family, used for color coding
            %       Value  - Numeric value in canonical units (rates are fractions)
            %       Text   - Formatted value, e.g. "72.0%" or "1.84"
            %       Detail - Supporting counts, e.g. "18/25"
            C = psychophysics.SessionMetrics.catalogue();
            n = numel(C);

            Name = strings(n,1); Label = strings(n,1); Group = strings(n,1);
            Kind = strings(n,1); Value = nan(n,1);  Text = strings(n,1);
            Detail = strings(n,1);

            for i = 1:n
                [Value(i), Text(i), Detail(i)] = obj.metric(C(i).Name);
                Name(i)  = C(i).Name;
                Label(i) = C(i).Label;
                Group(i) = C(i).Group;
                Kind(i)  = C(i).Kind;
            end

            T = table(Name, Label, Group, Kind, Value, Text, Detail);
        end

        function [value, text, detail] = metric(obj, name)
            % [value, text, detail] = metric(obj, name)
            % One metric by name, in canonical units plus display strings.
            %
            % Parameters:
            %   name - Metric name from psychophysics.SessionMetrics.catalogue.
            %
            % Returns:
            %   value  - Numeric value (rates are fractions, not percentages)
            %   text   - Formatted value, "--" when undefined
            %   detail - Supporting counts, e.g. "18/25"; "" when not applicable
            arguments
                obj
                name (1,1) string
            end

            C = psychophysics.SessionMetrics.catalogue();
            idx = find(strcmp([C.Name], name), 1);
            if isempty(idx)
                error('psychophysics:SessionMetrics:UnknownMetric', ...
                    '"%s" is not a metric of psychophysics.SessionMetrics.', name);
            end

            R = obj.Results;
            N = R.N;
            detail = "";

            switch name
                case "Trials",          value = N.Total;
                case "StimulusTrials",  value = N.Stimulus;
                case "CatchTrials",     value = N.Catch;
                case "Hits",            value = N.Hit;
                case "Misses",          value = N.Miss;
                case "CorrectRejects",  value = N.CorrectReject;
                case "FalseAlarms",     value = N.FalseAlarm;
                case "Aborts",          value = N.Abort;

                case "HitRate"
                    value = R.Rate.Hit;
                    detail = obj.fraction_(N.Hit, N.Scored);
                case "MissRate"
                    value = R.Rate.Miss;
                    detail = obj.fraction_(N.Miss, N.Scored);
                case "FARate"
                    value = R.Rate.FalseAlarm;
                    detail = obj.fraction_(N.FalseAlarm, N.CatchScored);
                case "CRRate"
                    value = R.Rate.CorrectReject;
                    detail = obj.fraction_(N.CorrectReject, N.CatchScored);
                case "AbortRate"
                    value = R.Rate.Abort;
                    detail = obj.fraction_(N.Abort, N.Total);
                case "PercentCorrect"
                    value = R.Rate.Correct;
                    detail = obj.fraction_(N.Hit + N.CorrectReject, N.Scored + N.CatchScored);

                case "DPrime",    value = R.DPrime;
                case "Criterion", value = R.Criterion;
            end

            text = psychophysics.SessionMetrics.formatValue_(value, C(idx).Format);
        end

        function s = summaryText(obj, names)
            % s = summaryText(obj, names)
            % Plain-text summary, one metric per line, for logs and clipboard.
            %
            % Parameters:
            %   names - Metric names to include. Defaults to defaultMetrics.
            arguments
                obj
                names (1,:) string = psychophysics.SessionMetrics.defaultMetrics()
            end

            C = psychophysics.SessionMetrics.catalogue();
            lines = strings(numel(names)+1, 1);
            lines(1) = obj.TrialWindow.label(obj.trialCount);

            for i = 1:numel(names)
                [~, text, detail] = obj.metric(names(i));
                label = C(strcmp([C.Name], names(i))).Label;
                if strlength(detail) > 0
                    lines(i+1) = sprintf('%-22s %8s   %s', label, text, detail);
                else
                    lines(i+1) = sprintf('%-22s %8s', label, text);
                end
            end

            s = strjoin(lines, newline);
        end
    end

    methods (Access = protected)
        function recomputeResults_(obj)
            % Recompute counts, rates, and sensitivity over the active window.
            R = psychophysics.SessionMetrics.emptyResults_();
            R.Window = obj.TrialWindow;

            n = obj.trialCount;
            if n == 0
                obj.Results = R;
                return
            end

            included = false(1,n);
            included(obj.TrialWindow.resolve(n)) = true;
            included = included & ~obj.excludedTrialMask_();

            R.TrialIndex = find(included);
            if ~isempty(R.TrialIndex)
                R.FirstTrial = R.TrialIndex(1);
                R.LastTrial  = R.TrialIndex(end);
            end

            M = obj.responseMasks_(n);
            if isempty(fieldnames(M))
                obj.Results = R;
                return
            end

            stim  = obj.trialTypeMask_(obj.StimulusTrialType) & included;
            catchM = obj.trialTypeMask_(obj.CatchTrialType) & included;

            % A paradigm that never labels trial types scores every outcome
            % over the whole window rather than reporting all-zero rates.
            if ~any(stim) && ~any(catchM)
                stim   = included;
                catchM = included;
            end

            R.N.Total    = sum(included);
            R.N.Stimulus = sum(stim);
            R.N.Catch    = sum(catchM);

            R.N.Hit           = sum(M.Hit & stim);
            R.N.Miss          = sum(M.Miss & stim);
            R.N.FalseAlarm    = sum(M.FalseAlarm & catchM);
            R.N.CorrectReject = sum(M.CorrectReject & catchM);
            R.N.Abort         = sum(M.Abort & included);

            R.N.Scored      = R.N.Hit + R.N.Miss;
            R.N.CatchScored = R.N.FalseAlarm + R.N.CorrectReject;

            R.Rate.Hit           = psychophysics.SessionMetrics.ratio_(R.N.Hit, R.N.Scored);
            R.Rate.Miss          = psychophysics.SessionMetrics.ratio_(R.N.Miss, R.N.Scored);
            R.Rate.FalseAlarm    = psychophysics.SessionMetrics.ratio_(R.N.FalseAlarm, R.N.CatchScored);
            R.Rate.CorrectReject = psychophysics.SessionMetrics.ratio_(R.N.CorrectReject, R.N.CatchScored);
            R.Rate.Abort         = psychophysics.SessionMetrics.ratio_(R.N.Abort, R.N.Total);
            R.Rate.Correct       = psychophysics.SessionMetrics.ratio_( ...
                R.N.Hit + R.N.CorrectReject, R.N.Scored + R.N.CatchScored);

            % psychophysics.Detection owns the signal-detection arithmetic;
            % its clamp uses min/max, which pass NaN through as a bound, so
            % undefined rates are rejected here rather than there.
            if ~isnan(R.Rate.Hit) && ~isnan(R.Rate.FalseAlarm)
                R.DPrime    = psychophysics.Detection.d_prime(R.Rate.Hit, R.Rate.FalseAlarm, obj.infCorrection);
                R.Criterion = psychophysics.Detection.bias(R.Rate.Hit, R.Rate.FalseAlarm, obj.infCorrection);
            end

            obj.Results = R;
        end
    end

    methods (Access = private)
        function M = responseMasks_(obj, n)
            % Decoded response bits, padded or trimmed to the trial count so
            % every mask can be combined with the window mask.
            M = struct();
            rc = obj.responseCodes;
            if isempty(rc), return; end

            M = epsych.BitMask.decode(rc);
            fn = fieldnames(M);
            for i = 1:numel(fn)
                m = reshape(M.(fn{i}), 1, []);
                if numel(m) < n
                    m(end+1:n) = false;
                elseif numel(m) > n
                    m = m(1:n);
                end
                M.(fn{i}) = m;
            end
        end

        function s = fraction_(~, num, den)
            % "18/25", or "" when the denominator is empty
            if den == 0
                s = "";
            else
                s = sprintf("%d/%d", num, den);
            end
        end
    end

    methods (Static)
        function C = catalogue()
            % C = psychophysics.SessionMetrics.catalogue()
            % Definitions of every metric this class computes.
            %
            % Returns:
            %   C - Struct array with fields Name, Label, Group, Kind, Format.
            %       Kind names the outcome family a metric belongs to, which
            %       gui.SessionPerformance maps to a display color.
            defs = {
            % Name              Label                    Group          Kind           Format
              "Trials",         "Trials",                "Counts",      "count",       "%d"
              "StimulusTrials", "Stimulus Trials",       "Counts",      "count",       "%d"
              "CatchTrials",    "Catch Trials",          "Counts",      "count",       "%d"
              "Hits",           "Hits",                  "Counts",      "hit",         "%d"
              "Misses",         "Misses",                "Counts",      "miss",        "%d"
              "CorrectRejects", "Correct Rejects",       "Counts",      "cr",          "%d"
              "FalseAlarms",    "False Alarms",          "Counts",      "fa",          "%d"
              "Aborts",         "Aborts",                "Counts",      "abort",       "%d"
              "HitRate",        "Hit Rate",              "Rates",       "hit",         "%.1f%%"
              "MissRate",       "Miss Rate",             "Rates",       "miss",        "%.1f%%"
              "FARate",         "False Alarm Rate",      "Rates",       "fa",          "%.1f%%"
              "CRRate",         "Correct Reject Rate",   "Rates",       "cr",          "%.1f%%"
              "AbortRate",      "Abort Rate",            "Rates",       "abort",       "%.1f%%"
              "PercentCorrect", "Percent Correct",       "Rates",       "neutral",     "%.1f%%"
              "DPrime",         "d'",                    "Sensitivity", "sensitivity", "%.2f"
              "Criterion",      "Criterion (c)",         "Sensitivity", "sensitivity", "%.2f"
              };

            C = struct('Name', defs(:,1), 'Label', defs(:,2), 'Group', defs(:,3), ...
                'Kind', defs(:,4), 'Format', defs(:,5));
            C = reshape(C, 1, []);
        end

        function names = metricNames()
            % names = psychophysics.SessionMetrics.metricNames()
            % Names of every available metric, in catalogue order.
            C = psychophysics.SessionMetrics.catalogue();
            names = [C.Name];
        end

        function names = defaultMetrics()
            % names = psychophysics.SessionMetrics.defaultMetrics()
            % The summary an experimenter usually wants on screen.
            names = ["Trials","HitRate","FARate","AbortRate","DPrime"];
        end
    end

    methods (Static, Access = private)
        function R = emptyResults_()
            % Result skeleton, so every field exists before the first trial.
            zeroCounts = struct('Total',0,'Stimulus',0,'Catch',0, ...
                'Hit',0,'Miss',0,'CorrectReject',0,'FalseAlarm',0,'Abort',0, ...
                'Scored',0,'CatchScored',0);
            nanRates = struct('Hit',NaN,'Miss',NaN,'FalseAlarm',NaN, ...
                'CorrectReject',NaN,'Abort',NaN,'Correct',NaN);

            R = struct( ...
                'Window',     psychophysics.TrialWindow, ...
                'TrialIndex', zeros(1,0), ...
                'FirstTrial', NaN, ...
                'LastTrial',  NaN, ...
                'N',          zeroCounts, ...
                'Rate',       nanRates, ...
                'DPrime',     NaN, ...
                'Criterion',  NaN);
        end

        function r = ratio_(num, den)
            if den == 0
                r = NaN;
            else
                r = double(num) ./ double(den);
            end
        end

        function s = formatValue_(value, fmt)
            % Format a metric for display; undefined values read as "--".
            if isempty(value) || (isnumeric(value) && ~isscalar(value))
                s = "--";
                return
            end
            if isnan(value)
                s = "--";
                return
            end
            if endsWith(fmt, "%%")
                s = string(sprintf(fmt, 100*value));
            else
                s = string(sprintf(fmt, value));
            end
        end
    end
end
