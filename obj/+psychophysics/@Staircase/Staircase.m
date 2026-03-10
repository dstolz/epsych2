classdef Staircase < handle & matlab.mixin.SetGet
    % STAIRCASE Read-only behavioral staircase history analyzer.
    %   psychophysics.Staircase listens for NewData events and derives
    %   staircase-relevant histories from completed trial data without
    %   writing back to parameters, trial tables, or runtime state.
    %
    %   S = psychophysics.Staircase(SOURCE) attaches to SOURCE and listens
    %   for NewData events carrying epsych.TrialsData payloads.
    %
    %   S = psychophysics.Staircase(SOURCE, Name=Value, ...) configures the
    %   tracked parameter, staircase step sizes, bounds, and N-up/M-down
    %   inference rules.
    %
    %   The class mirrors staircase behavior analytically. It records the
    %   observed outcome sequence, infers when a staircase step would have
    %   occurred and tracks reversals using only observed trial data.
    %   No external state is mutated.
    %
    %   Required event contract:
    %     SOURCE must emit a NewData event whose event.Data field contains
    %     the updated TRIALS struct, as provided by epsych.TrialsData.
    %
    %   Default semantics:
    %     - Hit on a stimulus trial steps down by StepOnHit.
    %     - Miss on a stimulus trial steps up by StepOnMiss.
    %     - Catch-trial outcomes are neutral unless configured otherwise.
    %     - Neutral trials do not break consecutive hit/miss counts.

    properties (SetObservable)
        Parameter = []
        ParameterName (1,1) string = ""

        StimulusTrialType (1,1) epsych.BitMask = epsych.BitMask.TrialType_0
        CatchTrialType    (1,1) epsych.BitMask = epsych.BitMask.TrialType_1

        StepOnHit  (1,1) double {mustBeFinite, mustBeNonnegative} = 0.02
        StepOnMiss (1,1) double {mustBeFinite, mustBeNonnegative} = 0.01

        MinValue (1,1) double = -inf
        MaxValue (1,1) double = inf

        UpCountRequired   (1,1) double {mustBeInteger, mustBePositive} = 1
        DownCountRequired (1,1) double {mustBeInteger, mustBePositive} = 1

        FalseAlarmBehavior   (1,1) string {mustBeMember(FalseAlarmBehavior,["hold","up","down"])} = "hold"
        CorrectRejectBehavior (1,1) string {mustBeMember(CorrectRejectBehavior,["hold","up","down"])} = "hold"
        AbortBehavior        (1,1) string {mustBeMember(AbortBehavior,["hold","up","down"])} = "hold"
    end

    properties (SetAccess = private)
        Source = []
        TRIALS = []

        TrialIndexHistory = []
        TrialTypeRawHistory = []
        TrialTypeHistory = strings(1,0)
        TrialValueHistory = []
        OutcomeHistory = strings(1,0)
        DirectionHistory = strings(1,0)
        StepAppliedHistory = false(1,0)
        ReversalHistory = false(1,0)
        ReversalCount (1,1) double = 0
    end

    properties (Dependent)
        DATA
        responseCodes
        trialCount
        CurrentValue
        LastOutcome
        LastDirection
    end

    properties (Access = private)
        hl_NewData = event.listener.empty
    end

    methods
        function obj = Staircase(source, options)
            % STAIRCASE Construct a read-only staircase observer.
            arguments
                source = []
                options.Parameter = []
                options.ParameterName (1,1) string = ""
                options.StimulusTrialType (1,1) epsych.BitMask = epsych.BitMask.TrialType_0
                options.CatchTrialType (1,1) epsych.BitMask = epsych.BitMask.TrialType_1
                options.StepOnHit (1,1) double {mustBeFinite, mustBeNonnegative} = 0.02
                options.StepOnMiss (1,1) double {mustBeFinite, mustBeNonnegative} = 0.01
                options.MinValue (1,1) double = -inf
                options.MaxValue (1,1) double = inf
                options.UpCountRequired (1,1) double {mustBeInteger, mustBePositive} = 1
                options.DownCountRequired (1,1) double {mustBeInteger, mustBePositive} = 1
                options.FalseAlarmBehavior (1,1) string {mustBeMember(options.FalseAlarmBehavior,["hold","up","down"])} = "hold"
                options.CorrectRejectBehavior (1,1) string {mustBeMember(options.CorrectRejectBehavior,["hold","up","down"])} = "hold"
                options.AbortBehavior (1,1) string {mustBeMember(options.AbortBehavior,["hold","up","down"])} = "hold"
                options.Attach (1,1) logical = true
            end

            obj.Parameter = options.Parameter;
            obj.ParameterName = options.ParameterName;
            obj.StimulusTrialType = options.StimulusTrialType;
            obj.CatchTrialType = options.CatchTrialType;
            obj.StepOnHit = options.StepOnHit;
            obj.StepOnMiss = options.StepOnMiss;
            obj.MinValue = options.MinValue;
            obj.MaxValue = options.MaxValue;
            obj.UpCountRequired = options.UpCountRequired;
            obj.DownCountRequired = options.DownCountRequired;
            obj.FalseAlarmBehavior = options.FalseAlarmBehavior;
            obj.CorrectRejectBehavior = options.CorrectRejectBehavior;
            obj.AbortBehavior = options.AbortBehavior;

            if nargin < 1 || isempty(source)
                return
            end

            if isa(source,'epsych.TrialsData')
                obj.ingest(source.Data);
            elseif isstruct(source)
                obj.ingest(source);
            elseif options.Attach
                obj.attach(source);
            end
        end

        function delete(obj)
            obj.detach();
        end

        function attach(obj, source)
            % ATTACH Listen to a source that emits NewData events.
            obj.detach();

            if isempty(source)
                return
            end

            source = Staircase.resolveEventSource(source);
            obj.hl_NewData = addlistener(source,'NewData',@obj.update_data);
            obj.Source = source;
        end

        function detach(obj)
            % DETACH Remove any active NewData listener.
            if ~isempty(obj.hl_NewData)
                delete(obj.hl_NewData);
                obj.hl_NewData = event.listener.empty;
            end
            obj.Source = [];
        end

        function reset(obj)
            % RESET Clear cached trials and derived histories.
            obj.TRIALS = [];
            obj.TrialIndexHistory = [];
            obj.TrialTypeRawHistory = [];
            obj.TrialTypeHistory = strings(1,0);
            obj.TrialValueHistory = [];
            obj.OutcomeHistory = strings(1,0);
            obj.DirectionHistory = strings(1,0);
            obj.StepAppliedHistory = false(1,0);
            obj.ReversalHistory = false(1,0);
            obj.ReversalCount = 0;
        end

        function ingest(obj, payload)
            % INGEST Recompute staircase histories from a trials snapshot.
            if isa(payload,'epsych.TrialsData')
                payload = payload.Data;
            end

            if isempty(payload)
                obj.reset();
                return
            end

            obj.TRIALS = payload;
            obj.recompute_history();
        end

        function update_data(obj, ~, event)
            % UPDATE_DATA Listener callback for NewData events.
            if nargin < 3 || isempty(event)
                return
            end

            obj.ingest(event.Data);
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

        function v = get.CurrentValue(obj)
            stimCode = Staircase.bitMaskToTrialTypeCode(obj.StimulusTrialType);
            idx = find(obj.TrialTypeRawHistory == stimCode & ~isnan(obj.TrialValueHistory), 1, 'last');
            if isempty(idx)
                v = nan;
            else
                v = obj.TrialValueHistory(idx);
            end
        end

        function s = get.LastOutcome(obj)
            if isempty(obj.OutcomeHistory)
                s = "";
            else
                s = obj.OutcomeHistory(end);
            end
        end

        function s = get.LastDirection(obj)
            if isempty(obj.DirectionHistory)
                s = "";
            else
                s = obj.DirectionHistory(end);
            end
        end
    end

    methods (Access = private)
        function recompute_history(obj)
            obj.TrialIndexHistory = [];
            obj.TrialTypeRawHistory = [];
            obj.TrialTypeHistory = strings(1,0);
            obj.TrialValueHistory = [];
            obj.OutcomeHistory = strings(1,0);
            obj.DirectionHistory = strings(1,0);
            obj.StepAppliedHistory = false(1,0);
            obj.ReversalHistory = false(1,0);
            obj.ReversalCount = 0;

            data = obj.DATA;
            if isempty(data)
                return
            end

            fieldName = char(obj.ParameterName);

            nTrials = numel(data);
            obj.TrialIndexHistory = nan(1,nTrials);
            obj.TrialTypeRawHistory = nan(1,nTrials);
            obj.TrialTypeHistory = strings(1,nTrials);
            obj.TrialValueHistory = nan(1,nTrials);
            obj.OutcomeHistory = strings(1,nTrials);
            obj.DirectionHistory = repmat("none",1,nTrials);
            obj.StepAppliedHistory = false(1,nTrials);
            obj.ReversalHistory = false(1,nTrials);

            decoded = epsych.BitMask.decode([obj.DATA.ResponseCode]);

            stimCode = Staircase.bitMaskToTrialTypeCode(obj.StimulusTrialType);
            lastNonzeroDirection = 0;
            upCount = 0;
            downCount = 0;

            for idx = 1:nTrials
                trial = data(idx);

                obj.TrialIndexHistory(idx) = trial.TrialID;
                obj.TrialTypeRawHistory(idx) = trial.TrialType;
                obj.TrialTypeHistory(idx) = Staircase.trialTypeCodeToName(obj.TrialTypeRawHistory(idx));
                obj.TrialValueHistory(idx) = trial.(fieldName);

                outcome = Staircase.normalizeOutcome(decoded, idx);
                obj.OutcomeHistory(idx) = outcome;

                stepDirection = 0;
                if obj.TrialTypeRawHistory(idx) == stimCode
                    [stepDirection, upCount, downCount] = obj.inferStimulusStep(outcome, upCount, downCount);
                end

                if stepDirection ~= 0
                    obj.DirectionHistory(idx) = Staircase.directionCodeToName(stepDirection);
                    obj.StepAppliedHistory(idx) = true;

                    obj.ReversalHistory(idx) =  lastNonzeroDirection ~= 0 && stepDirection ~= lastNonzeroDirection;
   
                    lastNonzeroDirection = stepDirection;
                end
            end

            obj.ReversalCount = sum(obj.ReversalHistory);
        end

        function [stepDirection, upCount, downCount] = inferStimulusStep(obj, outcome, upCount, downCount)
            stepDirection = 0;

            switch outcome
                case "hit"
                    downCount = downCount + 1;
                    upCount = 0;
                    if downCount >= obj.DownCountRequired
                        stepDirection = -1;
                        downCount = 0;
                    end

                case "miss"
                    upCount = upCount + 1;
                    downCount = 0;
                    if upCount >= obj.UpCountRequired
                        stepDirection = 1;
                        upCount = 0;
                    end
            end
        end

    end

    methods (Static, Access = private)
        function outcome = normalizeOutcome(decoded, idx)
            outcome = "other";

            if decoded.Hit(idx)
                outcome = "hit";
            elseif decoded.Miss(idx)
                outcome = "miss";
            elseif decoded.FalseAlarm(idx)
                outcome = "fa";
            elseif decoded.CorrectReject(idx)
                outcome = "cr";
            elseif decoded.Abort(idx)
                outcome = "abort";
            end
        end

        function source = resolveEventSource(source)
            if isprop(source,'HELPER')
                source = source.HELPER;
            elseif isprop(source,'Helper')
                source = source.Helper;
            end
        end

        function name = trialTypeCodeToName(code)
            if isnan(code)
                name = "Undefined";
            else
                name = "TrialType_" + string(code);
            end
        end

        function code = bitMaskToTrialTypeCode(bitMask)
            token = extractAfter(string(bitMask), "TrialType_");
            code = str2double(token);
        end

        function name = directionCodeToName(code)
            switch code
                case -1
                    name = "down";
                case 1
                    name = "up";
                otherwise
                    name = "none";
            end
        end
    end
end