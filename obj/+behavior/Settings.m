classdef Settings
    % s = behavior.Settings()
    % s = behavior.Settings(Name = Value, ...)
    % Every setting an offline behavioral analysis depends on, as one value.
    %
    % A Settings object is the RECORD of how a result was computed: which
    % analysis, which parameter, which trials, how the staircase threshold is
    % read off the reversals, how the psychometric function is fitted, and how
    % rates of 0 and 1 are corrected. It is the single place those choices
    % become psychophysics options -- staircaseArgs, staircaseProperties,
    % metricsArgs and fitArgs -- so the browser, the analysis, and a generated
    % script cannot read one setting two ways.
    %
    %   s = behavior.Settings(Window = "20+", ...
    %       Staircase = struct(ThresholdFromLastNReversals = 8));
    %   s.hash()                     % "9a4f1c2e": names the numbers it gives
    %   s.problems()                 % what would stop it from running
    %   st = s.toStruct();           % for project.json; no NaN or Inf
    %   s2 = behavior.Settings.fromStruct(jsondecode(jsonencode(st)));
    %
    % SUB-STRUCTS MERGE OVER THE DEFAULTS. Staircase, Fit, Metrics, QC,
    % Compare, Detection and NAFC are structs whose fields are validated one
    % by one. A partial struct -- in the constructor or assigned later --
    % keeps the defaults for every field it does not name, and a field the
    % group does not have is an error (a typo must not be silently ignored).
    % fromStruct is the forgiving reader for saved settings instead: it
    % coerces what jsondecode hands back, drops what it does not know, and
    % reports what it could not use rather than throwing.
    %
    % NO NaN OR Inf, EVER. A JSON file cannot carry them (jsonencode writes
    % null), so "find the weighted step from the data" is [] here and NaN
    % only on the psychophysics.Staircase it configures.
    %
    % THE HASH covers what changes a result and nothing else: QC thresholds
    % and Compare options are left out (they change flags and plots, not
    % numbers). It is FNV-1a over a canonical text -- fields sorted, numbers
    % written %.17g -- so it is the same on every machine and in every field
    % order.
    %
    % Properties:
    %   Analysis          - "Staircase" (v1); "Detection" and "NAFC" are
    %                       reserved, and problems() says so
    %   Parameter         - DATA field to analyse; "" = the session's first
    %                       candidate (behavior.Session.candidates)
    %   Window            - Trial window text, psychophysics.TrialWindow.parse
    %                       syntax: "all", "last 100", "first 50", "3-83", "20+"
    %   ExcludeTest       - Drop isTest (Preview) trials
    %   ExcludeTrialTypes - TrialType values dropped from every analysis
    %   IncludeAborts     - Count aborts as failures to respond
    %   StimulusTrialType, CatchTrialType - TrialType values (0-5)
    %   Staircase - Direction ("Down"|"Up"), ThresholdFromLastNReversals,
    %               ThresholdFormula ("Mean"|"GeometricMean"),
    %               ApplyWeightedCorrection, WeightedStepAfterYes/No ([] =
    %               find it), WeightedStepFieldYes/No ("" = none)
    %   Fit       - Enabled, Engine ("builtin"|"psignifit"), Shape, ThresholdCriterion,
    %               CriterionScale, GuessFromCatchTrials, GuessRate, LapseRate,
    %               EstimateLapse, Bootstrap, ConfidenceLevel, RandomSeed
    %   Metrics   - CorrectionMode, infCorrection
    %   QC        - MinTrials, MaxAbortRate, MinReversals
    %   Compare   - BootstrapCI, ConfidenceLevel, NumBoot
    %   Detection, NAFC - reserved for v2
    %
    % Documentation: documentation/behavior/behavior_Classes.md
    % See also: behavior.Session, psychophysics.Staircase,
    %   psychophysics.SessionMetrics, psychophysics.TrialWindow

    properties (Constant)
        SettingsVersion (1,1) double = 1
    end

    properties
        Analysis (1,1) string {mustBeMember(Analysis, ["Staircase","Detection","NAFC"])} = "Staircase"
        Parameter (1,1) string = ""
        Window (1,1) string = "all"
        ExcludeTest (1,1) logical = true
        ExcludeTrialTypes (1,:) double {mustBeInteger, mustBeInRange(ExcludeTrialTypes,0,5)} = zeros(1,0)
        IncludeAborts (1,1) logical = false
        StimulusTrialType (1,1) double {mustBeInteger, mustBeInRange(StimulusTrialType,0,5)} = 0
        CatchTrialType (1,1) double {mustBeInteger, mustBeInRange(CatchTrialType,0,5)} = 1
        Staircase (1,1) struct = behavior.Settings.defaults_("Staircase")
        Fit (1,1) struct = behavior.Settings.defaults_("Fit")
        Metrics (1,1) struct = behavior.Settings.defaults_("Metrics")
        QC (1,1) struct = behavior.Settings.defaults_("QC")
        Compare (1,1) struct = behavior.Settings.defaults_("Compare")
        Detection (1,1) struct = behavior.Settings.defaults_("Detection")
        NAFC (1,1) struct = behavior.Settings.defaults_("NAFC")
    end

    properties (Constant, Access = private)
        GROUPS_ = ["Staircase" "Fit" "Metrics" "QC" "Compare" "Detection" "NAFC"]
        EXCLUDED_FROM_HASH_ = ["QC" "Compare"]
    end

    methods
        function obj = Settings(options)
            % s = behavior.Settings(Name = Value, ...)
            % Every property can be given; a sub-struct is merged over its
            % defaults, so struct(ThresholdFromLastNReversals = 8) keeps the
            % rest of Staircase as it was.
            arguments
                options.?behavior.Settings
            end
            names = fieldnames(options);
            for k = 1:numel(names)
                obj.(names{k}) = options.(names{k});
            end
        end

        function obj = set.Staircase(obj, v), obj.Staircase = behavior.Settings.merge_("Staircase", v, true); end
        function obj = set.Fit(obj, v),       obj.Fit = behavior.Settings.merge_("Fit", v, true); end
        function obj = set.Metrics(obj, v),   obj.Metrics = behavior.Settings.merge_("Metrics", v, true); end
        function obj = set.QC(obj, v),        obj.QC = behavior.Settings.merge_("QC", v, true); end
        function obj = set.Compare(obj, v),   obj.Compare = behavior.Settings.merge_("Compare", v, true); end
        function obj = set.Detection(obj, v), obj.Detection = behavior.Settings.merge_("Detection", v, true); end
        function obj = set.NAFC(obj, v),      obj.NAFC = behavior.Settings.merge_("NAFC", v, true); end

        function st = toStruct(obj)
            % st = toStruct(obj)
            % Every setting as a plain struct, SettingsVersion first. Holds no
            % NaN or Inf, so jsonencode writes it exactly and fromStruct
            % reads it back equal.
            st = struct('SettingsVersion', behavior.Settings.SettingsVersion);
            for p = behavior.Settings.propertyNames_()
                st.(p) = obj.(p);
            end
        end

        function st = resultsStruct(obj)
            % st = resultsStruct(obj)
            % toStruct without the settings that do not change a result (QC
            % and Compare): what hash() names.
            st = rmfield(obj.toStruct(), cellstr(behavior.Settings.EXCLUDED_FROM_HASH_));
        end

        function h = hash(obj)
            % h = hash(obj)
            % Eight hex digits naming the results these settings produce:
            % behavior.hex8 of resultsStruct() written canonically (fields
            % sorted at every level, numbers %.17g). The same settings hash
            % the same on every machine and in every field order.
            h = behavior.hex8(char(behavior.Settings.canonical_(obj.resultsStruct())));
        end

        function p = problems(obj)
            % p = problems(obj)
            % What would stop these settings from producing a result, one
            % sentence per problem (string column; empty when they can run).
            p = strings(0, 1);

            if obj.Analysis ~= "Staircase"
                p(end+1, 1) = "Analysis """ + obj.Analysis + """ is not available in this version; use ""Staircase"".";
            end

            try
                psychophysics.TrialWindow.parse(obj.Window);
            catch ME
                p(end+1, 1) = "Window: " + string(ME.message);
            end

            if obj.StimulusTrialType == obj.CatchTrialType
                p(end+1, 1) = "StimulusTrialType and CatchTrialType are both " ...
                    + obj.StimulusTrialType + ", so no trial can be a catch trial.";
            end

            F = obj.Fit;
            crit = F.ThresholdCriterion;
            if ~(crit > 0 && crit < 1)
                p(end+1, 1) = "Fit.ThresholdCriterion must lie strictly between 0 and 1 (it is " + crit + ").";
            elseif F.CriterionScale == "absolute"
                lo = F.GuessRate;
                hi = 1 - F.LapseRate;
                if F.GuessFromCatchTrials
                    lo = 0;     % the guess rate is the data's, unknown here
                end
                if crit <= lo || (~F.EstimateLapse && crit >= hi)
                    p(end+1, 1) = sprintf(['Fit.ThresholdCriterion %g on the absolute scale lies outside ' ...
                        'the asymptotes [%g %g]; the fitted threshold would be NaN.'], crit, lo, hi);
                end
            end
            if F.GuessRate + F.LapseRate >= 1
                p(end+1, 1) = "Fit.GuessRate + Fit.LapseRate leave the psychometric function no span.";
            end

            if F.Engine == "psignifit"
                p(end+1, 1) = "psignifit: " + behavior.fit.Psignifit.whyUnavailable();
            end
        end

        function w = window(obj)
            % w = window(obj)
            % The trial window as a psychophysics.TrialWindow (throws on text
            % parse cannot read; problems() reports it without throwing).
            w = psychophysics.TrialWindow.parse(obj.Window);
        end

        function txt = describe(obj)
            % txt = describe(obj)
            % The settings in one sentence, for a status line or a header.
            if obj.Parameter == ""
                par = "the first candidate parameter";
            else
                par = obj.Parameter;
            end
            try
                win = lower(obj.window().describe());
            catch
                win = """" + obj.Window + """ (unreadable)";
            end

            excl = strings(1, 0);
            if obj.ExcludeTest, excl(end+1) = "test trials"; end
            if ~isempty(obj.ExcludeTrialTypes)
                excl(end+1) = "trial type " + strjoin(string(obj.ExcludeTrialTypes), "/");
            end
            if isempty(excl)
                exclText = "";
            else
                exclText = " without " + strjoin(excl, " or ");
            end

            S = obj.Staircase;
            thr = sprintf('%s of the last %d reversals', lower(S.ThresholdFormula), S.ThresholdFromLastNReversals);
            if S.ApplyWeightedCorrection
                thr = [thr ', weighted-step corrected'];
            end

            F = obj.Fit;
            if F.Enabled
                fit = sprintf('; %s %s fit read at %g (%s)', F.Engine, F.Shape, ...
                    F.ThresholdCriterion, F.CriterionScale);
            else
                fit = '; no psychometric fit';
            end

            txt = sprintf('%s on %s over %s%s; threshold = %s%s.', obj.Analysis, par, ...
                win, exclText, thr, fit);
            txt = string(txt);
        end

        function args = staircaseArgs(obj)
            % args = staircaseArgs(obj)
            % Name-value pairs for the psychophysics.Staircase CONSTRUCTOR.
            % The analysis settings that are properties rather than options
            % come from staircaseProperties.
            args = {'StimulusTrialType', behavior.Settings.trialTypeBit_(obj.StimulusTrialType), ...
                'CatchTrialType', behavior.Settings.trialTypeBit_(obj.CatchTrialType), ...
                'StaircaseDirection', obj.Staircase.Direction};
        end

        function p = staircaseProperties(obj)
            % p = staircaseProperties(obj)
            % The psychophysics.Staircase properties to SET after
            % construction, in the order to set them: each recomputes, so
            % the weighted steps go in before the flag that uses them. A
            % "find it" step ([]) is NaN on the object.
            S = obj.Staircase;
            p = struct( ...
                'ThresholdFromLastNReversals', S.ThresholdFromLastNReversals, ...
                'ThresholdFormula',            S.ThresholdFormula, ...
                'WeightedStepAfterYes',        localNaN(S.WeightedStepAfterYes), ...
                'WeightedStepAfterNo',         localNaN(S.WeightedStepAfterNo), ...
                'WeightedStepFieldYes',        S.WeightedStepFieldYes, ...
                'WeightedStepFieldNo',         S.WeightedStepFieldNo, ...
                'ApplyWeightedCorrection',     S.ApplyWeightedCorrection);
        end

        function args = metricsArgs(obj)
            % args = metricsArgs(obj)
            % Name-value pairs for psychophysics.SessionMetrics. The trial
            % window is not among them: behavior.Session.exclusionMask has
            % already folded it into ExcludedTrials.
            args = {'StimulusTrialType', behavior.Settings.trialTypeBit_(obj.StimulusTrialType), ...
                'CatchTrialType', behavior.Settings.trialTypeBit_(obj.CatchTrialType), ...
                'IncludeAborts', obj.IncludeAborts, ...
                'CorrectionMode', obj.Metrics.CorrectionMode, ...
                'infCorrection', obj.Metrics.infCorrection};
        end

        function args = fitArgs(obj)
            % args = fitArgs(obj)
            % Name-value pairs for psychophysics.Staircase.fitPsychometric.
            %
            % Direction is not a setting of its own: it follows the
            % staircase's. A "Down" staircase steps DOWN after a correct
            % response, so a higher level is easier and the function
            % increases with it; an "Up" staircase is the reverse (a masker
            % level, say). Asking separately would only allow the two to
            % disagree.
            F = obj.Fit;
            if obj.Staircase.Direction == "Up"
                direction = "decreasing";
            else
                direction = "increasing";
            end
            args = {'IncludeAborts', obj.IncludeAborts, ...
                'GuessFromCatchTrials', F.GuessFromCatchTrials, ...
                'Shape', F.Shape, ...
                'Direction', direction, ...
                'GuessRate', F.GuessRate, ...
                'LapseRate', F.LapseRate, ...
                'EstimateLapse', F.EstimateLapse, ...
                'ThresholdCriterion', F.ThresholdCriterion, ...
                'CriterionScale', F.CriterionScale, ...
                'Bootstrap', F.Bootstrap, ...
                'ConfidenceLevel', F.ConfidenceLevel, ...
                'RandomSeed', F.RandomSeed};
        end
    end

    methods (Static)
        function [s, warnings] = fromStruct(st)
            % [s, warnings] = behavior.Settings.fromStruct(st)
            % Settings from a saved struct (toStruct output, typically back
            % through jsondecode), forgivingly: column vectors are reshaped
            % to the declared shape, cellstr and char become string, unknown
            % fields are ignored, and a value that cannot be used keeps its
            % default. Each of those is reported in warnings rather than
            % thrown, since a saved project must open even when one setting
            % in it is stale. A SettingsVersion newer than this class's is
            % read the same way, with a warning that some settings may have
            % been lost.
            %
            % Returns:
            %   s        - behavior.Settings
            %   warnings - string column, one sentence per thing not used
            s = behavior.Settings();
            warnings = strings(0, 1);

            if ~isstruct(st) || ~isscalar(st)
                warnings(end+1, 1) = "Saved settings are not a struct; the defaults are used.";
                vprintf(1, 'behavior.Settings: %s', warnings(end))
                return
            end

            names = string(fieldnames(st));
            if ismember("SettingsVersion", names)
                v = double(st.SettingsVersion);
                if isscalar(v) && v > behavior.Settings.SettingsVersion
                    warnings(end+1, 1) = sprintf(['These settings were saved by a newer EPsych ' ...
                        '(SettingsVersion %g; this one reads %g): settings it does not know are ignored.'], ...
                        v, behavior.Settings.SettingsVersion);
                    vprintf(1, 'behavior.Settings: %s', warnings(end))
                end
            end

            % One slot per saved field, so nothing grows in the loop.
            props = behavior.Settings.propertyNames_();
            notes = cell(numel(names), 1);
            for i = 1:numel(names)
                f = names(i);
                if f == "SettingsVersion", continue, end
                if ~ismember(f, props)
                    notes{i} = "Ignored unknown setting """ + f + """.";
                    vprintf(2, 'behavior.Settings: %s', notes{i})
                    continue
                end
                if ismember(f, behavior.Settings.GROUPS_)
                    [val, notes{i}] = behavior.Settings.merge_(f, st.(f), false);
                    s.(f) = val;
                else
                    try
                        s.(f) = behavior.Settings.coerceTop_(f, st.(f));
                    catch ME
                        notes{i} = "Setting """ + f + """ could not be used (" ...
                            + string(ME.message) + "); the default is kept.";
                        vprintf(1, 'behavior.Settings: %s', notes{i})
                    end
                end
            end
            warnings = [warnings; vertcat(strings(0, 1), notes{:})];
        end
    end

    methods (Static, Access = private)
        function names = propertyNames_()
            % Every saved property, in declaration order.
            names = ["Analysis" "Parameter" "Window" "ExcludeTest" "ExcludeTrialTypes" ...
                "IncludeAborts" "StimulusTrialType" "CatchTrialType" behavior.Settings.GROUPS_];
        end

        function v = coerceTop_(name, v)
            % A top-level value as jsondecode hands it back, in its declared
            % shape; the property validators then do the checking.
            if iscellstr(v) || ischar(v) || isstring(v)
                v = string(v);
            end
            if name == "ExcludeTrialTypes"
                v = reshape(double(v), 1, []);
            end
        end

        function bm = trialTypeBit_(t)
            bm = epsych.BitMask.(sprintf('TrialType_%d', t));
        end

        function d = defaults_(group)
            % d = defaults_(group)
            % A group's default struct, built from its spec.
            spec = behavior.Settings.spec_(group);
            d = struct();
            for k = 1:numel(spec)
                d.(spec(k).Name) = spec(k).Default;
            end
        end

        function spec = spec_(group)
            % spec = spec_(group)
            % One row per field of a sub-struct: its name, default, and the
            % rule its value must satisfy. Kinds:
            %   text     - string scalar; Allowed = members ([] = any text)
            %   flag     - logical scalar
            %   number   - finite real scalar in Bounds (Open = exclusive)
            %   optional - [] or a number (NaN reads as [])
            %   pair     - 1x2 numbers in Bounds
            T = @(name, default, allowed) struct('Name', name, 'Default', default, ...
                'Kind', "text", 'Allowed', allowed, 'Bounds', [-Inf Inf], 'Open', false, 'Integer', false);
            L = @(name, default) struct('Name', name, 'Default', default, ...
                'Kind', "flag", 'Allowed', strings(1,0), 'Bounds', [-Inf Inf], 'Open', false, 'Integer', false);
            N = @(name, default, bounds, open, integer, kind) struct('Name', name, 'Default', default, ...
                'Kind', kind, 'Allowed', strings(1,0), 'Bounds', bounds, 'Open', open, 'Integer', integer);

            switch group
                case "Staircase"
                    spec = [ ...
                        T("Direction", "Down", ["Down" "Up"]), ...
                        N("ThresholdFromLastNReversals", 12, [1 Inf], false, true, "number"), ...
                        T("ThresholdFormula", "Mean", ["Mean" "GeometricMean"]), ...
                        L("ApplyWeightedCorrection", false), ...
                        N("WeightedStepAfterYes", [], [-Inf Inf], false, false, "optional"), ...
                        N("WeightedStepAfterNo", [], [-Inf Inf], false, false, "optional"), ...
                        T("WeightedStepFieldYes", "", strings(1,0)), ...
                        T("WeightedStepFieldNo", "", strings(1,0))];
                case "Fit"
                    spec = [ ...
                        L("Enabled", true), ...
                        T("Engine", "builtin", ["builtin" "psignifit"]), ...
                        T("Shape", "Logistic", ["Logistic" "Normal" "Weibull"]), ...
                        N("ThresholdCriterion", 0.5, [-Inf Inf], false, false, "number"), ...
                        T("CriterionScale", "relative", ["relative" "absolute"]), ...
                        L("GuessFromCatchTrials", false), ...
                        N("GuessRate", 0, [0 1], false, false, "number"), ...
                        N("LapseRate", 0, [0 1], false, false, "number"), ...
                        L("EstimateLapse", false), ...
                        N("Bootstrap", 0, [0 Inf], false, true, "number"), ...
                        N("ConfidenceLevel", 0.95, [0 1], true, false, "number"), ...
                        N("RandomSeed", 1, [0 Inf], false, true, "optional")];
                case "Metrics"
                    spec = [ ...
                        T("CorrectionMode", "clamp", ["none" "clamp" "halfcell" "loglinear"]), ...
                        N("infCorrection", [0.05 0.95], [0 1], true, false, "pair")];
                case "QC"
                    spec = [ ...
                        N("MinTrials", 30, [0 Inf], false, true, "number"), ...
                        N("MaxAbortRate", 0.30, [0 1], false, false, "number"), ...
                        N("MinReversals", 4, [0 Inf], false, true, "number")];
                case "Compare"
                    spec = [ ...
                        L("BootstrapCI", false), ...
                        N("ConfidenceLevel", 0.95, [0 1], true, false, "number"), ...
                        N("NumBoot", 1000, [1 Inf], false, true, "number")];
                case "Detection"
                    spec = repmat(L("x", false), 1, 0);
                case "NAFC"
                    spec = [ ...
                        N("NumAlternatives", 0, [0 Inf], false, true, "number"), ...
                        T("ChoiceField", "", strings(1,0)), ...
                        T("CorrectField", "TrialType", strings(1,0))];
                otherwise
                    error('behavior:Settings:UnknownGroup', 'Settings has no group "%s".', group);
            end
        end

        function [out, warnings] = merge_(group, v, strict)
            % [out, warnings] = merge_(group, v, strict)
            % A sub-struct merged over the group's defaults, every field
            % validated. strict (the constructor and property assignment)
            % throws on an unknown field or a bad value; otherwise (fromStruct)
            % the field keeps its default and the problem is reported.
            out = behavior.Settings.defaults_(group);
            warnings = strings(0, 1);
            if ~isstruct(v) || ~isscalar(v)
                msg = sprintf('Settings.%s must be a scalar struct.', group);
                if strict
                    error('behavior:Settings:InvalidValue', '%s', msg);
                end
                warnings(end+1, 1) = string(msg) + " The defaults are used.";
                vprintf(1, 'behavior.Settings: %s', warnings(end))
                return
            end

            spec = behavior.Settings.spec_(group);
            known = string({spec.Name});
            names = reshape(string(fieldnames(v)), 1, []);
            warnings = strings(numel(names), 1);
            for i = 1:numel(names)
                f = names(i);
                k = find(known == f, 1);
                if isempty(k)
                    k = find(strcmpi(known, f), 1);
                end
                if isempty(k)
                    if strict
                        error('behavior:Settings:UnknownField', ...
                            'Settings.%s has no field "%s".', group, f);
                    end
                    warnings(i) = "Ignored unknown setting """ + group + "." + f + """.";
                    vprintf(2, 'behavior.Settings: %s', warnings(i))
                    continue
                end
                [val, ok, rule] = behavior.Settings.coerce_(spec(k), v.(f));
                if ~ok
                    msg = sprintf('Settings.%s.%s must be %s.', group, spec(k).Name, rule);
                    if strict
                        error('behavior:Settings:InvalidValue', '%s', msg);
                    end
                    warnings(i) = string(msg) + " The default is kept.";
                    vprintf(1, 'behavior.Settings: %s', warnings(i))
                    continue
                end
                out.(spec(k).Name) = val;
            end
            warnings = warnings(warnings ~= "");
        end

        function [v, ok, rule] = coerce_(spec, v)
            % [v, ok, rule] = coerce_(spec, v)
            % One field's value in its canonical form, whether it satisfies
            % its rule, and the rule in words (for the error message).
            ok = false;
            switch spec.Kind
                case "text"
                    if isempty(spec.Allowed)
                        rule = 'text';
                    else
                        rule = ['one of "' char(strjoin(spec.Allowed, '", "')) '"'];
                    end
                    if ischar(v) && (isrow(v) || isempty(v)), v = string(v); end
                    if iscell(v) && isscalar(v) && (ischar(v{1}) || isstring(v{1})), v = string(v{1}); end
                    if ~(isstring(v) && isscalar(v)) || ismissing(v), return, end
                    if ~isempty(spec.Allowed)
                        k = find(strcmpi(spec.Allowed, v), 1);
                        if isempty(k), return, end
                        v = spec.Allowed(k);     % canonical spelling
                    end
                    ok = true;

                case "flag"
                    rule = 'true or false';
                    if (islogical(v) || isnumeric(v)) && isscalar(v) && (v == 0 || v == 1)
                        v = logical(v);
                        ok = true;
                    end

                case {"number", "optional"}
                    rule = behavior.Settings.numberRule_(spec);
                    if spec.Kind == "optional"
                        rule = ['[] or ' rule];
                        if isempty(v) || (isnumeric(v) && isscalar(v) && isnan(v))
                            v = [];
                            ok = true;
                            return
                        end
                    end
                    if ~(isnumeric(v) || islogical(v)) || ~isscalar(v), return, end
                    v = double(v);
                    ok = behavior.Settings.inBounds_(spec, v);

                case "pair"
                    rule = ['two numbers, each ' behavior.Settings.numberRule_(spec)];
                    if ~isnumeric(v) || numel(v) ~= 2, return, end
                    v = reshape(double(v), 1, 2);
                    ok = all(arrayfun(@(x) behavior.Settings.inBounds_(spec, x), v));
            end
        end

        function ok = inBounds_(spec, x)
            lo = spec.Bounds(1);
            hi = spec.Bounds(2);
            ok = isreal(x) && isfinite(x);
            if spec.Open
                ok = ok && x > lo && x < hi;
            else
                ok = ok && x >= lo && x <= hi;
            end
            if spec.Integer
                ok = ok && x == fix(x);
            end
        end

        function rule = numberRule_(spec)
            if spec.Integer, rule = 'a finite integer'; else, rule = 'a finite number'; end
            lo = spec.Bounds(1);
            hi = spec.Bounds(2);
            if spec.Open
                rule = sprintf('%s strictly between %g and %g', rule, lo, hi);
            elseif isfinite(lo) && isfinite(hi)
                rule = sprintf('%s from %g to %g', rule, lo, hi);
            elseif isfinite(lo)
                rule = sprintf('%s of at least %g', rule, lo);
            end
        end

        function txt = canonical_(v)
            % txt = canonical_(v)
            % Text that names a value exactly and only by its content: struct
            % fields sorted, numbers %.17g (which round-trips every double),
            % text JSON-escaped, every empty written "[]" (a JSON round trip
            % cannot tell [] from zeros(1,0), so neither may the hash).
            if isstruct(v)
                if isscalar(v)
                    names = sort(string(fieldnames(v)));
                    parts = strings(1, numel(names));
                    for k = 1:numel(names)
                        parts(k) = jsonencode(names(k)) + ":" + behavior.Settings.canonical_(v.(names(k)));
                    end
                    txt = "{" + strjoin(parts, ",") + "}";
                else
                    parts = arrayfun(@behavior.Settings.canonical_, v(:)');
                    txt = "[" + strjoin(parts, ",") + "]";
                end
            elseif isempty(v)
                txt = "[]";
            elseif ischar(v) || isstring(v) || iscellstr(v)
                v = string(v);
                txt = jsonencode(v(:)');
                if ~isscalar(v), txt = localSize(v) + txt; end
            elseif islogical(v)
                words = ["false" "true"];
                txt = strjoin(words(double(v(:)') + 1), ",");
                if ~isscalar(v), txt = localSize(v) + "[" + txt + "]"; end
            elseif isnumeric(v)
                txt = strjoin(compose("%.17g", double(v(:)')), ",");
                if ~isscalar(v), txt = localSize(v) + "[" + txt + "]"; end
            else
                error('behavior:Settings:Uncanonical', 'Cannot write a %s canonically.', class(v));
            end
        end
    end
end




function v = localNaN(v)
% [] ("find it") as the NaN psychophysics.Staircase reads it as.
if isempty(v), v = NaN; end
end




function s = localSize(v)
s = string(strjoin(compose("%d", size(v)), "x"));
end
