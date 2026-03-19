classdef Staircase < handle & matlab.mixin.SetGet
    % Adaptive staircase analysis that tracks reversals and computes thresholds.
    % 
    % psychophysics.Staircase analyzes trial data to maintain staircase state, including
    % reversals, step direction, and threshold estimates. The class exposes dependent
    % accessors for responseCodes, stimulusValues, and trialCount, as well as computed
    % properties ReversalCount, ReversalIdx, and Threshold.
    %
    % Modes:
    %   Online mode  — Construct with a Runtime object as the first input. The Staircase
    %                 attaches a listener to RUNTIME.HELPER and recomputes history on
    %                 each NewData event.
    %   Offline mode — Construct with DATA (a per-trial struct array, often loaded from session files)
    %                 as the first input. No listener is attached; history is computed
    %                 immediately from DATA and can be recomputed via refresh_history().
    %
    % Usage:
    %   S = psychophysics.Staircase(RUNTIME, Parameter)
    %   S = psychophysics.Staircase(RUNTIME, Parameter, StaircaseDirection="Up")
    %   S = psychophysics.Staircase(DATA, Parameter)
    %   S = psychophysics.Staircase(DATA, Parameter, EnablePlot=true)
    %   S = psychophysics.Staircase(DATA, Parameter, EnablePlot=true, PlotAxes=ax)
    %
    % Key properties:
    %   StaircaseDirection — "Up" or "Down"; defines direction for reversal detection
    %   StimulusTrialType — BitMask identifying stimulus trials for analysis
    %   ConvertToDecibels — when true, converts stimulus values using 20*log10(x)
    %
    % See also: documentation/Staircase.md

    properties (SetObservable)
        Parameter = []  % Parameter object to track in staircase analysis

        StaircaseDirection (1,1) string {mustBeMember(StaircaseDirection,["Up","Down"])} = "Down"  % Direction for reversal detection

        StimulusTrialType (1,1) epsych.BitMask = epsych.BitMask.TrialType_0  % BitMask identifying stimulus trials
        CatchTrialType    (1,1) epsych.BitMask = epsych.BitMask.TrialType_1  % BitMask identifying catch trials

        ThresholdFromLastNReversals (1,1) double {mustBePositive, mustBeInteger} = 12  % Number of reversals to use in threshold calculation
        ThresholdFormula (1,1) string {mustBeMember(ThresholdFormula,["Mean","GeometricMean"])} = "Mean"  % Formula for computing threshold from reversals
        ConvertToDecibels (1,1) logical = false  % If true, convert stimulus values to dB using 20*log10(x)

        

        Bits (1,:) epsych.BitMask = epsych.BitMask.getResponses;  % Response codes for visualization
        BitColors (:,1) string = epsych.BitMask.getDefaultColors(epsych.BitMask.getResponses(:));  % Colors mapped to Bits for response visualization

        % Optional plotting configuration (when enabled via enablePlot or constructor option).
        LineColor     (1,1) string = "#2659bf"
        StepColor     (1,1) string = "#e65a1a"
        NeutralColor  (1,1) string = "#999999"
        ReversalColor (1,1) string = "#1a1a1a"

        MarkerSize (1,1) double {mustBePositive} = 40
        StepMarkerSize (1,1) double {mustBePositive} = 72
        ReversalMarkerSize (1,1) double {mustBePositive} = 110

        ShowSteps (1,1) logical = true
        ShowReversals (1,1) logical = true
    end

    properties (SetAccess = private)
        RUNTIME  % Runtime object containing trial data and event infrastructure
        Helper = epsych.Helper  % Helper object for event broadcasting
        
        DATA  % Trial data array extracted from RUNTIME

        ReversalCount   % Total number of reversals observed in staircase history
        ReversalIdx     % Absolute trial indices in DATA where reversals occur (turning points)
        ReversalDirection  % Direction after each reversal (+1=up, -1=down)
        StepDirection   % Per-trial step direction (NaN for non-stim trials)
        StimulusTrialIdx  % Absolute trial indices in DATA that are stimulus trials
        Threshold       % Current threshold estimate based on last N reversals
        ThresholdStd    % Standard deviation of threshold values from last N reversals
    end

    properties (Dependent)
        % Dependent properties provide read-only access to computed trial data
        responseCodes  % Response codes extracted from DATA
        stimulusValues  % Stimulus parameter values from DATA, optionally converted to decibels
        trialCount  % Total number of trials in DATA

        ParameterName % Convenience accessor for plot labels/titles
    end

    properties (Access = private)
        hl_NewData = event.listener.empty

        % Plot state (optional).
        plotEnabled_ (1,1) logical = false
        plotAxes_ = []
        plotFigure_ = []
        plotOwnsFigure_ (1,1) logical = false
        plotListeners_ = event.listener.empty

        h_line
        h_points
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
            % S = psychophysics.Staircase(RUNTIME, Parameter, EnablePlot=true)
            % S = psychophysics.Staircase(RUNTIME, Parameter, EnablePlot=true, PlotAxes=ax)
            % S = psychophysics.Staircase(DATA, Parameter, EnablePlot=true)
            % S = psychophysics.Staircase(DATA, Parameter, EnablePlot=true, PlotAxes=ax)
            %
            % Construct a Staircase object for online or offline analysis.
            %
            % Online mode:
            %   Pass RUNTIME as the first input to attach a listener to RUNTIME.HELPER
            %   and automatically update history on each NewData event.
            %
            % Offline mode:
            %   Pass DATA (the per-trial struct array, e.g. event.Data.DATA) as the first
            %   input to compute staircase history immediately without attaching listeners.
            %
            % In online mode, the staircase automatically recomputes reversals and
            % thresholds when new trial data arrives. In offline mode, call refresh_history()
            % after modifying obj.DATA.
            %
            % Stimulus trials are filtered by StimulusTrialType mask for reversal detection.
            % When ConvertToDecibels is true, stimulus values are transformed as
            % dB = 20*log10(x) with x<=0 replaced by NaN.
            %
            % Plotting is optional. When EnablePlot is true and PlotAxes is empty, the
            % Staircase creates and owns a new figure/axes for online updates.
            %
            % Parameters:
            %   RUNTIME — Runtime object with HELPER and trial data (online mode)
            %   DATA — per-trial struct array (offline mode), typically event.Data.DATA
            %   Parameter — hw.Parameter object to track in staircase
            %   StimulusTrialType — BitMask for stimulus trials (default: TrialType_0)
            %   CatchTrialType — BitMask for catch trials (default: TrialType_1)
            %   StaircaseDirection — "Up" or "Down" (default: "Down")
            %   ConvertToDecibels — convert stimulus values to dB (default: false)
            %   EnablePlot — enable online plotting (default: false)
            %   PlotAxes — axes for plotting; when empty, creates a new figure (default: [])
            %   ShowSteps — show step markers when plotting (default: true)
            %   ShowReversals — show reversal markers when plotting (default: true)
            arguments
                RUNTIME 
                Parameter
                options.StimulusTrialType (1,1) epsych.BitMask = epsych.BitMask.TrialType_0
                options.CatchTrialType (1,1) epsych.BitMask = epsych.BitMask.TrialType_1
                options.StaircaseDirection (1,1) string {mustBeMember(options.StaircaseDirection,["Up","Down"])} = "Down"
                options.ConvertToDecibels (1,1) logical = false
                options.EnablePlot (1,1) logical = false
                options.PlotAxes = []
                options.ShowSteps (1,1) logical = true
                options.ShowReversals (1,1) logical = true
            end

            if isstruct(RUNTIME)
                obj.RUNTIME = [];
                obj.DATA = RUNTIME;
            else
                obj.RUNTIME = RUNTIME;
            end

            obj.Parameter = Parameter;
            obj.StimulusTrialType = options.StimulusTrialType;
            obj.CatchTrialType = options.CatchTrialType;
            obj.StaircaseDirection = options.StaircaseDirection;
            obj.ConvertToDecibels = options.ConvertToDecibels;

            if isempty(obj.RUNTIME)
                obj.hl_NewData = event.listener.empty;
                obj.recompute_history();
            else
                obj.hl_NewData = addlistener(obj.RUNTIME.HELPER,'NewData',@obj.update_data);
            end

            if options.EnablePlot
                obj.enablePlot(options.PlotAxes, ShowSteps=options.ShowSteps, ShowReversals=options.ShowReversals);
            end
            
        end

        function delete(obj)
            % delete(obj)
            % Destroy Staircase and release listeners/graphics.
            %
            % Parameters:
            %   obj — psychophysics.Staircase instance
            obj.disablePlot();

            if ~isempty(obj.hl_NewData)
                delete(obj.hl_NewData);
                obj.hl_NewData = event.listener.empty;
            end
        end

        function update_data(obj, ~, event)
            % update_data(obj, ~, event)
            % Update staircase state from a runtime NewData event.
            %
            % Parameters:
            %   obj — psychophysics.Staircase instance
            %   event — event data containing event.Data.DATA (trial struct array)
            vprintf(4, 'psychophysics.Staircase received NewData event with %d trials', numel(event.Data.DATA));
            obj.DATA = event.Data.DATA;

            obj.recompute_history();

            if obj.plotEnabled_
                obj.updatePlot_();
            end

            evtdata = epsych.TrialsData(event.Data);
            obj.Helper.notify('NewData',evtdata);
        end

        function refresh_history(obj)
            % refresh_history(obj)
            % Recompute staircase history and notify listeners.
            %
            % Parameters:
            %   obj — psychophysics.Staircase instance
            obj.recompute_history();

            if obj.plotEnabled_
                obj.updatePlot_();
            end

            obj.notify_history_update();
        end

        function enablePlot(obj, ax, options)
            % obj.enablePlot()
            % obj.enablePlot(ax)
            % obj.enablePlot(ax, ShowSteps=true, ShowReversals=true)
            %
            % Enable optional online plotting of staircase history.
            % If ax is empty, a new uifigure and uiaxes are created and owned.
            %
            % Parameters:
            %   obj — psychophysics.Staircase instance
            %   ax — target axes; when empty, a new figure/axes is created (default: [])
            %   ShowSteps — show step-direction markers (default: obj.ShowSteps)
            %   ShowReversals — show reversal markers (default: obj.ShowReversals)
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
            %
            % Parameters:
            %   obj — psychophysics.Staircase instance
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
            %
            % Parameters:
            %   obj — psychophysics.Staircase instance
            if ~obj.plotEnabled_
                return
            end
            obj.updatePlot_();
        end


        function rc = get.responseCodes(obj)
            % Extract response codes from DATA. Returns empty array if no data available.
            if isempty(obj.DATA)
                rc = [];
                return
            end

            rc = [obj.DATA.ResponseCode];
        end

        function n = get.trialCount(obj)
            % Return total number of trials in DATA.
            n = numel(obj.DATA);
        end

        function v = get.stimulusValues(obj)
            % Extract stimulus values from DATA using Parameter.validName. 
            % If ConvertToDecibels is true, transforms values as dB = 20*log10(x) 
            % with non-positive values replaced by NaN. Returns empty array if no data.
            if isempty(obj.DATA)
                v = [];
            else
                v = [obj.DATA.(obj.Parameter.validName)];
                if obj.ConvertToDecibels
                    v(v<=0) = nan;
                    v = 20*log10(v);
                end
            end
        end

        function n = get.ParameterName(obj)
            if isempty(obj.Parameter)
                n = "";
                return
            end
            if isprop(obj.Parameter,'Name')
                n = string(obj.Parameter.Name);
            else
                n = string(class(obj.Parameter));
            end
        end

        
        
    end

    methods (Access = private)
        function recompute_history(obj)
            % Recompute reversal indices, step direction, and threshold estimates.
            % Filters trial data by StimulusTrialType, detects reversals by comparing 
            % consecutive step directions, and calculates threshold from the last N reversals 
            % using the specified ThresholdFormula. Sets properties to empty if no data available.
            obj.ReversalCount = 0;

            data = obj.DATA;
            if isempty(data)
                obj.ReversalIdx = [];
                obj.ReversalDirection = [];
                obj.StepDirection = [];
                obj.StimulusTrialIdx = [];
                obj.Threshold = [];
                obj.ThresholdStd = [];
                return
            end

            RCD = epsych.BitMask.decode(obj.responseCodes);

            stimMask = RCD.(char(obj.StimulusTrialType));
            obj.StimulusTrialIdx = find(stimMask);

            stimValues = obj.stimulusValues(stimMask);

            aborts = RCD.Abort;

            naidx = find(~aborts);
            sv = stimValues(~aborts);

            sd = sign(diff(sv));
            if obj.StaircaseDirection == "Up"
                sd = -sd;
            end

            stepDirection = zeros(1, obj.trialCount);
            if ~isempty(sd)
                stepDirection(obj.StimulusTrialIdx(naidx)) = [0 sd];
            end
            obj.StepDirection = stepDirection;

            obj.ReversalIdx = [];
            obj.ReversalDirection = [];
            if numel(sd) >= 2
                rind = sd(2:end) ~= sd(1:end-1);
                reversalStimIdx = naidx(rind) + 1;
                obj.ReversalIdx = reversalStimIdx;
                obj.ReversalDirection = sd(rind+1);
            end

            obj.ReversalCount = numel(obj.ReversalIdx);

            if obj.ReversalCount > 0
                lastN = max(1, obj.ReversalCount - obj.ThresholdFromLastNReversals + 1):obj.ReversalCount;
                thresholdValues = obj.stimulusValues(obj.ReversalIdx(lastN));
                
                if obj.ThresholdFormula == "Mean"
                    obj.Threshold = mean(thresholdValues);
                else % GeometricMean
                    obj.Threshold = geomean(thresholdValues);
                end
                obj.ThresholdStd = std(thresholdValues);

            else
                obj.Threshold = [];
                obj.ThresholdStd = [];
            end
        end

        function notify_history_update(obj)
            % Broadcast NewData event to listeners with current trial state.
            % Returns silently if RUNTIME or RUNTIME.TRIALS is not available.
            if isempty(obj.RUNTIME) || ~isprop(obj.RUNTIME, 'TRIALS') || isempty(obj.RUNTIME.TRIALS)
                return
            end

            evtdata = epsych.TrialsData(obj.RUNTIME.TRIALS);
            obj.Helper.notify('NewData', evtdata);
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

        [x, y, c, xStep, yStep, cStep, xRevUp, yRevUp, xRevDown, yRevDown] = getPlotData_(obj)
        updatePlotLabels_(obj)
        [titleText, hasTitle] = getTitleText_(obj)
        c = directionColors_(obj, direction)
        c = responseCodeColors_(obj, responseCodes)
        values = columnize_(obj, values)
    end

    
end