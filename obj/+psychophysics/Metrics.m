classdef Metrics
    % psychophysics.Metrics
    % Stateless signal-detection arithmetic, shared by every analysis class.
    %
    % Metrics is the single home for the psychophysics formulas the rest of
    % the toolbox reuses: the z-transform, d', criterion, likelihood-ratio
    % bias, the nonparametric A' and B'', and proportion correct. It holds no
    % data, no runtime, and no state -- every method is static and pure, so
    % the same call works online, offline, in a test, or at the command line.
    %
    % Rates of exactly 0 or 1 send the z-transform to infinity, and the
    % correction for that is a scientific choice rather than a detail, so it
    % is named at every call:
    %
    %   "none"       rates as given; 0 and 1 give -Inf and +Inf
    %   "clamp"      rates pulled into Bounds (default [0.01 0.99])
    %   "halfcell"   0 -> 1/(2N), 1 -> 1-1/(2N)    (Macmillan & Kaplan 1985)
    %   "loglinear"  every rate -> (nYes+0.5)/(N+1) (Hautus 1995)
    %
    % The last two depend on how many trials are behind a rate, so they need
    % NSignal/NNoise; asking for one without counts is an error rather than a
    % silent fall back to a clamp. fromCounts is the entry point that always
    % has them.
    %
    % Everything broadcasts: a vector of hit rates pairs with a scalar false
    % alarm rate. NaN propagates as NaN -- an undefined rate is never turned
    % into a bound, which is the difference between this class and the
    % min/max clamp it replaces.
    %
    % The core needs no Statistics Toolbox: z is built on erfcinv.
    %
    % An aborted trial is the one judgement call in the denominators, and it
    % is an option rather than a convention: IncludeAborts defaults to false,
    % so a rate describes the trials the subject actually answered. See
    % rateDenominator.
    %
    % Methods (rates in):
    %   z / zinv          - Inverse and forward standard normal CDF
    %   rate              - num./den, NaN where den == 0
    %   rateDenominator   - Scored trials, plus aborts if they are counted
    %   correctRates      - The correction itself, so a caller can see it
    %   dprime            - Sensitivity d' = z(H) - z(F)
    %   criterion         - c = -(z(H) + z(F))/2
    %   criterionRelative - c' = c/d', comparable across sensitivities
    %   lnBeta / beta     - Likelihood-ratio criterion
    %   aprime            - Nonparametric sensitivity A' (Grier 1971)
    %   bprimeprime       - Nonparametric bias B'' (Grier 1971)
    %   percentCorrect    - Balanced proportion correct, (H + 1 - F)/2
    %   dprime2AFC        - d' from 2AFC proportion correct
    %
    % Methods (counts in):
    %   fromCounts        - Every metric above from nHit/nMiss/nFA/nCR
    %
    % Example:
    %   psychophysics.Metrics.dprime(0.9, 0.1)              % 2.5631
    %   psychophysics.Metrics.dprime([0.6 0.8 1], 0.1, ...
    %       Correction="loglinear", NSignal=20, NNoise=20)
    %   S = psychophysics.Metrics.fromCounts(18, 7, 3, 22, Correction="loglinear");
    %
    % See also: psychophysics.SessionMetrics, psychophysics.Detection,
    % psychophysics.TrialWindow,
    % documentation/psychophysics/psychophysics_Metrics.md

    properties (Constant)
        % DEFAULT_BOUNDS - Clamp applied by the "clamp" correction.
        DEFAULT_BOUNDS (1,2) double = [0.01 0.99]

        % CORRECTIONS - Every correction mode, for validation messages and
        % for a GUI that offers the choice. The mustBeMember validators on
        % each method must list the same names; smoke_test_metrics checks
        % that they do, because a validator cannot reference a class
        % constant.
        CORRECTIONS (1,:) string = ["none","clamp","halfcell","loglinear"]
    end

    methods (Access = private)
        function obj = Metrics()
            % Not instantiable: psychophysics.Metrics is arithmetic, not an
            % object. The class is a namespace, and one that handed out empty
            % instances would invite someone to give it state.
        end
    end

    methods (Static)
        function n = z(p)
            % n = psychophysics.Metrics.z(p)
            % Inverse standard normal CDF -- the "z-transform" of a rate.
            %
            %       z(p) = -sqrt(2) * erfcinv(2*p)
            %
            % Built on erfcinv, which is core MATLAB, so d' and criterion no
            % longer require the Statistics Toolbox. Agreement with the
            % toolbox norminv is exact to double precision and is asserted by
            % tmp/smoke_test_metrics.m wherever the toolbox is installed.
            %
            % The name is z rather than norminv deliberately: an unqualified
            % norminv(p) inside a classdef resolves to the toolbox function
            % rather than to the static method, which is the only reason the
            % psychophysics.Detection.norminv this replaces ever worked.
            %
            % No correction is applied here. p == 0 gives -Inf and p == 1
            % gives +Inf, which is the honest answer; NaN yields NaN, and a p
            % outside [0 1] yields NaN.
            %
            % Parameters:
            %   p - Probabilities, any size.
            %
            % Returns:
            %   n - z-scores, the same size as p.
            arguments
                p double
            end
            n = -sqrt(2) .* erfcinv(2 .* p);
        end

        function p = zinv(n)
            % p = psychophysics.Metrics.zinv(n)
            % Forward standard normal CDF, the inverse of z.
            %
            %       zinv(n) = 0.5 * erfc(-n/sqrt(2))
            %
            % Present so a caller can go the other way without the toolbox.
            % Generating the rates a known d' and criterion would produce is
            % how tmp/smoke_test_metrics.m checks the arithmetic against
            % theory rather than against itself.
            %
            % Parameters:
            %   n - z-scores, any size.
            %
            % Returns:
            %   p - Probabilities, the same size as n.
            arguments
                n double
            end
            p = 0.5 .* erfc(-n ./ sqrt(2));
        end

        function r = rate(num, den)
            % r = psychophysics.Metrics.rate(num, den)
            % Proportion, or NaN wherever the denominator is zero.
            %
            % "No trials of that kind" is not a rate of zero, and every
            % downstream metric depends on the difference surviving. Unlike
            % the scalar helpers it replaces this is element-wise and
            % broadcasts, so a row of per-level counts divides by a row of
            % per-level totals in one call.
            %
            % Parameters:
            %   num - Numerator counts.
            %   den - Denominator counts; broadcasts against num.
            %
            % Returns:
            %   r - Proportions, NaN where den == 0.
            arguments
                num double
                den double
            end
            [num, den] = psychophysics.Metrics.broadcast_(num, den);
            r = num ./ den;
            r(den == 0) = NaN;
        end

        function n = rateDenominator(nScored, nAbort, includeAborts)
            % n = psychophysics.Metrics.rateDenominator(nScored, nAbort, includeAborts)
            % The denominator a hit or false alarm rate should use.
            %
            % An aborted trial is one the subject never answered, and whether
            % it counts against the rate is a paradigm's decision rather than
            % a fact about the data: scoring it as a failure to respond makes
            % it an error, and leaving it out makes the rate a statement
            % about the trials that were actually completed.
            %
            % EPsych defaults to leaving them out -- an abort is usually a
            % lapse of engagement rather than a wrong answer, and including
            % them makes a distracted session look insensitive rather than
            % incomplete. Every class that computes a rate takes an
            % IncludeAborts option and routes through this one function, so
            % the convention is stated in one place instead of four.
            %
            % Parameters:
            %   nScored       - Answered trials (Hit + Miss, or FA + CR).
            %   nAbort        - Aborted trials of the same kind.
            %   includeAborts - Add them to the denominator.
            %
            % Returns:
            %   n - The denominator, broadcast to the common size.
            arguments
                nScored double
                nAbort double
                includeAborts (1,1) logical
            end
            [nScored, nAbort] = psychophysics.Metrics.broadcast_(nScored, nAbort);
            if includeAborts
                n = nScored + nAbort;
            else
                n = nScored;
            end
        end

        function [H, F] = correctRates(H, F, opts)
            % [H, F] = psychophysics.Metrics.correctRates(H, F, Name=Value)
            % Apply the correction for rates of 0 and 1, and return what the
            % z-transform will actually see.
            %
            % Public because "which rates went in" is the first question
            % asked of a surprising d'. Every metric in this class routes
            % through it, so what it returns is what was used.
            %
            % Parameters:
            %   H, F       - Hit and false alarm rates; broadcast together.
            %   Correction - "none", "clamp", "halfcell", or "loglinear".
            %   Bounds     - [lo hi] for "clamp". Default [0.01 0.99].
            %   NSignal    - Trials behind H; the N-dependent modes need it.
            %   NNoise     - Trials behind F; the N-dependent modes need it.
            %
            % Returns:
            %   H, F - Corrected rates. NaN in gives NaN out, always.
            arguments
                H double
                F double
                opts.Correction (1,1) string {mustBeMember(opts.Correction, ...
                    ["none","clamp","halfcell","loglinear"])} = "clamp"
                opts.Bounds (1,2) double {mustBeInRange(opts.Bounds,0,1,"exclusive")} = [0.01 0.99]
                opts.NSignal double = []
                opts.NNoise double = []
            end
            [H, F] = psychophysics.Metrics.applyCorrection_(H, F, opts);
        end

        function d = dprime(H, F, opts)
            % d = psychophysics.Metrics.dprime(H, F, Name=Value)
            % Sensitivity index d' for a yes/no or go/no-go task.
            %
            %       d' = z(H) - z(F)
            %
            % The distance between the noise and signal-plus-noise
            % distributions in standard deviations of the noise, assuming
            % both are Gaussian with equal variance. 0 is chance, 1 a modest
            % but real discrimination, and above about 4 the number is
            % governed by whichever correction was applied rather than by the
            % data.
            %
            % Contrast: aprime assumes no distribution and needs no
            % correction; criterion answers "how willing to say yes", which
            % d' deliberately does not.
            %
            % Rates broadcast, so a vector of hit rates may be paired with a
            % scalar false alarm rate. NaN in either rate yields NaN.
            %
            % Parameters:
            %   H, F                    - Hit and false alarm rates.
            %   Correction              - See correctRates.
            %   Bounds, NSignal, NNoise - See correctRates.
            %
            % Returns:
            %   d - d', broadcast to the common size of the inputs.
            %
            %   Green DM, Swets JA (1966) Signal Detection Theory and
            %   Psychophysics. Wiley.
            %   Macmillan NA, Creelman CD (2005) Detection Theory: A User's
            %   Guide, 2nd ed. Erlbaum.
            arguments
                H double
                F double
                opts.Correction (1,1) string {mustBeMember(opts.Correction, ...
                    ["none","clamp","halfcell","loglinear"])} = "clamp"
                opts.Bounds (1,2) double {mustBeInRange(opts.Bounds,0,1,"exclusive")} = [0.01 0.99]
                opts.NSignal double = []
                opts.NNoise double = []
            end
            [H, F] = psychophysics.Metrics.applyCorrection_(H, F, opts);
            d = psychophysics.Metrics.z(H) - psychophysics.Metrics.z(F);
        end

        function c = criterion(H, F, opts)
            % c = psychophysics.Metrics.criterion(H, F, Name=Value)
            % Decision criterion c, in the same units as d'.
            %
            %       c = -(z(H) + z(F)) / 2
            %
            % Where the subject placed the decision boundary: 0 is unbiased,
            % positive is conservative (reluctant to say yes), negative is
            % liberal. This is the quantity psychophysics.Detection calls
            % "bias" and SessionMetrics reports as Criterion; the name here is
            % the unambiguous one, since "bias" also names beta and B''.
            %
            % Parameters and returns as dprime.
            %
            %   Macmillan NA, Creelman CD (2005) Detection Theory: A User's
            %   Guide, 2nd ed. Erlbaum.
            arguments
                H double
                F double
                opts.Correction (1,1) string {mustBeMember(opts.Correction, ...
                    ["none","clamp","halfcell","loglinear"])} = "clamp"
                opts.Bounds (1,2) double {mustBeInRange(opts.Bounds,0,1,"exclusive")} = [0.01 0.99]
                opts.NSignal double = []
                opts.NNoise double = []
            end
            [H, F] = psychophysics.Metrics.applyCorrection_(H, F, opts);
            c = -(psychophysics.Metrics.z(H) + psychophysics.Metrics.z(F)) ./ 2;
        end

        function cr = criterionRelative(H, F, opts)
            % cr = psychophysics.Metrics.criterionRelative(H, F, Name=Value)
            % Relative criterion c' = c / d'.
            %
            % Criterion expressed as a fraction of the subject's own
            % sensitivity, which is what makes bias comparable between
            % subjects or sessions whose d' differ. Undefined at d' = 0: 0/0
            % gives NaN and a nonzero c over zero d' gives +/-Inf, both of
            % which are reported rather than papered over.
            %
            % Parameters and returns as dprime.
            arguments
                H double
                F double
                opts.Correction (1,1) string {mustBeMember(opts.Correction, ...
                    ["none","clamp","halfcell","loglinear"])} = "clamp"
                opts.Bounds (1,2) double {mustBeInRange(opts.Bounds,0,1,"exclusive")} = [0.01 0.99]
                opts.NSignal double = []
                opts.NNoise double = []
            end
            [H, F] = psychophysics.Metrics.applyCorrection_(H, F, opts);
            zH = psychophysics.Metrics.z(H);
            zF = psychophysics.Metrics.z(F);
            cr = (-(zH + zF) ./ 2) ./ (zH - zF);
        end

        function b = lnBeta(H, F, opts)
            % b = psychophysics.Metrics.lnBeta(H, F, Name=Value)
            % Log of the likelihood-ratio criterion beta.
            %
            %       ln(beta) = (z(F)^2 - z(H)^2) / 2  ==  c * d'
            %
            % The classical bias measure, in its numerically stable form: 0
            % is unbiased, positive conservative. Reported in logs rather than
            % raw because beta itself spans orders of magnitude.
            %
            % Parameters and returns as dprime.
            arguments
                H double
                F double
                opts.Correction (1,1) string {mustBeMember(opts.Correction, ...
                    ["none","clamp","halfcell","loglinear"])} = "clamp"
                opts.Bounds (1,2) double {mustBeInRange(opts.Bounds,0,1,"exclusive")} = [0.01 0.99]
                opts.NSignal double = []
                opts.NNoise double = []
            end
            [H, F] = psychophysics.Metrics.applyCorrection_(H, F, opts);
            zH = psychophysics.Metrics.z(H);
            zF = psychophysics.Metrics.z(F);
            b = (zF.^2 - zH.^2) ./ 2;
        end

        function b = beta(H, F, opts)
            % b = psychophysics.Metrics.beta(H, F, Name=Value)
            % Likelihood-ratio criterion beta == exp(lnBeta).
            %
            % A wrapper, present because readers coming from the literature
            % look for the name. Prefer lnBeta for anything averaged or
            % plotted, since beta spans orders of magnitude.
            %
            % Parameters and returns as dprime.
            arguments
                H double
                F double
                opts.Correction (1,1) string {mustBeMember(opts.Correction, ...
                    ["none","clamp","halfcell","loglinear"])} = "clamp"
                opts.Bounds (1,2) double {mustBeInRange(opts.Bounds,0,1,"exclusive")} = [0.01 0.99]
                opts.NSignal double = []
                opts.NNoise double = []
            end
            args = namedargs2cell(opts);
            b = exp(psychophysics.Metrics.lnBeta(H, F, args{:}));
        end

        function a = aprime(H, F)
            % a = psychophysics.Metrics.aprime(H, F)
            % Nonparametric sensitivity index A' (Grier 1971).
            %
            %       A' = 0.5 + sign(H-F) * ((H-F)^2 + |H-F|)
            %                              / (4*max(H,F) - 4*H*F)
            %
            % A' runs from 0 to 1: 0.5 is chance, 1.0 perfect
            % discrimination, and below 0.5 a reversed response mapping. It
            % reads as the area under the ROC curve through the single
            % observed (F,H) point, i.e. the probability of a correct answer
            % in an equivalent 2AFC task.
            %
            % Unlike dprime this assumes no distribution and takes no
            % correction: rates of exactly 0 or 1 are defined, which is what
            % makes A' the safer summary for the small trial counts and
            % extreme rates a single session produces.
            %
            % Inputs broadcast, so a vector of hit rates may be paired with a
            % scalar false alarm rate. NaN rates yield NaN.
            %
            % Parameters:
            %   H, F - Hit and false alarm rates.
            %
            % Returns:
            %   a - A', broadcast to the common size of the inputs.
            %
            %   Grier JB (1971) Nonparametric indexes for sensitivity and
            %   bias: computing formulas. Psychol Bull 75(6):424-429.
            arguments
                H double
                F double
            end
            d = H - F;
            a = 0.5 + sign(d) .* (d.^2 + abs(d)) ./ (4.*max(H,F) - 4.*H.*F);

            % H == F is chance whatever the rates are; taken separately
            % because the denominator also vanishes at H == F == 0 or 1.
            a(d == 0) = 0.5;
        end

        function b = bprimeprime(H, F)
            % b = psychophysics.Metrics.bprimeprime(H, F)
            % Nonparametric response bias B'' (Grier 1971).
            %
            %       B'' = sign(H-F) * ( H(1-H) - F(1-F) )
            %                       / ( H(1-H) + F(1-F) )
            %
            % Runs from -1 (extremely liberal) through 0 (no bias) to +1
            % (extremely conservative). It is to criterion what A' is to d':
            % distribution-free, and defined at rates of exactly 0 and 1, so
            % it takes no correction and stays usable at the small trial
            % counts a single session produces.
            %
            % Where both rates are 0 or 1 the denominator also vanishes;
            % those cases are reported as 0, since rates that extreme carry
            % no evidence about bias either way.
            %
            % Inputs broadcast. NaN rates yield NaN.
            %
            % Parameters:
            %   H, F - Hit and false alarm rates.
            %
            % Returns:
            %   b - B'', broadcast to the common size of the inputs.
            %
            %   Grier JB (1971) Nonparametric indexes for sensitivity and
            %   bias: computing formulas. Psychol Bull 75(6):424-429.
            arguments
                H double
                F double
            end
            vH = H .* (1 - H);
            vF = F .* (1 - F);
            b = sign(H - F) .* (vH - vF) ./ (vH + vF);
            b(vH + vF == 0) = 0;
        end

        function pc = percentCorrect(H, F)
            % pc = psychophysics.Metrics.percentCorrect(H, F)
            % Balanced proportion correct.
            %
            %       pc = (H + (1 - F)) / 2  ==  0.5 + (H - F)/2
            %
            % The proportion correct an equal number of signal and catch
            % trials would have produced. This is a rate-derived, prior-free
            % quantity, and it is NOT the observed proportion correct
            % (nHit + nCR)/nScored that SessionMetrics reports: with 90
            % stimulus and 10 catch trials the two differ, and the difference
            % is the trial mix, not the subject. fromCounts returns both,
            % named apart.
            %
            % Returns a fraction, not a percentage, like every rate in this
            % package. NaN rates yield NaN.
            %
            % Parameters:
            %   H, F - Hit and false alarm rates.
            %
            % Returns:
            %   pc - Balanced proportion correct.
            arguments
                H double
                F double
            end
            pc = 0.5 + (H - F) ./ 2;
        end

        function d = dprime2AFC(pc, opts)
            % d = psychophysics.Metrics.dprime2AFC(pc, Name=Value)
            % Sensitivity from two-alternative forced choice accuracy.
            %
            %       d' = sqrt(2) * z(pc)
            %
            % For an unbiased 2AFC task, where chance is 0.5 and there are no
            % separate hit and false alarm rates to combine. Corrections
            % apply to pc exactly as they do to any rate, so NSignal here
            % means the number of 2AFC trials.
            %
            % Parameters:
            %   pc         - Proportion correct.
            %   Correction - See correctRates.
            %   Bounds     - [lo hi] for "clamp".
            %   NSignal    - Trials behind pc; the N-dependent modes need it.
            %
            % Returns:
            %   d - d', the same size as pc.
            arguments
                pc double
                opts.Correction (1,1) string {mustBeMember(opts.Correction, ...
                    ["none","clamp","halfcell","loglinear"])} = "clamp"
                opts.Bounds (1,2) double {mustBeInRange(opts.Bounds,0,1,"exclusive")} = [0.01 0.99]
                opts.NSignal double = []
            end
            pc = psychophysics.Metrics.correctOne_(pc, opts.NSignal, ...
                opts.Correction, opts.Bounds, "NSignal");
            d = sqrt(2) .* psychophysics.Metrics.z(pc);
        end

        function S = fromCounts(nHit, nMiss, nFA, nCR, opts)
            % S = psychophysics.Metrics.fromCounts(nHit, nMiss, nFA, nCR, Name=Value)
            % Every metric this class computes, from raw outcome counts.
            %
            % This is the entry point the N-dependent corrections were added
            % for: the counts are already here, so "loglinear" and "halfcell"
            % need nothing extra, and no rate has to be un-divided to recover
            % the trial numbers behind it.
            %
            % All four counts broadcast, so a row of per-level hit counts
            % against a scalar catch-trial pair returns a row of every metric
            % in one call.
            %
            % Denominators are explicit, and aborts are the one judgement
            % call in them: by default the hit rate is nHit/(nHit+nMiss) and
            % the false alarm rate nFA/(nFA+nCR), counting only the trials
            % the subject answered. Pass IncludeAborts=true with the abort
            % counts to score them as failures to respond instead. See
            % rateDenominator for why the default is to leave them out.
            %
            % Parameters:
            %   nHit, nMiss   - Signal-trial outcome counts.
            %   nFA, nCR      - Catch-trial outcome counts.
            %   AbortSignal   - Aborted stimulus trials. Default 0.
            %   AbortNoise    - Aborted catch trials. Default 0.
            %   IncludeAborts - Count aborts against the rates. Default false.
            %   Correction    - See correctRates. Default "clamp".
            %   Bounds        - [lo hi] for "clamp". Default [0.01 0.99].
            %
            % Returns:
            %   S - Struct with fields:
            %       N              - Hit, Miss, FalseAlarm, CorrectReject,
            %                        AbortSignal, AbortNoise, Signal, Noise,
            %                        Total. Signal and Noise are the
            %                        denominators actually used.
            %       Rate           - Hit, Miss, FalseAlarm, CorrectReject,
            %                        Correct (all observed, uncorrected)
            %       RateCorrected  - Hit, FalseAlarm as the z-transform saw them
            %       Correction     - Mode applied
            %       Bounds         - Bounds applied, for "clamp"
            %       IncludeAborts  - Aborts policy applied
            %       DPrime, Criterion, CriterionRelative, LnBeta, Beta
            %       APrime, BPrimePrime
            %       PercentCorrect         - observed, (nHit+nCR)/(nSignal+nNoise)
            %       PercentCorrectBalanced - (H + 1 - F)/2
            arguments
                nHit  double
                nMiss double
                nFA   double
                nCR   double
                opts.AbortSignal double = 0
                opts.AbortNoise double = 0
                opts.IncludeAborts (1,1) logical = false
                opts.Correction (1,1) string {mustBeMember(opts.Correction, ...
                    ["none","clamp","halfcell","loglinear"])} = "clamp"
                opts.Bounds (1,2) double {mustBeInRange(opts.Bounds,0,1,"exclusive")} = [0.01 0.99]
            end
            [nHit, nMiss, nFA, nCR, aSig, aNoi] = psychophysics.Metrics.broadcast_( ...
                nHit, nMiss, nFA, nCR, opts.AbortSignal, opts.AbortNoise);
            nSignal = psychophysics.Metrics.rateDenominator(nHit + nMiss, aSig, opts.IncludeAborts);
            nNoise  = psychophysics.Metrics.rateDenominator(nFA  + nCR,  aNoi, opts.IncludeAborts);

            S.N = struct('Hit', nHit, 'Miss', nMiss, ...
                'FalseAlarm', nFA, 'CorrectReject', nCR, ...
                'AbortSignal', aSig, 'AbortNoise', aNoi, ...
                'Signal', nSignal, 'Noise', nNoise, 'Total', nSignal + nNoise);

            H = psychophysics.Metrics.rate(nHit, nSignal);
            F = psychophysics.Metrics.rate(nFA,  nNoise);

            S.Rate = struct( ...
                'Hit',           H, ...
                'Miss',          psychophysics.Metrics.rate(nMiss, nSignal), ...
                'FalseAlarm',    F, ...
                'CorrectReject', psychophysics.Metrics.rate(nCR, nNoise), ...
                'Correct',       psychophysics.Metrics.rate(nHit + nCR, nSignal + nNoise));

            [Hc, Fc] = psychophysics.Metrics.correctRates(H, F, ...
                Correction=opts.Correction, Bounds=opts.Bounds, ...
                NSignal=nSignal, NNoise=nNoise);
            S.RateCorrected = struct('Hit', Hc, 'FalseAlarm', Fc);
            S.Correction    = opts.Correction;
            S.Bounds        = opts.Bounds;
            S.IncludeAborts = opts.IncludeAborts;

            % The rates are corrected already, so the metrics take them as
            % they are rather than routing through the public methods and
            % correcting a second time.
            zH = psychophysics.Metrics.z(Hc);
            zF = psychophysics.Metrics.z(Fc);
            S.DPrime            = zH - zF;
            S.Criterion         = -(zH + zF) ./ 2;
            S.CriterionRelative = S.Criterion ./ S.DPrime;
            S.LnBeta            = (zF.^2 - zH.^2) ./ 2;
            S.Beta              = exp(S.LnBeta);

            % A' and B'' are defined at 0 and 1, so they take the observed
            % rates; correcting those would only bias them toward chance.
            S.APrime      = psychophysics.Metrics.aprime(H, F);
            S.BPrimePrime = psychophysics.Metrics.bprimeprime(H, F);

            S.PercentCorrect         = S.Rate.Correct;
            S.PercentCorrectBalanced = psychophysics.Metrics.percentCorrect(H, F);
        end
    end

    methods (Static, Access = private)
        function [H, F] = applyCorrection_(H, F, opts)
            % The single implementation behind correctRates and every metric.
            H = psychophysics.Metrics.correctOne_(H, opts.NSignal, ...
                opts.Correction, opts.Bounds, "NSignal");
            F = psychophysics.Metrics.correctOne_(F, opts.NNoise, ...
                opts.Correction, opts.Bounds, "NNoise");
        end

        function p = correctOne_(p, n, mode, bounds, countName)
            % Correct one rate. Split out from applyCorrection_ so the hit
            % and false alarm rates each answer to their own trial count, and
            % so dprime2AFC -- which has only one rate -- shares the code.
            switch mode
                case "none"
                    return

                case "clamp"
                    p = psychophysics.Metrics.clampKeepNaN_(p, bounds(1), bounds(2));
                    return
            end

            % Past here the correction is N-dependent. It errors rather than
            % falling back to a clamp: a silent fallback is how this toolbox
            % ended up with three correction defaults nobody chose.
            if isempty(n)
                error('psychophysics:Metrics:CountsRequired', ...
                    ['The "%s" correction needs the trial count behind each rate; ' ...
                     'supply %s, or use psychophysics.Metrics.fromCounts.'], mode, countName);
            end

            [p, n] = psychophysics.Metrics.broadcast_(p, n);

            switch mode
                case "halfcell"
                    % Only 0 and 1 move: an interior k/N already lies inside
                    % [0.5/N, 1-0.5/N], so this clamp is the extremes-only
                    % rule written in a form that vectorizes.
                    p = psychophysics.Metrics.clampKeepNaN_(p, 0.5./n, 1 - 0.5./n);

                case "loglinear"
                    p = (p .* n + 0.5) ./ (n + 1);
            end

            % A rate with no trials behind it stays undefined under every
            % correction: 0.5/0 is Inf, and (0*0+0.5)/(0+1) would report a
            % fabricated 50%.
            p(n == 0) = NaN;
        end

        function p = clampKeepNaN_(p, lo, hi)
            % Pull p into [lo hi] without inventing a value for NaN.
            %
            % min/max treat NaN as missing -- min(NaN,0.99) is 0.99 -- so the
            % obvious max(min(p,hi),lo) turns an undefined rate into a bound.
            % That is the bug this replaces. Comparison is false at NaN, so
            % indexed assignment leaves it alone. The bounds may be arrays,
            % since the N-dependent corrections make them so.
            [p, lo, hi] = psychophysics.Metrics.broadcast_(p, lo, hi);
            below = p < lo;   p(below) = lo(below);
            above = p > hi;   p(above) = hi(above);
        end

        function varargout = broadcast_(varargin)
            % Expand every input to their common implicit-expansion size.
            %
            % Built by summing zeros(size(...)) so that no value
            % participates and neither NaN nor Inf can leak from one argument
            % into another; incompatible sizes raise MATLAB's own error.
            sz = zeros(size(varargin{1}));
            for i = 2:nargin
                sz = sz + zeros(size(varargin{i}));
            end
            varargout = cellfun(@(v) v + sz, varargin, UniformOutput=false);
        end
    end
end
