classdef Detection < psychophysics.Psych
    % D = psychophysics.Detection(RUNTIME, Parameter)
    % D = psychophysics.Detection(DATA, "FieldName")
    % D = psychophysics.Detection(..., Name=Value)
    % Yes/no (Go/No-Go) detection analysis, by stimulus value.
    %
    % Stimulus trials are grouped by the value they recorded for Parameter
    % (a tone level, a flash duration, a deviant sound's ID); every catch
    % trial goes into ONE pool, whatever value it recorded. Each stimulus
    % value then gets its hit rate and, against the pooled false-alarm rate,
    % d', A', criterion c and B''. psychophysics.SessionMetrics is the same
    % arithmetic collapsed over every stimulus value; both delegate the
    % formulas to psychophysics.Metrics, so for one stimulus value the two
    % agree exactly.
    %
    % Like every psychophysics.Psych it runs online (construct with a
    % runtime; it follows NewData) or offline (construct with a saved DATA
    % struct array; change it with setData). Online it also accepts a DATA
    % field NAME as Parameter -- the analysis needs only the field, which is
    % how a plot switches its independent variable mid-session.
    %
    % Every analysis setting -- Parameter, StimulusTrialType,
    % CatchTrialType, TrialWindow, ExcludedTrials, IncludeAborts,
    % CorrectionMode, infCorrection -- recomputes Results and broadcasts
    % Events.NewData when it changes, so every display over the object
    % follows. Reading a result never changes anything.
    %
    % Results (struct):
    %   Parameter    - DATA field the stimulus trials are grouped by
    %   Values       - 1xK stimulus values, ascending
    %   N            - Per value (1xK): Trials, Hit, Miss, Abort, and Scored,
    %                  the hit rate's denominator (Hit+Miss, plus Abort under
    %                  IncludeAborts)
    %   Catch        - Pooled catch trials (scalars): Trials, FalseAlarm,
    %                  CorrectReject, Abort, Scored
    %   Rate         - Hit and Miss (1xK); FalseAlarm and CorrectReject
    %                  (scalars, pooled)
    %   DPrime, APrime, Criterion, BPrimePrime - 1xK, each value's hit rate
    %                  against the pooled false-alarm rate
    %   NumNoValue   - Stimulus trials left out because they recorded no
    %                  numeric value for Parameter
    %   TrialIndex   - Trials included (TrialWindow minus ExcludedTrials)
    %   Window       - The psychophysics.TrialWindow applied
    %   Message      - Why Results are empty, or ""
    %
    % Methods:
    %   metric               - One metric as a row over Values, for plotting
    %   summary              - Per-value table
    %   windowed             - Every metric as a curve over trials
    %                          (cumulative, or a sliding window)
    %   candidateParameters  - DATA fields that could be the independent variable
    %   sourceLabel          - "Subject [box]" for a title
    %
    % Trial types come from DATA.TrialType when present, else from the
    % TrialType_* bits in the response codes (psychophysics.Psych). A
    % paradigm that labels neither is analysed as all stimulus trials,
    % with false alarms counted wherever they were scored -- the rule
    % SessionMetrics applies.
    %
    % Example:
    %   D = psychophysics.Detection(RUNTIME, RUNTIME.find_parameter('ToneLevel'));
    %   D = psychophysics.Detection(S.Data, "ToneLevel", TrialWindow="last 100");
    %   plot(D.Results.Values, D.Results.Rate.Hit)
    %
    % See also: psychophysics.Psych, psychophysics.SessionMetrics,
    %   psychophysics.Metrics, gui.components.PsychPlot,
    %   gui.components.SlidingWindowPerformancePlot,
    %   documentation/psychophysics/psychophysics_Detection.md

    properties (SetObservable)
        % TrialWindow - Trials included; anything psychophysics.TrialWindow.parse
        % takes ("all", 50 for the last 50, [20 100], "last 20").
        TrialWindow = psychophysics.TrialWindow

        % IncludeAborts - Count aborted trials against the hit and false
        % alarm rates, as failures to respond. False by default, so the rates
        % describe the trials the subject answered; see
        % psychophysics.Metrics.rateDenominator.
        IncludeAborts (1,1) logical = false

        % CorrectionMode - How rates of exactly 0 or 1 are handled before the
        % z-transform behind d' and c; see psychophysics.Metrics. A' and B''
        % take the observed rates under every mode.
        CorrectionMode (1,1) string {mustBeMember(CorrectionMode, ...
            ["none","clamp","halfcell","loglinear"])} = "clamp"

        % infCorrection - Rate bounds for CorrectionMode "clamp".
        infCorrection (1,2) double {mustBeInRange(infCorrection,0,1,"exclusive")} = [0.05 0.95]

        % BoxID - Follow only this box's NewData. Empty follows every box,
        % which is right for a single-box rig and wrong for a multi-box one,
        % where it would mix subjects.
        BoxID double {mustBeScalarOrEmpty} = []

        % Subject - Label for titles. Empty uses the subject named by the
        % session's own NewData.
        Subject (1,1) string = ""
    end

    properties (SetAccess = protected)
        Results = []  % Computed analysis; see the class help
    end

    properties (SetAccess = private)
        SourceSubject (1,1) string = ""  % Subject named by the last NewData accepted
        SourceBoxID = []                 % Box of the last NewData accepted
    end

    properties (Dependent)
        ParameterField  % DATA field the analysis reads (string)
    end

    properties (Access = private)
        trial_ = []                          % per-trial arrays, rebuilt by recomputeResults_
        constructing_ (1,1) logical = true   % settings do not recompute until the end of the constructor
        settingListener_ = event.listener.empty  % PostSet on the inherited analysis settings
    end

    properties (Constant, Hidden)
        % History row colours, pastel so the row text stays readable; in the
        % order of epsych.BitMask.getResponses (Hit Miss CR FA Abort).
        ROW_COLORS = ["#dff7df"; "#fcdcdc"; "#d9f2ff"; "#fcdefc"; "#fcfcd4"]

        % DATA fields that are bookkeeping, never an independent variable.
        BOOKKEEPING_FIELDS = ["RespCode","ResponseCode","TrialType","TrialIndex", ...
            "TrialID","computerTimestamp","isTest"]
    end

    methods
        function obj = Detection(source, Parameter, options)
            % D = psychophysics.Detection(source, Parameter, Name=Value)
            %
            % Parameters:
            %   source            - epsych.Runtime (online) or a per-trial DATA
            %                       struct array (offline).
            %   Parameter         - hw.Parameter, or the name of a DATA field
            %                       (online or offline).
            %   StimulusTrialType - Trials grouped by value. Default TrialType_0.
            %   CatchTrialType    - Trials pooled for the false-alarm rate.
            %                       Default TrialType_1.
            %   TrialWindow       - Trials included. Default all.
            %   ExcludedTrials    - Logical mask or 1-based indices to drop.
            %   IncludeAborts     - Default false.
            %   CorrectionMode    - Default "clamp".
            %   infCorrection     - Default [0.05 0.95].
            %   BoxID             - Follow only this box online. Default [] (all).
            %   Subject           - Title label. Default "" (the session's).
            arguments
                source = []
                Parameter = []
                options.StimulusTrialType (1,1) epsych.BitMask = epsych.BitMask.TrialType_0
                options.CatchTrialType (1,1) epsych.BitMask = epsych.BitMask.TrialType_1
                options.TrialWindow = psychophysics.TrialWindow
                options.ExcludedTrials = []
                options.IncludeAborts (1,1) logical = false
                options.CorrectionMode (1,1) string = "clamp"
                options.infCorrection (1,2) double = [0.05 0.95]
                options.BoxID double {mustBeScalarOrEmpty} = []
                options.Subject (1,1) string = ""
            end

            obj@psychophysics.Psych(source, Parameter, ExcludedTrials=options.ExcludedTrials);

            obj.StimulusTrialType = options.StimulusTrialType;
            obj.CatchTrialType    = options.CatchTrialType;
            obj.TrialWindow       = options.TrialWindow;
            obj.IncludeAborts     = options.IncludeAborts;
            obj.CorrectionMode    = options.CorrectionMode;
            obj.infCorrection     = options.infCorrection;
            obj.BoxID             = options.BoxID;
            obj.Subject           = options.Subject;
            obj.BitColors         = psychophysics.Detection.ROW_COLORS;

            % Built mid-session (a pop-out, a review), an online analysis
            % would otherwise read empty until the next trial completes.
            obj.seedFromRuntime_();

            obj.constructing_ = false;
            obj.recomputeResults_();

            % The inherited settings have no setter this class can define, so
            % their change is caught here; each recomputes and broadcasts
            % like the settings declared above.
            obj.settingListener_ = addlistener(obj, ...
                {'Parameter','StimulusTrialType','CatchTrialType'}, 'PostSet', ...
                @(~,~) obj.refresh());
        end

        function delete(obj)
            % Release the settings listener; Psych releases the runtime one.
            delete(obj.settingListener_(isvalid(obj.settingListener_)));
        end

        function update_data(obj, src, event)
            % update_data(obj, src, event)
            % A completed trial from the runtime. Ignored when it is another
            % box's (BoxID); otherwise the base class takes the trials,
            % recomputes and broadcasts.
            if ~isempty(obj.BoxID) && ~isempty(event.BoxID) && ~any(event.BoxID == obj.BoxID)
                return
            end
            obj.noteSource_(event.Subject, event.BoxID);
            update_data@psychophysics.Psych(obj, src, event);
        end

        % --- Settings: each recomputes and broadcasts ----------------------
        function set.TrialWindow(obj, value)
            obj.TrialWindow = psychophysics.TrialWindow.parse(value);
            obj.settingChanged_();
        end

        function set.IncludeAborts(obj, value)
            obj.IncludeAborts = value;
            obj.settingChanged_();
        end

        function set.CorrectionMode(obj, value)
            obj.CorrectionMode = value;
            obj.settingChanged_();
        end

        function set.infCorrection(obj, value)
            obj.infCorrection = value;
            obj.settingChanged_();
        end

        function set.BoxID(obj, value)
            obj.BoxID = value;
            obj.boxChanged_();
        end

        function f = get.ParameterField(obj)
            f = "";
            if ~isempty(obj.Parameter)
                f = string(obj.parameterFieldName_());
            end
        end

        % --- Reading results -------------------------------------------------
        function y = metric(obj, name)
            % y = metric(obj, name)
            % One metric as a row over Results.Values, for plotting. The
            % pooled false-alarm and correct-reject rates are repeated once
            % per value so every metric lines up with Values.
            %
            % Parameters:
            %   name - One of psychophysics.Detection.metricNames().
            arguments
                obj
                name (1,1) string {mustBeMember(name, ["HitRate","MissRate","FARate", ...
                    "CRRate","DPrime","APrime","Criterion","BPrimePrime"])}
            end
            R = obj.Results;
            K = numel(R.Values);
            switch name
                case "HitRate",     y = R.Rate.Hit;
                case "MissRate",    y = R.Rate.Miss;
                case "FARate",      y = repmat(R.Rate.FalseAlarm, 1, K);
                case "CRRate",      y = repmat(R.Rate.CorrectReject, 1, K);
                otherwise,          y = R.(name);
            end
        end

        function T = summary(obj)
            % T = summary(obj)
            % One row per stimulus value: the trials it rests on and every
            % metric. The pooled catch-trial side is in Results.Catch.
            R = obj.Results;
            T = table(R.Values(:), R.N.Trials(:), R.N.Hit(:), R.N.Miss(:), R.N.Abort(:), ...
                R.Rate.Hit(:), R.DPrime(:), R.APrime(:), R.Criterion(:), ...
                VariableNames = {'Value','Trials','Hits','Misses','Aborts', ...
                    'HitRate','DPrime','APrime','Criterion'});
        end

        function W = windowed(obj, windowSize)
            % W = windowed(obj, windowSize)
            % Every metric as a curve over trials: row t is computed from the
            % trials in the window ending at trial t -- all trials so far
            % when windowSize is 0, else the last windowSize. Excluded trials
            % count nowhere; TrialWindow is not applied (the window is).
            %
            % Computed from running sums, so the whole curve costs one pass
            % whatever the session length.
            %
            % Returns:
            %   W - struct: TrialIndex (n x 1), Values (1 x K), WindowSize,
            %       HitRate, DPrime, APrime, Criterion, BPrimePrime (n x K),
            %       FARate (n x 1), NScored (n x K), CatchScored (n x 1).
            arguments
                obj
                windowSize (1,1) double {mustBeNonnegative, mustBeInteger} = 0
            end
            c = obj.trial_;
            n = c.n;

            withValue = c.stim & ~isnan(c.value);
            vals = unique(c.value(withValue));
            K = numel(vals);
            [~, g] = ismember(c.value, vals);
            g(~withValue) = 0;

            onehot = zeros(n, K);
            rows = find(g > 0);
            onehot(sub2ind([n K], rows, g(rows))) = 1;

            sumW = @(X) psychophysics.Detection.windowSum_(X, windowSize);
            nHit   = sumW(onehot .* c.hit(:));
            nMiss  = sumW(onehot .* c.miss(:));
            nAbort = sumW(onehot .* c.abort(:));
            nFA    = sumW(double(c.catch & c.fa).');
            nCR    = sumW(double(c.catch & c.cr).');
            nAbC   = sumW(double(c.catch & c.abort).');

            S = psychophysics.Metrics.fromCounts(nHit, nMiss, nFA, nCR, ...
                AbortSignal=nAbort, AbortNoise=nAbC, IncludeAborts=obj.IncludeAborts, ...
                Correction=obj.CorrectionMode, Bounds=obj.infCorrection);
            catchScored = psychophysics.Metrics.rateDenominator(nFA + nCR, nAbC, obj.IncludeAborts);

            W = struct();
            W.TrialIndex  = (1:n).';
            W.Values      = reshape(vals, 1, []);
            W.WindowSize  = windowSize;
            W.HitRate     = S.Rate.Hit;
            W.DPrime      = S.DPrime;
            W.APrime      = S.APrime;
            W.Criterion   = S.Criterion;
            W.BPrimePrime = S.BPrimePrime;
            W.FARate      = psychophysics.Metrics.rate(nFA, catchScored);
            W.NScored     = psychophysics.Metrics.rateDenominator(nHit + nMiss, nAbort, obj.IncludeAborts);
            W.CatchScored = catchScored;
        end

        function names = candidateParameters(obj)
            % names = candidateParameters(obj)
            % DATA fields that could be the independent variable: every field
            % holding a numeric value on at least one trial, bookkeeping
            % (RespCode, TrialType, TrialIndex, ...) left out.
            names = strings(1, 0);
            if isempty(obj.DATA), return; end
            fn = setdiff(string(fieldnames(obj.DATA)).', ...
                psychophysics.Detection.BOOKKEEPING_FIELDS, 'stable');
            numeric = false(size(fn));
            for k = 1:numel(fn)
                numeric(k) = any(~isnan(obj.perTrialNumeric_(char(fn(k)), NaN)));
            end
            names = fn(numeric);
        end

        function s = sourceLabel(obj)
            % s = sourceLabel(obj)
            % "Subject [box]" for a plot title; "" when neither is known.
            name = obj.Subject;
            if strlength(name) == 0, name = obj.SourceSubject; end
            box = obj.BoxID;
            if isempty(box), box = obj.SourceBoxID; end
            if isempty(box)
                s = name;
            else
                s = strtrim(sprintf('%s [%d]', name, box));
            end
        end
    end

    methods (Static)
        function names = metricNames()
            % names = psychophysics.Detection.metricNames()
            % Every name metric() accepts, for a plot's type picker.
            names = ["HitRate","FARate","DPrime","APrime","Criterion","BPrimePrime","MissRate","CRRate"];
        end
    end

    methods (Access = protected)
        function recomputeResults_(obj)
            if obj.constructing_, return; end
            obj.trial_ = obj.perTrialArrays_();
            obj.Results = obj.tabulate_(obj.windowMask_());
        end

        function P = normalizeParameter_(~, P)
            % A DATA field name is as good as a parameter object, online too:
            % the analysis reads only the field. The base class refuses a name
            % online because a Staircase needs the hw.Parameter itself.
            if ischar(P) || (isstring(P) && isscalar(P))
                P = string(P);
            end
        end
    end

    methods (Access = private)
        function settingChanged_(obj)
            if ~obj.constructing_
                obj.refresh();
            end
        end

        function boxChanged_(obj)
            % Changing box changes whose trials these are, so an online
            % analysis takes that box's trials from the runtime at once.
            if obj.constructing_ || isempty(obj.RUNTIME), return; end
            obj.DATA = [];
            obj.seedFromRuntime_();
            obj.refresh();
        end

        function seedFromRuntime_(obj)
            % Take this box's trials from the runtime when it already has
            % some. With no BoxID only a single-subject runtime is
            % unambiguous; a multi-box one waits for its NewData.
            if isempty(obj.RUNTIME), return; end
            T = [];
            try
                T = obj.RUNTIME.TRIALS;
            catch
            end
            if ~isstruct(T) || isempty(T) || ~isfield(T, 'DATA'), return; end
            if isempty(obj.BoxID)
                if ~isscalar(T), return; end
                k = 1;
            elseif isfield(T, 'BoxID')
                k = find([T.BoxID] == obj.BoxID, 1);
                if isempty(k), return; end
            else
                return
            end
            obj.DATA = T(k).DATA;
            subj = [];
            box = [];
            if isfield(T, 'Subject'), subj = T(k).Subject; end
            if isfield(T, 'BoxID'),   box  = T(k).BoxID;   end
            obj.noteSource_(subj, box);
        end

        function noteSource_(obj, subject, box)
            name = "";
            try
                if isstruct(subject) || isobject(subject)
                    name = string(subject.Name);
                elseif ~isempty(subject)
                    name = string(subject);
                end
            catch
            end
            obj.SourceSubject = name;
            obj.SourceBoxID = box;
        end

        function c = perTrialArrays_(obj)
            % Everything the counts are built from, one entry per trial.
            n = obj.trialCount;
            c.n = n;
            c.field = obj.ParameterField;
            if strlength(c.field) > 0
                c.value = obj.perTrialNumeric_(char(c.field), NaN);
            else
                c.value = nan(1, n);
            end
            c.hasField = strlength(c.field) > 0 && n > 0 && isfield(obj.DATA, c.field);

            rc = obj.responseCodes;
            if isempty(rc)
                M = [];
                f = false(1, n);
                [c.hit, c.miss, c.fa, c.cr, c.abort] = deal(f);
            else
                M = epsych.BitMask.decode(rc);
                c.hit   = reshape(M.Hit, 1, []);
                c.miss  = reshape(M.Miss, 1, []);
                c.fa    = reshape(M.FalseAlarm, 1, []);
                c.cr    = reshape(M.CorrectReject, 1, []);
                c.abort = reshape(M.Abort, 1, []);
            end

            c.excluded = obj.excludedTrialMask_();
            masks = obj.trialTypeMasks_([obj.StimulusTrialType obj.CatchTrialType], M);
            c.stim  = masks(1, :);
            c.catch = masks(2, :);
            c.unlabeled = n > 0 && ~any(c.stim) && ~any(c.catch);
            if c.unlabeled
                c.stim  = ~c.excluded;
                c.catch = ~c.excluded;
            end
        end

        function use = windowMask_(obj)
            n = obj.trial_.n;
            use = false(1, n);
            use(obj.TrialWindow.resolve(n)) = true;
            use = use & ~obj.trial_.excluded;
        end

        function R = tabulate_(obj, use)
            % Results over the trials USE selects.
            c = obj.trial_;
            R = psychophysics.Detection.emptyResults_();
            R.Parameter  = c.field;
            R.Window     = obj.TrialWindow;
            R.TrialIndex = find(use);

            if c.n == 0
                R.Message = "No trials yet.";
                return
            end
            if strlength(c.field) == 0
                R.Message = "No Parameter set: nothing to group the stimulus trials by.";
            elseif ~c.hasField
                R.Message = "DATA has no field """ + c.field + """.";
            end

            stim = c.stim & use;
            ctch = c.catch & use;
            withValue = stim & ~isnan(c.value);
            R.NumNoValue = nnz(stim & ~withValue);

            vals = unique(c.value(withValue));
            K = numel(vals);
            R.Values = reshape(vals, 1, []);
            [~, g] = ismember(c.value, vals);
            g(~withValue) = 0;

            countBy = @(m) psychophysics.Detection.countBy_(g, m, K);
            R.N.Trials = countBy(true(1, c.n));
            R.N.Hit    = countBy(c.hit);
            R.N.Miss   = countBy(c.miss);
            R.N.Abort  = countBy(c.abort);
            R.N.Scored = psychophysics.Metrics.rateDenominator( ...
                R.N.Hit + R.N.Miss, R.N.Abort, obj.IncludeAborts);

            R.Catch.Trials        = nnz(ctch);
            R.Catch.FalseAlarm    = nnz(ctch & c.fa);
            R.Catch.CorrectReject = nnz(ctch & c.cr);
            R.Catch.Abort         = nnz(ctch & c.abort);
            R.Catch.Scored        = psychophysics.Metrics.rateDenominator( ...
                R.Catch.FalseAlarm + R.Catch.CorrectReject, R.Catch.Abort, obj.IncludeAborts);

            R.Rate.FalseAlarm    = psychophysics.Metrics.rate(R.Catch.FalseAlarm, R.Catch.Scored);
            R.Rate.CorrectReject = psychophysics.Metrics.rate(R.Catch.CorrectReject, R.Catch.Scored);

            if K == 0
                if strlength(R.Message) == 0
                    R.Message = "No stimulus trial with a value yet.";
                end
                return
            end

            % psychophysics.Metrics owns every formula; a row of per-value
            % counts against the pooled catch counts broadcasts to one value
            % per stimulus level.
            S = psychophysics.Metrics.fromCounts(R.N.Hit, R.N.Miss, ...
                R.Catch.FalseAlarm, R.Catch.CorrectReject, ...
                AbortSignal=R.N.Abort, AbortNoise=R.Catch.Abort, ...
                IncludeAborts=obj.IncludeAborts, ...
                Correction=obj.CorrectionMode, Bounds=obj.infCorrection);
            R.Rate.Hit    = S.Rate.Hit;
            R.Rate.Miss   = S.Rate.Miss;
            R.DPrime      = S.DPrime;
            R.APrime      = S.APrime;
            R.Criterion   = S.Criterion;
            R.BPrimePrime = S.BPrimePrime;
        end
    end

    methods (Static, Access = private)
        function out = countBy_(g, m, K)
            % Trials per value group (g > 0) among those M selects.
            sel = g > 0 & m;
            out = zeros(1, K);
            if K > 0 && any(sel)
                out = accumarray(g(sel).', 1, [K 1]).';
            end
        end

        function S = windowSum_(X, w)
            % Running sums down the trials (rows): all so far when w is 0,
            % else over the last w.
            S = cumsum(X, 1);
            if w > 0 && size(X, 1) > 0
                k = min(w, size(X, 1));
                S = S - [zeros(k, size(X, 2)); S(1:end-k, :)];
            end
        end

        function R = emptyResults_()
            % Every field present before the first trial.
            e = zeros(1, 0);
            R = struct( ...
                'Parameter',  "", ...
                'Values',     e, ...
                'N',          struct('Trials', e, 'Hit', e, 'Miss', e, 'Abort', e, 'Scored', e), ...
                'Catch',      struct('Trials', 0, 'FalseAlarm', 0, 'CorrectReject', 0, 'Abort', 0, 'Scored', 0), ...
                'Rate',       struct('Hit', e, 'Miss', e, 'FalseAlarm', NaN, 'CorrectReject', NaN), ...
                'DPrime',     e, ...
                'APrime',     e, ...
                'Criterion',  e, ...
                'BPrimePrime', e, ...
                'NumNoValue', 0, ...
                'TrialIndex', e, ...
                'Window',     psychophysics.TrialWindow, ...
                'Message',    "");
        end
    end
end
