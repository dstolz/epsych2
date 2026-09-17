classdef Staircase < psychophysics.Psych & gui.PopOut
    % S = psychophysics.Staircase(RUNTIME, Parameter)
    % S = psychophysics.Staircase(DATA, Parameter)
    % S = psychophysics.Staircase(..., Name=Value)
    % psychophysics.Staircase Track adaptive reversals and compute staircase thresholds.
    % psychophysics.Staircase analyzes trial history to compute stimulus step
    % direction, reversal locations, and threshold estimates for adaptive
    % psychophysics procedures. Only trials matching StimulusTrialType are used
    % in the computation of step direction, reversals, and thresholds.
    %
    % The class supports two operating modes:
    %   Online mode  - Construct with a Runtime object to listen for NewData events
    %       and update automatically as trials are completed.
    %   Offline mode - Construct with a per-trial DATA struct array to analyze saved
    %       sessions without attaching event listeners.
    %
    % Key properties:
    %   Parameter - hw.Parameter object or offline DATA field name used to
    %       extract stimulus values from DATA.
    %   StaircaseDirection - "Up" or "Down" reversal convention.
    %   StimulusTrialType - BitMask identifying trials included in the staircase.
    %   ExcludedTrials - Trial exclusions specified as a logical mask or
    %       1-based trial indices.
    %   Results - Structure containing computed staircase outputs such as
    %       Threshold, ReversalIdx, and StepDirection.
    %
    % Key methods:
    %   refresh_history  - Recompute reversals and the reversal threshold.
    %   Plot / popOut    - The staircase track, embedded or in its own window.
    %   fitPsychometric  - Maximum-likelihood threshold, slope and psychometric
    %       function from the trials themselves, rather than from the
    %       reversals. Returned, never stored, so it cannot go stale beside
    %       live data. See documentation/psychophysics/psychophysics_StaircaseFit.md.
    %   weightedThreshold - Hoover (2025) corrected threshold for a weighted
    %       (asymmetric-step) staircase: a balanced reversal mean plus
    %       (delta_- - delta_+)/4, and the probability the steps actually
    %       target. ApplyWeightedCorrection=true makes it Results.Threshold.
    %       See documentation/psychophysics/psychophysics_WeightedStaircase.md.
    %
    % Example:
    %   S = psychophysics.Staircase(RUNTIME, Parameter, Plot=true);
    %   S = psychophysics.Staircase(DATA, Parameter, StaircaseDirection="Up");
    %   S = psychophysics.Staircase(DATA, 'Depth');
    %   S.ExcludedTrials = [1 4 7];
    %   S.Plot();
    %   S.Plot(ax, ShowSteps=false);
    %   S.popOut();   % the same plot, larger, in a window of its own
    %   F = S.fitPsychometric();   % threshold and slope from the responses
    %   T = S.weightedThreshold(StepFieldYes='Depth_StepOnHit', ...
    %       StepFieldNo='Depth_StepOnMiss');   % corrected, weighted-step threshold
    %
    % The plot's right-click menu offers "Open in Separate Window" (see
    % gui.PopOut). That window holds a second Staircase over the same trials
    % with a plot of its own, so changing its threshold settings, dB axis, or
    % overlays -- or closing it -- leaves the embedded plot untouched.
    %
    % See documentation/psychophysics/psychophysics_Staircase.md for workflow notes, threshold details, and
    % event-system integration examples.

    properties (SetObservable)
        StaircaseDirection (1,1) string {mustBeMember(StaircaseDirection,["Up","Down"])} = "Down"  % Direction for reversal detection

        ThresholdFromLastNReversals (1,1) double {mustBePositive, mustBeInteger} = 12  % Number of reversals to use in threshold calculation
        ThresholdFormula (1,1) string {mustBeMember(ThresholdFormula,["Mean","GeometricMean"])} = "Mean"  % Formula for computing threshold from reversals

        % Weighted-staircase correction (see weightedThreshold). Off by default,
        % so no existing session changes its numbers. When on,
        % Results.Threshold is the corrected, balanced value -- NaN until it
        % can be computed, never the uncorrected mean under a flag that says
        % otherwise -- and Results.Weighted holds the full result. Set, then
        % refresh_history(), as for ThresholdFromLastNReversals.
        ApplyWeightedCorrection (1,1) logical = false
        WeightedStepAfterYes (1,1) double = NaN   % signed; NaN = find it
        WeightedStepAfterNo  (1,1) double = NaN
        WeightedStepFieldYes (1,1) string = ""    % DATA field holding the step; "" = none
        WeightedStepFieldNo  (1,1) string = ""

        % Optional plotting configuration (when enabled via Plot or constructor option).
        % Accent colors avoid the reserved response-outcome hues (green/red/blue/
        % orange from epsych.BitMask) so overlays never read as an outcome.
        LineColor      (1,1) string = "#6b7a8f"
        StepColor      (1,1) string = "#e65a1a"
        NeutralColor   (1,1) string = "#999999"
        ReversalColor  (1,1) string = "#b5179e"
        ThresholdColor (1,1) string = "#0f7c8a"

        MarkerSize (1,1) double {mustBePositive} = 42
        StepMarkerSize (1,1) double {mustBePositive} = 130
        ReversalMarkerSize (1,1) double {mustBePositive} = 120

        ShowSteps (1,1) logical = true
        ShowReversals (1,1) logical = true
    end

    properties (SetAccess = protected)
        Results = struct( ...
            'ReversalCount', [], ...
            'ReversalIdx', [], ...
            'ReversalDirection', [], ...
            'StepDirection', [], ...
            'StimulusTrialIdx', [], ...
            'Threshold', [], ...
            'ThresholdStd', [], ...
            'MinBlockThreshold', [], ...
            'MinBlockReversals', [], ...
            'Weighted', [])  % Computed staircase outputs; Weighted only with ApplyWeightedCorrection
    end

    properties (Dependent)
        % Dependent properties provide read-only access to computed trial data
        stimulusValues  % Stimulus parameter values from DATA, optionally converted to decibels
    end

    properties (Access = private)
        sessionCache_ = []     % memoized per-trial vectors; see sessionVectors_
        geomeanUndefined_ (1,1) logical = false  % latches the undefined-geometric-mean log to once per episode
        weightedRefusal_ (1,1) string = ""       % last weighted-correction refusal logged; see logWeightedRefusal_

        % Plot state (optional).
        plotEnabled_ (1,1) logical = false
        plotAxes_ = []
        plotFigure_ = []
        plotOwnsFigure_ (1,1) logical = false
        plotListeners_ = event.listener.empty

        h_line
        h_points
        CatchH
        h_thrreg
        h_thrline
        StepH
        ReversalUpH
        ReversalDownH
        bitSwatchH_ = []       % legend-only handles, one per obj.Bits
        legendH_ = []          % legend built from the currently visible series
        legendKey_ = ""        % identifies the last legend contents; skips rebuilds
        plotContextMenu_ = []  % uicontextmenu for plot axes
    end

    methods
        function obj = Staircase(RUNTIME, Parameter,options)
            % S = psychophysics.Staircase(RUNTIME, Parameter)
            % S = psychophysics.Staircase(RUNTIME, Parameter, StaircaseDirection="Up")
            % S = psychophysics.Staircase(DATA, Parameter)
            % S = psychophysics.Staircase(RUNTIME, Parameter, Plot=true)
            % S = psychophysics.Staircase(RUNTIME, Parameter, Plot=true, PlotAxes=ax)
            % S = psychophysics.Staircase(DATA, Parameter, Plot=true)
            % S = psychophysics.Staircase(DATA, Parameter, Plot=true, PlotAxes=ax)
            %
            % Construct a Staircase object for online or offline analysis.
            %
            % Pass a Runtime object as the first input to attach a listener to
            % RUNTIME.EVENTS and update automatically on each NewData event.
            %
            % Pass a DATA struct array as the first input to compute staircase history
            % immediately without attaching listeners.
            %
            % In online mode, the staircase automatically recomputes reversals and
            % thresholds when new trial data arrives. In offline mode, call refresh_history()
            % after modifying obj.DATA.
            %
            % Stimulus trials are filtered by StimulusTrialType mask for reversal detection.
            %
            % Plotting is optional. When Plot is true and PlotAxes is empty, the
            % Staircase creates and owns a new figure/axes for online updates.
            %
            % Parameters:
            %   RUNTIME              - Runtime object with EVENTS and trial data for online mode.
            %   DATA                 - Per-trial struct array for offline mode, typically the loaded `Data` struct.
            %   Parameter            - hw.Parameter object, or in offline mode a field name from DATA.
            %   StimulusTrialType    - BitMask for stimulus trials (default: TrialType_0).
            %   CatchTrialType       - BitMask for catch trials (default: TrialType_1).
            %   StaircaseDirection   - "Up" or "Down" (default: "Down").
            %   Plot                 - Enable staircase plotting (default: false).
            %   PlotAxes             - Axes to draw into; creates new figure when empty.
            %   ExcludedTrials       - Trial exclusions as a logical mask or 1-based indices.
            %   ShowSteps            - Show step-direction markers when plotting.
            %   ShowReversals        - Show reversal markers when plotting.
            %
            % Returns:
            %   obj - Configured psychophysics.Staircase instance.
            %
            % See documentation/psychophysics/psychophysics_Staircase.md for offline analysis and plotting examples.
            arguments
                RUNTIME
                Parameter
                options.StimulusTrialType (1,1) epsych.BitMask = epsych.BitMask.TrialType_0
                options.CatchTrialType (1,1) epsych.BitMask = epsych.BitMask.TrialType_1
                options.StaircaseDirection (1,1) string {mustBeMember(options.StaircaseDirection,["Up","Down"])} = "Down"
                options.Plot (1,1) logical = false
                options.PlotAxes = []
                options.ExcludedTrials = []
                options.ShowSteps (1,1) logical
                options.ShowReversals (1,1) logical
            end

            obj = obj@psychophysics.Psych(RUNTIME, Parameter, ExcludedTrials=options.ExcludedTrials);
            obj.StimulusTrialType = options.StimulusTrialType;
            obj.CatchTrialType = options.CatchTrialType;
            obj.StaircaseDirection = options.StaircaseDirection;

            if isempty(obj.RUNTIME)
                obj.refresh();
            end

            if options.Plot
                % Forward only what the caller stated (see Plot).
                shown = rmfield(options, intersect(fieldnames(options), ...
                    {'StimulusTrialType','CatchTrialType','StaircaseDirection', ...
                    'Plot','PlotAxes','ExcludedTrials'}));
                args = namedargs2cell(shown);
                obj.Plot(options.PlotAxes, args{:});
            end

        end

        function delete(obj)
            % delete(obj)
            % Destroy Staircase and release listeners/graphics.
            % Parameters:
            %   obj - psychophysics.Staircase instance.
            obj.disablePlot();
            delete@psychophysics.Psych(obj);
        end

        function refresh_history(obj)
            % refresh_history(obj)
            % Recompute staircase history and notify listeners.
            % Parameters:
            %   obj - psychophysics.Staircase instance.
            %
            % Use this after changing DATA or analysis settings in offline workflows.
            obj.refresh();
        end

        function Plot(obj, ax, options)
            % obj.Plot()
            % obj.Plot(ax)
            % obj.Plot(ax, ShowSteps=true, ShowReversals=true)
            % Enable optional staircase plotting.
            % If ax is empty, a new uifigure and uiaxes are created and owned.
            %
            % In offline mode, first construct the staircase from saved DATA and then
            % call Plot() to visualize the computed history:
            %   S = psychophysics.Staircase(DATA, 'Depth');
            %   S.Plot();
            %
            % To draw into existing axes during offline review:
            %   S = psychophysics.Staircase(DATA, Parameter);
            %   S.Plot(ax, ShowSteps=false, ShowReversals=true);
            %
            % Parameters:
            %   obj - psychophysics.Staircase instance.
            %   ax - Target axes. When empty, a new figure and axes are created.
            %   ShowSteps - Show step-direction markers. The default is obj.ShowSteps.
            %   ShowReversals - Show reversal markers. The default is obj.ShowReversals.
            %
            % See documentation/psychophysics/psychophysics_Staircase.md for plotting workflows.
            % ShowSteps/ShowReversals carry no arguments-block defaults, so a
            % caller who did not state one can be told apart from one who
            % did: the operator's saved choice fills in only the former.
            arguments
                obj
                ax = []
                options.ShowSteps (1,1) logical
                options.ShowReversals (1,1) logical
            end

            obj.disablePlot();

            if isempty(ax)
                fig = uifigure('Name', sprintf('Staircase | %s', char(obj.ParameterName)));
                fig.CloseRequestFcn = @(src,~)obj.onPlotFigureClose_(src);
                layout = uigridlayout(fig, [1 1]);
                layout.RowHeight = {'1x'};
                layout.ColumnWidth = {'1x'};
                ax = uiaxes(layout);
                obj.plotFigure_ = fig;
                obj.plotOwnsFigure_ = true;
            else
                obj.plotFigure_ = ancestor(ax,'figure');
                obj.plotOwnsFigure_ = false;
            end

            obj.plotAxes_ = ax;

            % Restored before the plot is enabled, so a changed threshold
            % setting recomputes once without redrawing axes not yet set up.
            obj.loadMenuPreferences_();
            if isfield(options, 'ShowSteps'), obj.ShowSteps = options.ShowSteps; end
            if isfield(options, 'ShowReversals'), obj.ShowReversals = options.ShowReversals; end

            obj.plotEnabled_ = true;

            obj.attachPlotDestructionListeners_();
            obj.setupPlotAxes_();
            obj.updatePlot_();
        end

        function disablePlot(obj)
            % disablePlot(obj)
            % Disable plotting and release graphics/listeners.
            % Parameters:
            %   obj - psychophysics.Staircase instance.
            obj.plotEnabled_ = false;

            if ~isempty(obj.plotListeners_)
                L = obj.plotListeners_;
                L = L(isvalid(L));
                if ~isempty(L)
                    delete(L);
                end
                obj.plotListeners_ = event.listener.empty;
            end

            obj.deletePlotGraphics_();

            if obj.plotOwnsFigure_ && ~isempty(obj.plotFigure_) && isvalid(obj.plotFigure_)
                delete(obj.plotFigure_);
            end

            obj.plotAxes_ = [];
            obj.plotFigure_ = [];
            obj.plotOwnsFigure_ = false;
        end

        function refreshPlot(obj)
            % refreshPlot(obj)
            % Re-render plot from current staircase state (no-op if disabled).
            % Parameters:
            %   obj - psychophysics.Staircase instance.
            if ~obj.plotEnabled_
                return
            end
            obj.updatePlot_();
        end
        function v = get.stimulusValues(obj)
            % v = obj.stimulusValues
            % Return tracked stimulus values extracted from obj.DATA.
            % Parameters:
            %   obj - psychophysics.Staircase instance.
            % Returns:
            %   v - Stimulus values for the tracked Parameter.
            if isempty(obj.DATA)
                v = [];
            else
                fieldName = obj.parameterFieldName_();
                if ~isfield(obj.DATA, fieldName)
                    ME = MException(obj.classIdentifier_('MissingParameterField'), ...
                        ['DATA does not contain the field ''' fieldName ''' required for staircase analysis.']);
                    throwAsCaller(ME);
                end
                v = obj.dataFieldValues_(fieldName);
                if numel(v) ~= obj.trialCount
                    v = obj.stimulusValuesPerTrial_(fieldName);
                end
            end
        end

        % Psychometric fit (implemented as separate files in @Staircase)
        F = fitPsychometric(obj, options)

        % Weighted-staircase threshold (Hoover 2025), a separate file in @Staircase
        T = weightedThreshold(obj, options)

    end

    methods (Static)
        % The fit itself, and the function it fits -- pure and stateless, so
        % they work on counts from anywhere and are testable with no session.
        F = fitProportions(levels, numYes, numTotal, options)
        P = psychometricFunction(x, alpha, beta, options)
        x = psychometricLevel(P, alpha, beta, options)

        % The weighted-staircase estimator, likewise pure.
        T = correctedReversalMean(reversalValues, reversalIsAscending, stepAfterYes, stepAfterNo, options)
    end

    methods (Static, Access = private)
        F = emptyFit_()
        T = emptyWeightedThreshold_()
        [used, why] = selectBalancedReversals_(isAscending, eligible, numReversals)
    end

    methods (Access = protected)
        function recomputeResults_(obj)
            % Recompute reversal indices, step direction, and threshold estimates.
            % Only trials matching StimulusTrialType are used in the computation of step direction,
            % reversals, and thresholds. Filters trial data by StimulusTrialType, detects reversals by comparing
            % consecutive nonzero step directions (holds and NaN steps are ignored), and calculates
            % threshold from the last N reversals.
            % When DATA includes a TrialType field, that explicit value is used for
            % stimulus/catch selection before falling back to decoded response-code bits.
            % using the specified ThresholdFormula. Sets properties to empty if no data available.
            results = obj.emptyResults_();
            results.ReversalCount = 0;

            % The trials behind the memo, or their content, may have changed
            % since it was built; every refresh path arrives here.
            obj.sessionCache_ = [];

            if isempty(obj.DATA)
                obj.Results = results;
                if obj.ApplyWeightedCorrection
                    % A session that has not started still reports a result
                    % struct under the flag, so no reader of
                    % Results.Weighted.Valid has to test for [] first.
                    results.Weighted = obj.weightedThreshold();
                    results.Threshold = NaN;
                    results.ThresholdStd = NaN;
                    obj.Results = results;
                end
                return
            end

            s = obj.sessionVectors_();
            stimMask = s.stimMask;
            results.StimulusTrialIdx = find(stimMask);

            stimValues = s.stimValues(stimMask);



            sd = sign(diff(stimValues));
            if obj.StaircaseDirection == "Up"
                sd = -sd;
            end

            stepDirection = nan(1, obj.trialCount);
            if ~isempty(sd)
                stepDirection(results.StimulusTrialIdx) = [0 sd];
            end
            results.StepDirection = stepDirection;

            % Reversals are defined on the sequence of nonzero, non-NaN steps:
            % holds (sd == 0) occur legitimately when the controller repeats a
            % value after an abort or catch outcome, and NaN steps arise from
            % a trial whose recorded value is NaN; neither may create or mask a reversal.
            stepPos = find(~isnan(sd) & sd ~= 0);
            nzSteps = sd(stepPos);
            if numel(nzSteps) >= 2
                revJ = 1 + find(nzSteps(2:end) ~= nzSteps(1:end-1));
                if ~isempty(revJ)
                    % Mark the first stimulus trial at the extremum; matches
                    % the prior convention when there are no holds.
                    results.ReversalIdx = results.StimulusTrialIdx(stepPos(revJ - 1) + 1);
                    results.ReversalDirection = nzSteps(revJ);
                end
            end

            results.ReversalCount = numel(results.ReversalIdx);

            if results.ReversalCount > 0 && ~obj.ApplyWeightedCorrection
                lastN = max(1, results.ReversalCount - obj.ThresholdFromLastNReversals + 1):results.ReversalCount;
                thresholdValues = s.stimValues(results.ReversalIdx(lastN));

                results.Threshold = obj.thresholdFromReversals_(thresholdValues);
                results.ThresholdStd = std(thresholdValues);

                [results.MinBlockThreshold, results.MinBlockReversals] = ...
                    obj.minBlockThreshold_(s.stimValues(results.ReversalIdx));
            end

            obj.Results = results;

            if obj.ApplyWeightedCorrection
                % weightedThreshold reads the reversals from obj.Results, so
                % they are published first. It never throws for a data
                % problem, which matters here: this runs from a NewData
                % listener on every trial. The uncorrected path above is
                % skipped rather than overwritten, or GeometricMean would log
                % "threshold not shown" beside a threshold that is shown.
                W = obj.weightedThreshold();
                results.Weighted = W;
                results.Threshold = W.Threshold;
                % A refused correction can still have averaged its reversals;
                % a spread beside a NaN threshold would describe nothing.
                results.ThresholdStd = NaN;
                if W.Valid
                    results.ThresholdStd = W.ReversalStd;
                end
                obj.Results = results;
                obj.logWeightedRefusal_(W);
            end
        end

        function logWeightedRefusal_(obj, W)
            % Say once, not once per trial, why the corrected threshold is
            % missing. Debug level: a session's first trials have no
            % reversals yet, and that is not news.
            if W.Valid
                obj.weightedRefusal_ = "";
                return
            end
            if W.Message ~= obj.weightedRefusal_
                vprintf(2, 'Staircase %s: no weighted-corrected threshold. %s', ...
                    char(obj.ParameterName), char(W.Message));
            end
            obj.weightedRefusal_ = W.Message;
        end

        function v = stimulusValuesPerTrial_(obj, fieldName)
            % One level per trial, NaN where a trial recorded none.
            % [DATA.(f)] silently drops a trial whose value is empty, which
            % slid every later level onto the wrong trial -- and threw in
            % recomputeResults_ from the NewData listener, every trial. NaN is
            % what reversal detection already reads as "not recorded".
            v = nan(1, obj.trialCount);
            for k = 1:obj.trialCount
                x = obj.DATA(k).(fieldName);
                if isscalar(x) && ((isstruct(x) && isfield(x, 'Value')) || (isobject(x) && isprop(x, 'Value')))
                    x = x.Value;
                end
                if isscalar(x) && (isnumeric(x) || islogical(x))
                    v(k) = double(x);
                end
            end
        end

        function [thr, span] = minBlockThreshold_(obj, reversalValues)
            % The lowest threshold over every run of ThresholdFromLastNReversals
            % consecutive reversals, and the reversal numbers [first last] of
            % that run. The last-N threshold follows the track wherever it
            % drifts late in a session (fatigue, satiety); this is the best
            % the subject managed at any point. Blocks slide by one reversal,
            % so a best stretch is not split across two fixed blocks. Empty
            % until one whole block exists, since a partial block is not the
            % same estimate. Blocks whose formula is undefined are skipped,
            % and NaN reversal values are left to propagate into their block.
            thr = [];
            span = [];
            n = obj.ThresholdFromLastNReversals;
            numBlocks = numel(reversalValues) - n + 1;
            if numBlocks < 1
                return
            end

            blockThr = nan(1, numBlocks);
            for k = 1:numBlocks
                v = reversalValues(k:k+n-1);
                if obj.ThresholdFormula == "Mean"
                    blockThr(k) = mean(v);
                elseif all(v >= 0)
                    blockThr(k) = geomean(v);
                end
            end

            [thr, k] = min(blockThr);   % min skips NaN; all-NaN returns NaN
            span = [k, k + n - 1];
        end

        function thr = thresholdFromReversals_(obj, values)
            % thr = thresholdFromReversals_(obj, values)
            % Combine reversal values into a threshold under ThresholdFormula.
            % Runs from a NewData listener every trial, so an undefined
            % geometric mean is NaN (which the plot and title already read as
            % "no threshold") rather than an error, logged once per episode.
            % A parameter already in dB (an AM depth re 100%) is the usual
            % way to get there: its values are negative, and the log scale
            % means Mean is the geometric mean of the linear quantity anyway.
            undefined = false;
            if obj.ThresholdFormula == "Mean"
                thr = mean(values);
            elseif any(values < 0)
                thr = NaN;
                undefined = true;
            else
                thr = geomean(values);
            end

            if undefined && ~obj.geomeanUndefined_
                vprintf(1, 1, ['Staircase %s: the geometric mean of the reversals is undefined ' ...
                    'for negative values (min %g); threshold not shown. Use Mean, which is ' ...
                    'the right formula for a parameter already on a log scale.'], ...
                    char(obj.ParameterName), min(values));
            end
            obj.geomeanUndefined_ = undefined;
        end

        function results = emptyResults_(obj)
            % Return an empty staircase-results structure.
            results = obj.Results;
            results.ReversalCount = [];
            results.ReversalIdx = [];
            results.ReversalDirection = [];
            results.StepDirection = [];
            results.StimulusTrialIdx = [];
            results.Threshold = [];
            results.ThresholdStd = [];
            results.MinBlockThreshold = [];
            results.MinBlockReversals = [];
            results.Weighted = [];
        end

        function afterRefresh_(obj)
            % Update the staircase plot after analysis refreshes when enabled.
            if obj.plotEnabled_
                obj.updatePlot_();
            end
        end

        function c = popOutHostContainer_(obj)
            % Axes this staircase is plotted into (gui.PopOut).
            c = obj.plotAxes_;
        end

        function h = createPopOut_(obj, container)
            % A second staircase over the same trials, plotted in its own
            % window. A sibling analysis object rather than a second view of
            % this one: the plot's settings (threshold reversals, formula)
            % are properties of the analysis, so sharing it would make
            % a change in the pop-out rewrite the embedded plot as well.
            layout = uigridlayout(container, [1 1]);
            layout.RowHeight   = {'1x'};
            layout.ColumnWidth = {'1x'};
            layout.Padding     = [2 2 2 2];
            ax = uiaxes(layout);

            source = obj.RUNTIME;
            if isempty(source), source = obj.DATA; end

            h = psychophysics.Staircase(source, obj.Parameter, ...
                StimulusTrialType  = obj.StimulusTrialType, ...
                CatchTrialType     = obj.CatchTrialType, ...
                StaircaseDirection = obj.StaircaseDirection, ...
                ExcludedTrials     = obj.ExcludedTrials);

            % The weighted-correction settings are analysis settings too: left
            % out, a pop-out would show the uncorrected threshold beside a
            % corrected embedded plot.
            props = {'ThresholdFromLastNReversals','ThresholdFormula', ...
                'ApplyWeightedCorrection','WeightedStepAfterYes','WeightedStepAfterNo', ...
                'WeightedStepFieldYes','WeightedStepFieldNo', ...
                'LineColor','StepColor','NeutralColor','ReversalColor', ...
                'ThresholdColor','MarkerSize','StepMarkerSize', ...
                'ReversalMarkerSize','Bits','BitColors', ...
                'ShowSteps','ShowReversals'};
            for k = 1:numel(props)
                h.(props{k}) = obj.(props{k});
            end

            % Online, a fresh analysis holds no trials until the next
            % NewData; hand it the session so far so the window opens on the
            % same picture instead of an empty axes.
            if ~isempty(obj.RUNTIME)
                h.DATA = obj.DATA;
            end
            h.refresh();

            % The embedded plot's settings are the starting point; the
            % pop-out's own saved menu choices, if any, then win in Plot.
            h.Plot(ax);
        end



    end

    methods (Access = private)
        % Plot helper methods (implemented as separate files in @Staircase)
        attachPlotDestructionListeners_(obj)
        onPlotFigureClose_(obj, fig)
        deletePlotGraphics_(obj)
        setupPlotAxes_(obj)
        applyAxesStyle_(obj)
        createPlotContextMenu_(obj)
        updatePlot_(obj)
        updateThresholdOverlay_(obj)
        updatePlotLimits_(obj, plotData)
        updateLegend_(obj, plotData)

        plotData = getPlotData_(obj);
        % Update any code here that used the old outputs to use plotData fields
        updatePlotLabels_(obj)
        lbl = yAxisLabel_(obj)
        [titleText, hasTitle] = getTitleText_(obj)
        c = directionColors_(obj, direction)
        c = responseCodeColors_(obj, decodedResponses, mask)
        values = columnize_(obj, values)
        s = sessionVectors_(obj)

        function name = menuPreferenceName_(obj)
            % Preference name for the right-click menu choices: the hosting
            % figure's Tag (else Name) and the tracked parameter, so two
            % staircases in one GUI, or one staircase in two GUIs, keep
            % their own settings. A pop-out window has its own Tag, so it
            % never writes over the embedded plot's choices.
            host = '';
            f = obj.plotFigure_;
            if ~isempty(f) && isvalid(f)
                host = f.Tag;
                if isempty(host), host = f.Name; end
            end
            if isempty(host), host = 'default'; end
            name = matlab.lang.makeValidName(sprintf('%s_%s', host, char(obj.ParameterName)));
        end

        function loadMenuPreferences_(obj)
            % Apply the operator's saved menu choices, recomputing once if a
            % threshold setting changed. Only menu actions save, so a
            % programmatic setting is never persisted.
            try
                name = obj.menuPreferenceName_();
                if ~ispref(obj.MENU_PREF_GROUP, name), return; end
                s = getpref(obj.MENU_PREF_GROUP, name);

                oldN = obj.ThresholdFromLastNReversals;
                oldFormula = obj.ThresholdFormula;
                if isfield(s, 'ThresholdFromLastNReversals')
                    obj.ThresholdFromLastNReversals = s.ThresholdFromLastNReversals;
                end
                if isfield(s, 'ThresholdFormula')
                    obj.ThresholdFormula = s.ThresholdFormula;
                end
                if isfield(s, 'ShowSteps'), obj.ShowSteps = s.ShowSteps; end
                if isfield(s, 'ShowReversals'), obj.ShowReversals = s.ShowReversals; end

                if oldN ~= obj.ThresholdFromLastNReversals || oldFormula ~= obj.ThresholdFormula
                    obj.refresh();
                end
            catch ME
                vprintf(2, 'Staircase %s: saved menu preferences not applied: %s', ...
                    char(obj.ParameterName), ME.message);
            end
        end

        function saveMenuPreferences_(obj)
            % Persist the right-click menu choices; called by the menu
            % callbacks in createPlotContextMenu_.
            try
                s = struct( ...
                    'ThresholdFromLastNReversals', obj.ThresholdFromLastNReversals, ...
                    'ThresholdFormula', char(obj.ThresholdFormula), ...
                    'ShowSteps', obj.ShowSteps, ...
                    'ShowReversals', obj.ShowReversals);
                setpref(obj.MENU_PREF_GROUP, obj.menuPreferenceName_(), s);
            catch ME
                vprintf(2, 'Staircase %s: menu preferences not saved: %s', ...
                    char(obj.ParameterName), ME.message);
            end
        end
    end

    properties (Constant, Access = private)
        MENU_PREF_GROUP = 'epsych2_psychophysics_Staircase'
    end


end
