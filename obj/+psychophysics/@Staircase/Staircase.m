classdef Staircase < handle & matlab.mixin.SetGet
    % STAIRCASE Store staircase analysis settings and listener state.
    %
    %   psychophysics.Staircase keeps the tracked parameter, staircase
    %   direction, and trial-type masks used to analyze staircase data.
    %   The constructor takes RUNTIME and Parameter inputs, registers a
    %   NewData listener on RUNTIME.HELPER, and exposes dependent
    %   accessors for DATA,
    %   responseCodes, stimulusValues, and trialCount.
    %
    %   S = psychophysics.Staircase(RUNTIME, Parameter)
    %   S = psychophysics.Staircase(RUNTIME, Parameter, Name=Value)
    %
    %   ReversalCount, ReversalIdx, and StepDirection are maintained as
    %   private state for inferred staircase history.
    %
    %   2026-03-10

    properties (SetObservable)
        Parameter = []

        StaircaseDirection (1,1) string {mustBeMember(StaircaseDirection,["Up","Down"])} = "Down"

        StimulusTrialType (1,1) epsych.BitMask = epsych.BitMask.TrialType_0
        CatchTrialType    (1,1) epsych.BitMask = epsych.BitMask.TrialType_1
  end

    properties (SetAccess = private)
        
        ReversalCount   % total number of reversals observed
        ReversalIdx     % indices of trials where reversals occurred
        StepDirection   % inferred direction of staircase step at each trial (1=up, -1=down, nan=neutral)
        
    end

    properties (Dependent)
        DATA
        responseCodes
        stimulusValues
        trialCount
    end

    properties (Access = private)
        hl_NewData = event.listener.empty
    end

    methods
        function obj = Staircase(RUNTIME, Parameter,options)
            % STAIRCASE Construct a Staircase object and attach its listener.
            %
            %   S = psychophysics.Staircase(RUNTIME, Parameter)
            %   S = psychophysics.Staircase(RUNTIME, Parameter, Name=Value)
            %
            %   Parameter is stored in the Parameter property. Name-value
            %   options configure StimulusTrialType, CatchTrialType, and
            %   StaircaseDirection.
            %
            %   2026-03-10
            arguments
                RUNTIME 
                Parameter
                options.StimulusTrialType (1,1) epsych.BitMask = epsych.BitMask.TrialType_0
                options.CatchTrialType (1,1) epsych.BitMask = epsych.BitMask.TrialType_1
                options.Attach (1,1) logical = true
                options.StaircaseDirection (1,1) string {mustBeMember(options.StaircaseDirection,["Up","Down"])} = "Down"
            end

            obj.Parameter = Parameter;
            obj.StimulusTrialType = options.StimulusTrialType;
            obj.CatchTrialType = options.CatchTrialType;
            obj.AbortBehavior = options.AbortBehavior;
            obj.StaircaseDirection = options.StaircaseDirection;

            obj.hl_NewData = addlistener(RUNTIME.HELPER,'NewData',@obj.update_data);
            
        end

        function delete(obj)
            obj.detach();
        end

        function detach(obj)
            % DETACH Remove any active NewData listener.
            if ~isempty(obj.hl_NewData)
                delete(obj.hl_NewData);
                obj.hl_NewData = event.listener.empty;
            end
        end

        function update_data(obj, ~, event)
            
        end

        function d = get.DATA(obj)
            if isempty(obj.TRIALS)
                d = [];
            else
                d = obj.TRIALS.DATA;
            end
        end

        function rc = get.responseCodes(obj)
            if isempty(obj.DATA)
                rc = uint32([]);
                return
            end

            rc = uint32([obj.DATA.ResponseCode]);
        end

        function n = get.trialCount(obj)
            n = numel(obj.DATA);
        end

        function v = get.stimulusValues(obj)
            if isempty(obj.DATA)
                v = [];
            else
                v = [obj.DATA.(obj.Parameter.validName)];
            end
        end

        
        
    end

    methods (Access = private)
        function recompute_history(obj)
            obj.ReversalCount = 0;

            data = obj.DATA;
            if isempty(data)
                return
            end

            RCD = epsych.BitMask.decode(obj.responseCodes);

            ind = RCD.TrialType == obj.StimulusTrialType;

            stimValues = obj.stimulusValues(ind);
            
            d = sign(diff(stimValues));
            if obj.StaircaseDirection == "Up"
                d = -d;
            end

            obj.StepDirection = [nan,d];
            obj.ReversalIdx = find(d(2:end)>d(1:end-1)) + 1;


            obj.ReversalCount = length(obj.ReversalIdx);
        end

        

    end

    
end