classdef Staircase < handle & matlab.mixin.SetGet
    % Adaptive staircase analysis that tracks reversals and computes thresholds.
    % 
    % psychophysics.Staircase analyzes trial data to maintain staircase state, including 
    % reversals, step direction, and threshold estimates. It listens to RUNTIME.HELPER 
    % NewData events and recomputes staircase history with each trial. The class exposes 
    % dependent accessors for responseCodes, stimulusValues, and trialCount, as well as 
    % computed properties ReversalCount, ReversalIdx, and Threshold.
    %
    % Usage:
    %   S = psychophysics.Staircase(RUNTIME, Parameter)
    %   S = psychophysics.Staircase(RUNTIME, Parameter, StaircaseDirection="Up")
    %
    % Key properties:
    %   StaircaseDirection — "Up" or "Down"; defines direction for reversal detection
    %   StimulusTrialType — BitMask identifying stimulus trials for analysis
    %   ConvertToDecibels — when true, converts stimulus values using 20*log10(x)

    properties (SetObservable)
        Parameter = []  % Parameter object to track in staircase analysis

        StaircaseDirection (1,1) string {mustBeMember(StaircaseDirection,["Up","Down"])} = "Down"  % Direction for reversal detection

        StimulusTrialType (1,1) epsych.BitMask = epsych.BitMask.TrialType_0  % BitMask identifying stimulus trials
        CatchTrialType    (1,1) epsych.BitMask = epsych.BitMask.TrialType_1  % BitMask identifying catch trials

        ThresholdFromLastNReversals (1,1) double {mustBePositive, mustBeInteger} = 12  % Number of reversals to use in threshold calculation
        ThresholdFormula (1,1) string {mustBeMember(ThresholdFormula,["Mean","GeometricMean"])} = "Mean"  % Formula for computing threshold from reversals
        ConvertToDecibels (1,1) logical = false  % If true, convert stimulus values to dB using 20*log10(x)

        

        Bits (1,:) epsych.BitMask = epsych.BitMask.getResponses;  % Response codes for visualization
        BitColors (5,1) string = ["#dff7df","#fcdcdc","#d9f2ff","#fcdefc","#fcfcd4"];  % Colors for response visualization
    end

    properties (SetAccess = private)
        RUNTIME  % Runtime object containing trial data and event infrastructure
        Helper = epsych.Helper  % Helper object for event broadcasting
        
        DATA  % Trial data array extracted from RUNTIME

        ReversalCount   % Total number of reversals observed in staircase history
        ReversalIdx     % Indices of trials where reversals occurred in stimulus sequence
        StepDirection   % Direction of staircase step at each trial (1=up, -1=down, nan=neutral)
        Threshold       % Current threshold estimate based on last N reversals
        ThresholdStd    % Standard deviation of threshold values from last N reversals
    end

    properties (Dependent)
        % Dependent properties provide read-only access to computed trial data
        responseCodes  % Response codes extracted from DATA
        stimulusValues  % Stimulus parameter values from DATA, optionally converted to decibels
        trialCount  % Total number of trials in DATA
    end

    properties (Access = private)
        hl_NewData = event.listener.empty
    end

    methods
        function obj = Staircase(RUNTIME, Parameter,options)
            % S = psychophysics.Staircase(RUNTIME, Parameter)
            % S = psychophysics.Staircase(RUNTIME, Parameter, StaircaseDirection="Up", ConvertToDecibels=true)
            %
            % Construct a Staircase object and attach a listener to RUNTIME.HELPER.
            % The staircase automatically recomputes reversals and thresholds when new 
            % trial data arrives. Stimulus trials are filtered by StimulusTrialType mask 
            % for reversal detection. When ConvertToDecibels is true, stimulus values are 
            % transformed as dB = 20*log10(x) with x<=0 replaced by NaN.
            %
            % Parameters:
            %   RUNTIME — Runtime object with HELPER and trial data
            %   Parameter — hw.Parameter object to track in staircase
            %   StimulusTrialType — BitMask for stimulus trials (default: TrialType_0)
            %   CatchTrialType — BitMask for catch trials (default: TrialType_1)
            %   StaircaseDirection — "Up" or "Down" (default: "Down")
            %   ConvertToDecibels — convert stimulus values to dB (default: false)
            arguments
                RUNTIME 
                Parameter
                options.StimulusTrialType (1,1) epsych.BitMask = epsych.BitMask.TrialType_0
                options.CatchTrialType (1,1) epsych.BitMask = epsych.BitMask.TrialType_1
                options.StaircaseDirection (1,1) string {mustBeMember(options.StaircaseDirection,["Up","Down"])} = "Down"
                options.ConvertToDecibels (1,1) logical = false
            end

            obj.RUNTIME = RUNTIME;
            obj.Parameter = Parameter;
            obj.StimulusTrialType = options.StimulusTrialType;
            obj.CatchTrialType = options.CatchTrialType;
            obj.StaircaseDirection = options.StaircaseDirection;
            obj.ConvertToDecibels = options.ConvertToDecibels;

            obj.hl_NewData = addlistener(RUNTIME.HELPER,'NewData',@obj.update_data);
            
        end

        function delete(obj)
            % Remove NewData listener and clean up event infrastructure.
            % This destructor ensures proper cleanup of the listener attached in the constructor.
            if ~isempty(obj.hl_NewData)
                delete(obj.hl_NewData);
                obj.hl_NewData = event.listener.empty;
            end
        end

        function update_data(obj, ~, event)
            % Handle NewData event from RUNTIME.HELPER and update staircase state.
            % Extracts trial data from the event, recomputes reversal history, and 
            % broadcasts a NewData notification to listeners.
            vprintf(4, 'psychophysics.Staircase received NewData event with %d trials', numel(event.Data.DATA));
            obj.DATA = event.Data.DATA;

            obj.recompute_history();

            evtdata = epsych.TrialsData(event.Data);
            obj.Helper.notify('NewData',evtdata);
        end

        function refresh_history(obj)
            % Recompute staircase history and notify listeners of updates.
            % Call this method when data may have changed outside the normal NewData event pathway.
            obj.recompute_history();
            obj.notify_history_update();
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
                obj.StepDirection = [];
                obj.Threshold = [];
                obj.ThresholdStd = [];
                return
            end

            RCD = epsych.BitMask.decode(obj.responseCodes);

            ind = RCD.(char(obj.StimulusTrialType));

            stimValues = obj.stimulusValues(ind);
            
            d = sign(diff(stimValues));
            if obj.StaircaseDirection == "Up"
                d = -d;
            end

            obj.StepDirection = [nan,d];
            obj.ReversalIdx = find(d(2:end)~=0 & (d(2:end)<d(1:end-1) | d(2:end) > d(1:end-1))) + 1;


            obj.ReversalCount = length(obj.ReversalIdx);

            if obj.ReversalCount > 0
                lastNReversals = obj.ReversalIdx(max(1, end - obj.ThresholdFromLastNReversals + 1):end);
                thresholdValues = stimValues(lastNReversals);
                
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

    
end