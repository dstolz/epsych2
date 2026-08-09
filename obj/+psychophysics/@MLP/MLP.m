classdef MLP < psychophysics.Psych
    % mlp = psychophysics.MLP(source, Parameter, AlphaRange=[min max])
    % mlp = psychophysics.MLP(source, Parameter, AlphaRange=[min max], Name=Value)
    % Three-parameter Bayesian maximum-likelihood procedure for estimating
    % psychometric functions. Maintains a posterior over threshold (alpha),
    % slope (beta), and lapse rate (lambda) and adaptively places the next
    % stimulus at one of up to four "sweet points" — signal strengths that
    % minimize the expected variance of each parameter estimate.
    %
    % The guess rate (gamma) is assumed fixed (e.g., 0.5 for 2-AFC). The
    % posterior is updated via Bayes' rule after each trial. Two sweet-point
    % selection rules are supported: uniform-random draw or a hybrid N-down
    % M-up staircase that cycles through sweet points in order.
    %
    % Supports two operating modes:
    %   Online mode  - Construct with a Runtime object to listen for NewData
    %       events and update automatically as trials are completed.
    %   Offline mode - Construct with a per-trial DATA struct array to analyze
    %       saved sessions without attaching event listeners.
    %
    % Key properties:
    %   AlphaRange           - [min max] for alpha (threshold) grid. Required.
    %   PsychometricFunction - "Logistic" (default) or "Weibull".
    %   GuessRate            - Fixed lower asymptote gamma; 0.5 for 2-AFC.
    %   MaxSignalStrength    - Signal strength for the lambda-sweet proxy.
    %   SweetPointRule       - "Random" (default) or "UpDown".
    %   UpDownRule           - [N M] for N-down M-up rule (default [4 1]).
    %
    % Key Results fields:
    %   NextLevel            - Recommended signal strength for the next trial.
    %   AlphaEstimate        - ML estimate of threshold alpha.
    %   BetaEstimate         - ML estimate of slope beta.
    %   LapseEstimate        - ML estimate of lapse rate lambda.
    %   SweetPoints          - Sweet-point signal strengths (4x1 Logistic, 3x1 Weibull).
    %   SweetPointPcorrect   - Proportion correct P at each sweet point.
    %   Posterior            - Normalized 3D posterior over (alpha, beta, lambda).
    %   FittedPsychFn        - Struct with fields x and P for the fitted curve.
    %
    % Example:
    %   mlp = psychophysics.MLP(RUNTIME, Parameter, AlphaRange=[-10 10], ...
    %       GuessRate=0.5, BetaPriorMean=1.5, SweetPointRule="UpDown");
    %   mlp = psychophysics.MLP(DATA, 'Level', AlphaRange=[-5 5]);
    %   nextLevel = mlp.Results.NextLevel;
    %   mlp.reset();  % restart estimation without clearing DATA
    %
    % Note: For the Weibull psychometric function, AlphaRange specifies the
    %   range of the k scale parameter (0 < k < 1). MaxSignalStrength must be
    %   set explicitly since it cannot be inferred from the k range.
    %
    % Reference: Shen, Y. and Richards, V.M. (2012). A maximum-likelihood
    %   procedure for estimating psychometric functions: Thresholds, slopes,
    %   and lapses of attention. J. Acoust. Soc. Am., 132(2), 957-967.
    %    % Documentation: documentation/psychophysics/psychophysics_MLP.md
    %    % See also: psychophysics.BestPEST, psychophysics.Staircase

    properties (SetObservable)
        AlphaRange (1,2) double = [0 1]  % [min max] for the alpha (threshold) parameter grid; for Weibull this is the k scale parameter range

        BetaRange (1,2) double {mustBePositive} = [0.2 2]  % [min max] for the beta (slope) parameter grid; must be positive
        LapseRange (1,2) double {mustBeNonnegative} = [0 0.2]  % [min max] for the lambda (lapse rate) grid; must be non-negative

        AlphaResolution (1,1) double {mustBePositive, mustBeInteger} = 21  % Number of alpha grid points (paper used 21)
        BetaResolution  (1,1) double {mustBePositive, mustBeInteger} = 10   % Number of beta grid points (paper used 10)
        LapseResolution (1,1) double {mustBePositive, mustBeInteger} = 5    % Number of lapse grid points (paper used 5)

        AlphaPriorMean (1,1) double = NaN  % Mean of Gaussian prior on alpha; default: center of AlphaRange
        AlphaPriorStd  (1,1) double = NaN  % Std of Gaussian prior on alpha; default: diff(AlphaRange)/4
        BetaPriorMean  (1,1) double = 1     % Mean of Gaussian prior on beta (default 1)
        BetaPriorStd   (1,1) double = 0.75  % Std of Gaussian prior on beta (default 0.75 per Shen & Richards)
        LapsePriorMean (1,1) double = 0     % Mean of Gaussian prior on lapse rate (default 0)
        LapsePriorStd  (1,1) double = 0.1   % Std of Gaussian prior on lapse rate (default 0.1 per Shen & Richards)

        PsychometricFunction (1,1) string {mustBeMember(PsychometricFunction, ["Logistic","Weibull"])} = "Logistic"  % Psychometric function shape: "Logistic" or "Weibull"

        GuessRate (1,1) double {mustBeNonnegative} = 0  % Fixed lower asymptote gamma; set 0.5 for 2-AFC

        MaxSignalStrength (1,1) double = NaN  % Maximum signal strength for sweet-point search and lambda-sweet proxy; default: AlphaRange(2)

        SweetPointRule (1,1) string {mustBeMember(SweetPointRule, ["Random","UpDown"])} = "Random"  % Sweet-point selection strategy: "Random" (uniform draw) or "UpDown" (N-down M-up staircase)
        UpDownRule (1,2) double {mustBePositive, mustBeInteger} = [4 1]  % [N M] for N-down M-up sweet-point selection; default [4 1] per Shen & Richards

        SweetPointGridResolution (1,1) double {mustBePositive, mustBeInteger} = 1000  % Number of x-grid points for numerical sweet-point optimization

        PositiveResponseBit (1,1) epsych.BitMask = epsych.BitMask.Hit  % Response code identifying a correct (positive) response
    end

    properties (SetAccess = protected)
        Results = struct( ...
            'NextLevel',             [], ...
            'AlphaEstimate',         [], ...
            'BetaEstimate',          [], ...
            'LapseEstimate',         [], ...
            'SweetPoints',           [], ...
            'SweetPointPcorrect',    [], ...
            'CurrentSweetPointIndex',[], ...
            'Posterior',             [], ...
            'FittedPsychFn',         [], ...
            'TrialCount',            [], ...
            'StimulusLevels',        [], ...
            'Responses',             [])  % MLP estimation outputs
    end

    properties (Dependent)
        ResetCount  % Number of trials present at the last reset; trials at or below this index are excluded (read-only)
    end

    properties (Access = private)
        resetCount_           (1,1) double = 0  % Watermark set by reset(); trials at or before this count are ignored
        sweetPointIdx_        (1,1) double = 4  % Current sweet-point index for UpDown rule (1 = lowest, 4 = lambda-sweet)
        correctStreak_        (1,1) double = 0  % Consecutive correct responses since last direction change (UpDown)
        incorrectStreak_      (1,1) double = 0  % Consecutive incorrect responses since last direction change (UpDown)
        lastResponseCount_    (1,1) double = 0  % Trial count at last UpDown state update
    end

    methods
        function obj = MLP(source, Parameter, options)
            % mlp = psychophysics.MLP(source, Parameter, AlphaRange=[min max])
            % mlp = psychophysics.MLP(source, Parameter, AlphaRange=[min max], Name=Value)
            % Construct an MLP object for online or offline psychometric function estimation.
            %
            % Pass a Runtime object as source for online mode (auto-updates on NewData).
            % Pass a DATA struct array for offline mode (computes immediately).
            %
            % Parameters:
            %   source                - Runtime object (online) or DATA struct array (offline).
            %   Parameter             - Parameter object (online) or DATA field name string (offline).
            %   AlphaRange            - Required. [min max] of the threshold (alpha) parameter.
            %   BetaRange             - [min max] slope search range (default [0.2 2]).
            %   LapseRange            - [min max] lapse rate range, non-negative (default [0 0.2]).
            %   AlphaResolution       - Alpha grid points (default 21).
            %   BetaResolution        - Beta grid points (default 10).
            %   LapseResolution       - Lapse grid points (default 5).
            %   AlphaPriorMean        - Prior mean for alpha (default: center of AlphaRange).
            %   AlphaPriorStd         - Prior std for alpha (default: diff(AlphaRange)/4).
            %   BetaPriorMean         - Prior mean for beta (default 1).
            %   BetaPriorStd          - Prior std for beta (default 0.75).
            %   LapsePriorMean        - Prior mean for lapse (default 0).
            %   LapsePriorStd         - Prior std for lapse (default 0.1).
            %   PsychometricFunction  - "Logistic" (default) or "Weibull".
            %   GuessRate             - Fixed lower asymptote gamma (default 0; set 0.5 for 2-AFC).
            %   MaxSignalStrength     - Lambda-sweet proxy signal strength (default: AlphaRange(2)).
            %   SweetPointRule        - "Random" (default) or "UpDown".
            %   UpDownRule            - [N M] for N-down M-up rule (default [4 1]).
            %   SweetPointGridResolution - Grid points for sweet-point search (default 1000).
            %   PositiveResponseBit   - BitMask for a correct response (default Hit).
            %   StimulusTrialType     - BitMask for stimulus trials (default TrialType_0).
            %   CatchTrialType        - BitMask for catch trials (default TrialType_1).
            %   ExcludedTrials        - Logical mask or 1-based indices of trials to exclude.
            %
            % Returns:
            %   obj - Configured psychophysics.MLP instance.
            arguments
                source = []
                Parameter = []
                options.AlphaRange (1,2) double = [0 1]
                options.BetaRange  (1,2) double {mustBePositive} = [0.2 2]
                options.LapseRange (1,2) double {mustBeNonnegative} = [0 0.2]
                options.AlphaResolution (1,1) double {mustBePositive, mustBeInteger} = 21
                options.BetaResolution  (1,1) double {mustBePositive, mustBeInteger} = 10
                options.LapseResolution (1,1) double {mustBePositive, mustBeInteger} = 5
                options.AlphaPriorMean (1,1) double = NaN
                options.AlphaPriorStd  (1,1) double = NaN
                options.BetaPriorMean  (1,1) double = 1
                options.BetaPriorStd   (1,1) double = 0.75
                options.LapsePriorMean (1,1) double = 0
                options.LapsePriorStd  (1,1) double = 0.1
                options.PsychometricFunction (1,1) string {mustBeMember(options.PsychometricFunction, ["Logistic","Weibull"])} = "Logistic"
                options.GuessRate (1,1) double {mustBeNonnegative} = 0
                options.MaxSignalStrength (1,1) double = NaN
                options.SweetPointRule (1,1) string {mustBeMember(options.SweetPointRule, ["Random","UpDown"])} = "Random"
                options.UpDownRule (1,2) double {mustBePositive, mustBeInteger} = [4 1]
                options.SweetPointGridResolution (1,1) double {mustBePositive, mustBeInteger} = 1000
                options.PositiveResponseBit (1,1) epsych.BitMask = epsych.BitMask.Hit
                options.StimulusTrialType   (1,1) epsych.BitMask = epsych.BitMask.TrialType_0
                options.CatchTrialType      (1,1) epsych.BitMask = epsych.BitMask.TrialType_1
                options.ExcludedTrials = []
            end

            obj = obj@psychophysics.Psych(source, Parameter, ExcludedTrials=options.ExcludedTrials);

            obj.AlphaRange            = options.AlphaRange;
            obj.BetaRange             = options.BetaRange;
            obj.LapseRange            = options.LapseRange;
            obj.AlphaResolution       = options.AlphaResolution;
            obj.BetaResolution        = options.BetaResolution;
            obj.LapseResolution       = options.LapseResolution;
            obj.AlphaPriorMean        = options.AlphaPriorMean;
            obj.AlphaPriorStd         = options.AlphaPriorStd;
            obj.BetaPriorMean         = options.BetaPriorMean;
            obj.BetaPriorStd          = options.BetaPriorStd;
            obj.LapsePriorMean        = options.LapsePriorMean;
            obj.LapsePriorStd         = options.LapsePriorStd;
            obj.PsychometricFunction  = options.PsychometricFunction;
            obj.GuessRate             = options.GuessRate;
            obj.MaxSignalStrength     = options.MaxSignalStrength;
            obj.SweetPointRule        = options.SweetPointRule;
            obj.UpDownRule            = options.UpDownRule;
            obj.SweetPointGridResolution = options.SweetPointGridResolution;
            obj.PositiveResponseBit   = options.PositiveResponseBit;
            obj.StimulusTrialType     = options.StimulusTrialType;
            obj.CatchTrialType        = options.CatchTrialType;

            % Resolve NaN defaults that depend on AlphaRange
            if isnan(obj.AlphaPriorMean)
                obj.AlphaPriorMean = mean(obj.AlphaRange);
            end
            if isnan(obj.AlphaPriorStd)
                obj.AlphaPriorStd = diff(obj.AlphaRange) / 4;
            end
            if isnan(obj.MaxSignalStrength)
                obj.MaxSignalStrength = obj.AlphaRange(2);
            end

            if isempty(obj.RUNTIME)
                obj.refresh();
            end
        end

        function reset(obj)
            % reset(obj)
            % Restart estimation from a clean slate without deleting DATA.
            % Watermarks all current trials; subsequent estimation treats the
            % next trial as the first. Resets UpDown tracking state.
            obj.resetCount_        = numel(obj.DATA);
            obj.sweetPointIdx_     = 4;
            obj.correctStreak_     = 0;
            obj.incorrectStreak_   = 0;
            obj.lastResponseCount_ = 0;
            obj.refresh();
        end

        function n = get.ResetCount(obj)
            % n = obj.ResetCount
            % Number of trials present at the last reset.
            %
            % Returns:
            %   n - Trial watermark index; trials at or below this are excluded.
            n = obj.resetCount_;
        end
    end

    methods (Access = protected)
        recomputeResults_(obj)
        % recomputeResults_(obj)
        % Recompute 3D posterior, ML estimates, sweet points, and NextLevel.
        % Called automatically by Psych.refresh on each NewData event.
        % Implemented in recomputeResults_.m.

        function results = emptyResults_(obj)
            % results = emptyResults_(obj)
            % Return Results struct with outputs cleared and NextLevel initialized
            % to AlphaPriorMean (the expected threshold before any trials).
            %
            % Returns:
            %   results - Cleared Results struct ready for population.
            results                        = obj.Results;
            results.NextLevel              = obj.AlphaPriorMean;
            results.AlphaEstimate          = [];
            results.BetaEstimate           = [];
            results.LapseEstimate          = [];
            results.SweetPoints            = [];
            results.SweetPointPcorrect     = [];
            results.CurrentSweetPointIndex = [];
            results.Posterior              = [];
            results.FittedPsychFn          = [];
            results.TrialCount             = 0;
            results.StimulusLevels         = [];
            results.Responses              = [];
        end
    end

    methods (Access = private)
        P = evaluatePsychFn_(obj, x, alpha, beta, lapse)
        % P = evaluatePsychFn_(obj, x, alpha, beta, lapse)
        % Evaluate the psychometric function for scalar or broadcast-compatible arrays.

        [logPosterior, alphaVec, betaVec, lapseVec] = computePosterior_(obj, stimLevels, responses)
        % Compute the 3D Bayesian log-posterior from trial history.

        sweetPoints = computeSweetPoints_(obj, alphaML, betaML, lapseML)
        % Numerically find sweet-point signal strengths from ML parameter estimates.

        level = selectNextLevel_(obj, sweetPoints, responses)
        % Select the next signal strength from sweet points using the configured rule.

        function rcField = resolveRespCodeField_(~, data)
            % rcField = resolveRespCodeField_(obj, data)
            % Return the response code field name present in the given data struct.
            %
            % Parameters:
            %   data - Struct array to inspect.
            %
            % Returns:
            %   rcField - 'RespCode', 'ResponseCode', or '' if neither is present.
            if isfield(data, 'RespCode')
                rcField = 'RespCode';
            elseif isfield(data, 'ResponseCode')
                rcField = 'ResponseCode';
            else
                rcField = '';
            end
        end
    end
end
