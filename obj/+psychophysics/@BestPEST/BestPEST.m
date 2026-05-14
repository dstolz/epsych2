classdef BestPEST < psychophysics.Psych
    % bp = psychophysics.BestPEST(source, Parameter, Range=[min max])
    % bp = psychophysics.BestPEST(source, Parameter, Range=[min max], Name=Value)
    % Maximum likelihood threshold estimation using the Best PEST procedure.
    % At each trial, fits a psychometric function to the accumulated response
    % history via grid-based MLE, selecting the next stimulus level at the
    % current maximum-likelihood threshold estimate — the point of maximum
    % Fisher information. The estimated threshold at a configurable target
    % probability and a profile log-likelihood confidence interval are also
    % reported in Results.
    %
    % Supports two operating modes:
    %   Online mode  - Construct with a Runtime object to listen for NewData
    %       events and update automatically as trials are completed.
    %   Offline mode - Construct with a per-trial DATA struct array to analyze
    %       saved sessions without attaching event listeners.
    %
    % Key properties:
    %   Range               - [min max] of independent variable (required).
    %   PsychometricFunction - "Logistic" (default), "Normal", or "Weibull".
    %   Slope               - Fixed slope of psychometric function (default 1).
    %   EstimateSlope       - If true, jointly estimate threshold and slope.
    %   TargetProbability   - Probability for ThresholdAtTarget (default 0.5).
    %   GuessRate           - Lower asymptote gamma; 0.5 for 2-AFC (default 0).
    %   LapseRate           - Upper asymptote offset lambda (default 0).
    %   ConfidenceLevel     - Profile log-likelihood CI coverage (default 0.95).
    %   GridResolution      - Threshold grid points for MLE (default 1000).
    %   PositiveResponseBit - BitMask for a positive (detected) response.
    %
    % Key Results fields:
    %   NextLevel            - Next recommended stimulus level (= ThresholdEstimate).
    %   ThresholdEstimate    - ML estimate of location/scale parameter theta.
    %   ThresholdAtTarget    - Stimulus level yielding TargetProbability.
    %   ConfidenceInterval   - [lower upper] bounds on ThresholdEstimate.
    %   ConfidenceIntervalWidth - Scalar CI width; use as a stopping criterion.
    %   LogLikelihood        - Normalized log-likelihood over Grid (max = 0).
    %
    % Example:
    %   bp = psychophysics.BestPEST(RUNTIME, Parameter, Range=[-40 0]);
    %   bp = psychophysics.BestPEST(DATA, 'Depth', Range=[-40 0], GuessRate=0.5, ...
    %       TargetProbability=0.75);
    %   nextLevel = bp.Results.NextLevel;
    %   bp.reset();  % restart estimation without deleting DATA
    %
    % Reference: Pentland, A. (1980). Maximum likelihood estimation: The best PEST.
    %   Perception & Psychophysics, 28(4), 377-379.
    %
    % Documentation: documentation/psychophysics/psychophysics_BestPEST.md
    %
    % See also: psychophysics.Staircase

    properties (SetObservable)
        Range (1,2) double = [0 1]  % [min max] of the independent variable

        PsychometricFunction (1,1) string {mustBeMember(PsychometricFunction, ["Logistic","Normal","Weibull"])} = "Logistic"  % Psychometric function shape: "Logistic", "Normal", or "Weibull"

        Slope (1,1) double {mustBePositive} = 1  % Fixed slope (steepness) of psychometric function; ignored when EstimateSlope=true
        EstimateSlope (1,1) logical = false  % If true, jointly estimate threshold and slope via 2-D MLE grid
        SlopeRange (1,2) double = [0.1 10]  % [min max] slope search range; used only when EstimateSlope=true
        SlopeGridResolution (1,1) double {mustBePositive, mustBeInteger} = 50  % Number of slope grid points; used only when EstimateSlope=true

        TargetProbability (1,1) double {mustBeInRange(TargetProbability, 0, 1)} = 0.5  % Target response probability for ThresholdAtTarget (e.g. 0.75 for 2-AFC)
        GuessRate (1,1) double {mustBeNonnegative} = 0  % Lower asymptote gamma; set 0.5 for 2-AFC
        LapseRate (1,1) double {mustBeNonnegative} = 0  % Upper asymptote offset lambda

        GridResolution (1,1) double {mustBePositive, mustBeInteger} = 1000  % Number of threshold grid points for MLE
        ConfidenceLevel (1,1) double {mustBeInRange(ConfidenceLevel, 0, 1)} = 0.95  % Profile log-likelihood confidence interval coverage probability

        PositiveResponseBit (1,1) epsych.BitMask = epsych.BitMask.Hit  % Response code identifying a positive (detected) response
    end

    properties (SetAccess = protected)
        Results = struct( ...
            'NextLevel',                [], ...
            'ThresholdEstimate',        [], ...
            'ThresholdAtTarget',        [], ...
            'SlopeEstimate',            [], ...
            'ConfidenceInterval',       [], ...
            'ConfidenceIntervalWidth',  [], ...
            'Grid',                     [], ...
            'LogLikelihood',            [], ...
            'TrialCount',               [], ...
            'StimulusLevels',           [], ...
            'Responses',                [])  % Maximum likelihood threshold estimation outputs
    end

    properties (Dependent)
        ResetCount  % Number of trials present at last reset; trials before this index are excluded from estimation (read-only)
    end

    properties (Access = private)
        resetCount_ (1,1) double = 0  % Trial watermark set by reset(); trials at or below this index are ignored by recomputeResults_
    end

    methods
        function obj = BestPEST(source, Parameter, options)
            % bp = psychophysics.BestPEST(source, Parameter, Range=[min max])
            % bp = psychophysics.BestPEST(source, Parameter, Range=[min max], Name=Value)
            % Construct a BestPEST object for online or offline threshold estimation.
            %
            % Pass a Runtime object as source for online mode (auto-updates on NewData).
            % Pass a DATA struct array for offline mode (computes immediately).
            %
            % Parameters:
            %   source                - Runtime object (online) or DATA struct array (offline).
            %   Parameter             - Parameter object (online) or DATA field name string (offline).
            %   Range                 - Required. [min max] of independent variable.
            %   PsychometricFunction  - "Logistic" (default), "Normal", or "Weibull".
            %   Slope                 - Fixed slope when EstimateSlope=false (default 1).
            %   EstimateSlope         - Enable 2-D MLE over threshold x slope (default false).
            %   SlopeRange            - [min max] slope search range (default [0.1 10]).
            %   SlopeGridResolution   - Slope grid points (default 50).
            %   TargetProbability     - Probability for ThresholdAtTarget (default 0.5).
            %   GuessRate             - Lower asymptote gamma (default 0).
            %   LapseRate             - Upper asymptote offset lambda (default 0).
            %   GridResolution        - Threshold grid points (default 1000).
            %   ConfidenceLevel       - CI coverage probability (default 0.95).
            %   PositiveResponseBit   - BitMask for positive response (default Hit).
            %   StimulusTrialType     - BitMask for stimulus trials (default TrialType_0).
            %   CatchTrialType        - BitMask for catch trials (default TrialType_1).
            %   ExcludedTrials        - Logical mask or 1-based trial indices to exclude.
            %
            % Returns:
            %   obj - Configured psychophysics.BestPEST instance.
            arguments
                source = []
                Parameter = []
                options.Range (1,2) double = [0 1]
                options.PsychometricFunction (1,1) string {mustBeMember(options.PsychometricFunction, ["Logistic","Normal","Weibull"])} = "Logistic"
                options.Slope (1,1) double {mustBePositive} = 1
                options.EstimateSlope (1,1) logical = false
                options.SlopeRange (1,2) double = [0.1 10]
                options.SlopeGridResolution (1,1) double {mustBePositive, mustBeInteger} = 50
                options.TargetProbability (1,1) double {mustBeInRange(options.TargetProbability, 0, 1)} = 0.5
                options.GuessRate (1,1) double {mustBeNonnegative} = 0
                options.LapseRate (1,1) double {mustBeNonnegative} = 0
                options.GridResolution (1,1) double {mustBePositive, mustBeInteger} = 1000
                options.ConfidenceLevel (1,1) double {mustBeInRange(options.ConfidenceLevel, 0, 1)} = 0.95
                options.PositiveResponseBit (1,1) epsych.BitMask = epsych.BitMask.Hit
                options.StimulusTrialType (1,1) epsych.BitMask = epsych.BitMask.TrialType_0
                options.CatchTrialType (1,1) epsych.BitMask = epsych.BitMask.TrialType_1
                options.ExcludedTrials = []
            end

            obj = obj@psychophysics.Psych(source, Parameter, ExcludedTrials=options.ExcludedTrials);
            obj.Range                = options.Range;
            obj.PsychometricFunction = options.PsychometricFunction;
            obj.Slope                = options.Slope;
            obj.EstimateSlope        = options.EstimateSlope;
            obj.SlopeRange           = options.SlopeRange;
            obj.SlopeGridResolution  = options.SlopeGridResolution;
            obj.TargetProbability    = options.TargetProbability;
            obj.GuessRate            = options.GuessRate;
            obj.LapseRate            = options.LapseRate;
            obj.GridResolution       = options.GridResolution;
            obj.ConfidenceLevel      = options.ConfidenceLevel;
            obj.PositiveResponseBit  = options.PositiveResponseBit;
            obj.StimulusTrialType    = options.StimulusTrialType;
            obj.CatchTrialType       = options.CatchTrialType;

            if isempty(obj.RUNTIME)
                obj.refresh();
            end
        end

        function reset(obj)
            % reset(obj)
            % Restart MLE estimation from a clean slate without deleting DATA.
            % Watermarks all current trials; subsequent recomputation treats the
            % next trial as the first, returning NextLevel to mean(Range).
            obj.resetCount_ = numel(obj.DATA);
            obj.refresh();
        end

        function n = get.ResetCount(obj)
            % n = obj.ResetCount
            % Number of trials present at the last reset.
            %
            % Returns:
            %   n - Trial watermark; trials at or below this index are excluded.
            n = obj.resetCount_;
        end
    end

    methods (Access = protected)
        recomputeResults_(obj)
        % recomputeResults_(obj)
        % Recompute MLE threshold estimate from the active trial window.
        % Called automatically by Psych.refresh on each NewData event.
        % Implemented in recomputeResults_.m.

        function results = emptyResults_(obj)
            % results = emptyResults_(obj)
            % Return the Results struct with output fields cleared and NextLevel
            % initialized to mean(Range) per the Pentland first-trial rule.
            %
            % Returns:
            %   results - Results struct ready for population by recomputeResults_.
            results = obj.Results;
            results.NextLevel               = mean(obj.Range);
            results.ThresholdEstimate       = [];
            results.ThresholdAtTarget       = [];
            results.SlopeEstimate           = [];
            results.ConfidenceInterval      = [];
            results.ConfidenceIntervalWidth = [];
            results.Grid                    = [];
            results.LogLikelihood           = [];
            results.TrialCount              = 0;
            results.StimulusLevels          = [];
            results.Responses               = [];
        end
    end

    methods (Access = private)
        P = evaluatePsychFn_(obj, x, theta, slope)
        % P = evaluatePsychFn_(obj, x, theta, slope)
        % Evaluate the generalized psychometric function with gamma and lambda applied.
        % Implemented in evaluatePsychFn_.m.

        [logL, thetaGrid, slopeGrid, ci] = computeLogLikelihood_(obj, stimLevels, responses)
        % [logL, thetaGrid, slopeGrid, ci] = computeLogLikelihood_(obj, stimLevels, responses)
        % Compute normalized log-likelihood over a threshold (and optionally slope) grid.
        % Implemented in computeLogLikelihood_.m.

        x = invertPsychFn_(obj, P_target, theta, slope)
        % x = invertPsychFn_(obj, P_target, theta, slope)
        % Invert the psychometric function to find x such that P(x) = P_target.
        % Implemented in invertPsychFn_.m.

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
