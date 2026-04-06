classdef Staircase < psychophysics.Psych
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
    %   ConvertToDecibels - Convert stimulus values using 20*log10(x).
    %   ExcludedTrials - Trial exclusions specified as a logical mask or
    %       1-based trial indices.
    %   Results - Structure containing computed staircase outputs such as
    %       Threshold, ReversalIdx, and StepDirection.
    %
    % Example:
    %   S = psychophysics.Staircase(RUNTIME, Parameter, Plot=true);
    %   S = psychophysics.Staircase(DATA, Parameter, StaircaseDirection="Up");
    %   S = psychophysics.Staircase(DATA, 'Depth');
    %   S.ExcludedTrials = [1 4 7];
    %   S.Plot();
    %   S.Plot(ax, ShowSteps=false);
    %
    % See documentation/psychophysics_Staircase.md for workflow notes, threshold details, and
    % event-system integration examples.

    properties (SetObservable)
        StaircaseDirection (1,1) string {mustBeMember(StaircaseDirection,["Up","Down"])} = "Down"  % Direction for reversal detection

        StimulusTrialType (1,1) epsych.BitMask = epsych.BitMask.TrialType_0  % BitMask identifying stimulus trials
        CatchTrialType    (1,1) epsych.BitMask = epsych.BitMask.TrialType_1  % BitMask identifying catch trials

        ThresholdFromLastNReversals (1,1) double {mustBePositive, mustBeInteger} = 12  % Number of reversals to use in threshold calculation
        ThresholdFormula (1,1) string {mustBeMember(ThresholdFormula,["Mean","GeometricMean"])} = "Mean"  % Formula for computing threshold from reversals
        ConvertToDecibels (1,1) logical = false  % If true, convert stimulus values to dB using 20*log10(x)

        

        Bits (1,:) epsych.BitMask = epsych.BitMask.getResponses;  % Response codes for visualization
        BitColors (:,1) string = epsych.BitMask.getDefaultColors(epsych.BitMask.getResponses);  % Colors mapped to Bits for response visualization

        % Optional plotting configuration (when enabled via Plot or constructor option).
        LineColor     (1,1) string = "#1a1a1a"
        StepColor     (1,1) string = "#e65a1a"
        NeutralColor  (1,1) string = "#999999"
        ReversalColor (1,1) string = "#ff0095"

        MarkerSize (1,1) double {mustBePositive} = 40
        StepMarkerSize (1,1) double {mustBePositive} = 72
        ReversalMarkerSize (1,1) double {mustBePositive} = 110

        ShowSteps (1,1) logical = true
        ShowReversals (1,1) logical = true
    end

    properties (SetAccess = private)
        Results = struct( ...
            'ReversalCount', [], ...
            'ReversalIdx', [], ...
            'ReversalDirection', [], ...
            'StepDirection', [], ...
            'StimulusTrialIdx', [], ...
            'Threshold', [], ...
            'ThresholdStd', [])  % Computed staircase outputs
    end

    properties (Dependent)
        % Dependent properties provide read-only access to computed trial data
        stimulusValues  % Stimulus parameter values from DATA, optionally converted to decibels
    end

    properties (Access = private)
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
        plotContextMenu_ = []  % uicontextmenu for plot axes
    end

    methods
        function obj = Staircase(RUNTIME, Parameter,options)
            % S = psychophysics.Staircase(RUNTIME, Parameter)
            % S = psychophysics.Staircase(RUNTIME, Parameter, StaircaseDirection="Up", ConvertToDecibels=true)
            % S = psychophysics.Staircase(DATA, Parameter)
            % S = psychophysics.Staircase(RUNTIME, Parameter, Plot=true)
            % S = psychophysics.Staircase(RUNTIME, Parameter, Plot=true, PlotAxes=ax)
            % S = psychophysics.Staircase(DATA, Parameter, Plot=true)
            % S = psychophysics.Staircase(DATA, Parameter, Plot=true, PlotAxes=ax)
            %
            % Construct a Staircase object for online or offline analysis.
            %
            % Pass a Runtime object as the first input to attach a listener to
            % RUNTIME.HELPER and update automatically on each NewData event.
            %
            % Pass a DATA struct array as the first input to compute staircase history
            % immediately without attaching listeners.
            %
            % In online mode, the staircase automatically recomputes reversals and
            % thresholds when new trial data arrives. In offline mode, call refresh_history()
            % after modifying obj.DATA.
            %
            % Stimulus trials are filtered by StimulusTrialType mask for reversal detection.
            % When ConvertToDecibels is true, stimulus values are transformed as
            % dB = 20*log10(x) with x<=0 replaced by NaN.
            %
            % Plotting is optional. When Plot is true and PlotAxes is empty, the
            % Staircase creates and owns a new figure/axes for online updates.
            %
            % Parameters:
            %   RUNTIME              - Runtime object with HELPER and trial data for online mode.
            %   DATA                 - Per-trial struct array for offline mode, typically the loaded `Data` struct.
            %   Parameter            - hw.Parameter object, or in offline mode a field name from DATA.
            %   StimulusTrialType    - BitMask for stimulus trials (default: TrialType_0).
            %   CatchTrialType       - BitMask for catch trials (default: TrialType_1).
            %   StaircaseDirection   - "Up" or "Down" (default: "Down").
            %   ConvertToDecibels    - Convert stimulus values to dB (default: false).
            %   Plot                 - Enable staircase plotting (default: false).
            %   PlotAxes             - Axes to draw into; creates new figure when empty.
            %   ExcludedTrials       - Trial exclusions as a logical mask or 1-based indices.
            %   ShowSteps            - Show step-direction markers when plotting.
            %   ShowReversals        - Show reversal markers when plotting.
            %
            % Returns:
            %   obj - Configured psychophysics.Staircase instance.
            %
            % See documentation/psychophysics_Staircase.md for offline analysis and plotting examples.
            arguments
                RUNTIME 
                Parameter
                options.StimulusTrialType (1,1) epsych.BitMask = epsych.BitMask.TrialType_0
                options.CatchTrialType (1,1) epsych.BitMask = epsych.BitMask.TrialType_1
                options.StaircaseDirection (1,1) string {mustBeMember(options.StaircaseDirection,["Up","Down"])} = "Down"
                options.ConvertToDecibels (1,1) logical = false
                options.Plot (1,1) logical = false
                options.PlotAxes = []
                options.ExcludedTrials = []
                options.ShowSteps (1,1) logical = true
                options.ShowReversals (1,1) logical = true
            end

            obj = obj@psychophysics.Psych(RUNTIME, Parameter, ExcludedTrials=options.ExcludedTrials);
            obj.StimulusTrialType = options.StimulusTrialType;
            obj.CatchTrialType = options.CatchTrialType;
            obj.StaircaseDirection = options.StaircaseDirection;
            obj.ConvertToDecibels = options.ConvertToDecibels;

            if isempty(obj.RUNTIME)
                obj.refresh();
            end

            if options.Plot
                obj.Plot(options.PlotAxes, ShowSteps=options.ShowSteps, ShowReversals=options.ShowReversals);
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
            % See documentation/psychophysics_Staircase.md for plotting workflows.
            arguments
                obj
                ax = []
                options.ShowSteps (1,1) logical = obj.ShowSteps
                options.ShowReversals (1,1) logical = obj.ShowReversals
            end

            obj.disablePlot();

            obj.ShowSteps = options.ShowSteps;
            obj.ShowReversals = options.ShowReversals;

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
            %   v - Stimulus values for the tracked Parameter, optionally converted to
            %       decibels with nonpositive values replaced by NaN.
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
                if obj.ConvertToDecibels
                    v(v<=0) = nan;
                    v = 20*log10(v);
                end
            end
        end

        
        
    end

    methods (Access = protected)
        function recomputeResults_(obj)
            % Recompute reversal indices, step direction, and threshold estimates.
            % Only trials matching StimulusTrialType are used in the computation of step direction,
            % reversals, and thresholds. Filters trial data by StimulusTrialType, detects reversals by comparing
            % consecutive step directions, and calculates threshold from the last N reversals.
            % When DATA includes a TrialType field, that explicit value is used for
            % stimulus/catch selection before falling back to decoded response-code bits.
            % using the specified ThresholdFormula. Sets properties to empty if no data available.
            results = obj.emptyResults_();
            results.ReversalCount = 0;

            data = obj.DATA;
            if isempty(data)
                obj.Results = results;
                return
            end

            stimMask = obj.trialTypeMask_(obj.StimulusTrialType);
            results.StimulusTrialIdx = find(stimMask);

            stimValues = obj.stimulusValues(stimMask);



            sd = sign(diff(stimValues));
            if obj.StaircaseDirection == "Up"
                sd = -sd;
            end

            stepDirection = nan(1, obj.trialCount);
            if ~isempty(sd)
                stepDirection(results.StimulusTrialIdx) = [0 sd];
            end
            results.StepDirection = stepDirection;

            if numel(sd) >= 2
                rind = sd(1:end-1) ~= 0 & (sd(2:end) > sd(1:end-1) | sd(2:end) < sd(1:end-1));
                results.ReversalIdx = results.StimulusTrialIdx([false rind false]);
                results.ReversalDirection = sd([false rind]);
            end

            results.ReversalCount = numel(results.ReversalIdx);

            if results.ReversalCount > 0
                lastN = max(1, results.ReversalCount - obj.ThresholdFromLastNReversals + 1):results.ReversalCount;
                thresholdValues = obj.stimulusValues(results.ReversalIdx(lastN));
                
                if obj.ThresholdFormula == "Mean"
                    results.Threshold = mean(thresholdValues);
                else % GeometricMean
                    results.Threshold = geomean(thresholdValues);
                end
                results.ThresholdStd = std(thresholdValues);
            end

            obj.Results = results;
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
        end

        function afterRefresh_(obj)
            % Update the staircase plot after analysis refreshes when enabled.
            if obj.plotEnabled_
                obj.updatePlot_();
            end
        end

        

    end

    methods (Access = private)
        % Plot helper methods (implemented as separate files in @Staircase)
        attachPlotDestructionListeners_(obj)
        onPlotFigureClose_(obj, fig)
        deletePlotGraphics_(obj)
        setupPlotAxes_(obj)
        createPlotContextMenu_(obj)
        updatePlot_(obj)
        updateThresholdOverlay_(obj)

        plotData = getPlotData_(obj);
        % Update any code here that used the old outputs to use plotData fields
        updatePlotLabels_(obj)
        [titleText, hasTitle] = getTitleText_(obj)
        c = directionColors_(obj, direction)
        c = responseCodeColors_(obj, responseCodes)
        values = columnize_(obj, values)
    end

    
end