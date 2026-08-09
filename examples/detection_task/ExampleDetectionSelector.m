classdef ExampleDetectionSelector < epsych.TrialSelector
    % ExampleDetectionSelector  Go/No-Go selector with a catch-rate policy.
    %
    % Demonstrates a custom epsych.TrialSelector. Policy:
    %   1. Catch (no-go) trials are drawn with probability CatchProbability.
    %   2. Runs of the same trial type are capped at MaxConsecutive; the cap
    %      forces a switch, which keeps the sequence unpredictable without
    %      long stretches of one type.
    %   3. Within the chosen type, the least-presented condition wins, ties
    %      broken at random (same balancing rule as epsych.DefaultTrialSelector).
    %
    % A protocol opts in by naming this class:
    %   P.setOption('trialFunc', 'ExampleDetectionSelector')
    % The class must be on the MATLAB path when the protocol validates and
    % when the session runs.
    %
    % Walkthrough: documentation/examples/Detection_Task_2_TrialSelector.md
    %
    % See also epsych.TrialSelector, epsych.DefaultTrialSelector

    properties
        CatchProbability (1,1) double {mustBeInRange(CatchProbability,0,1)} = 0.25
        MaxConsecutive   (1,1) double {mustBeInteger, mustBePositive} = 3
    end

    properties (SetAccess = private)
        TrialCount (:,1) double = zeros(0,1) % Presentations per condition row
        nHits        (1,1) double = 0        % Outcome tallies kept by onComplete
        nFalseAlarms (1,1) double = 0
    end

    properties (Access = private)
        goRows_    (:,1) double = zeros(0,1) % Condition rows with TrialType == 0
        catchRows_ (:,1) double = zeros(0,1) % Condition rows with TrialType == 1
        recentIsCatch_ (1,:) logical = false(1,0) % Sliding history for the run cap
    end

    methods
        function initialize(obj, TRIALS)
            % initialize(obj, TRIALS)
            % Index the compiled condition list by trial type. At this point
            % TRIALS carries parameters/trials/writeparams/writeParamIdx but
            % no DATA yet; writeParamIdx maps parameter validName -> column.
            assert(isfield(TRIALS.writeParamIdx, 'TrialType'), ...
                '%s requires a TrialType parameter in the protocol.', class(obj))
            col   = TRIALS.writeParamIdx.TrialType;
            types = cell2mat(TRIALS.trials(:, col));
            obj.goRows_    = find(types == 0);
            obj.catchRows_ = find(types == 1);
            assert(~isempty(obj.goRows_) && ~isempty(obj.catchRows_), ...
                '%s needs at least one go and one catch condition.', class(obj))
            obj.TrialCount     = zeros(size(TRIALS.trials, 1), 1);
            obj.recentIsCatch_ = false(1, 0);
        end

        function nextTrialID = selectNext(obj, ~)
            % nextTrialID = selectNext(obj, TRIALS)
            % Pick the next condition row. TRIALS is passed by value, so
            % state that must persist between trials lives on obj (or is
            % written back through obj.runtime_.TRIALS(obj.subjectIdx_)).
            wantCatch = rand < obj.CatchProbability;

            % Force a type switch after MaxConsecutive of the same type.
            h = obj.recentIsCatch_;
            if numel(h) >= obj.MaxConsecutive ...
                    && all(h(end-obj.MaxConsecutive+1:end) == h(end))
                wantCatch = ~h(end);
            end

            if wantCatch
                rows = obj.catchRows_;
            else
                rows = obj.goRows_;
            end

            counts = obj.TrialCount(rows);
            rows   = rows(counts == min(counts));
            nextTrialID = rows(randi(numel(rows)));

            obj.TrialCount(nextTrialID) = obj.TrialCount(nextTrialID) + 1;
            obj.recentIsCatch_(end+1) = wantCatch;
            if numel(obj.recentIsCatch_) > 100
                obj.recentIsCatch_(1) = [];
            end
        end

        function onRecompile(obj, TRIALS)
            % onRecompile(obj, TRIALS)
            % The operator recompiled mid-session: re-index the (possibly
            % different) condition list, keeping counts when the list size
            % is unchanged so balancing continues where it left off.
            counts = obj.TrialCount;
            obj.initialize(TRIALS);
            if numel(counts) == numel(obj.TrialCount)
                obj.TrialCount = counts;
            end
        end

        function onComplete(obj, trialID, data)
            % onComplete(obj, trialID, data)
            % Called once per completed trial with the DATA record just
            % collected. A selector can adapt here; this one just tallies.
            RC = epsych.BitMask.decode(data.RespCode);
            obj.nHits        = obj.nHits        + double(RC.Hit);
            obj.nFalseAlarms = obj.nFalseAlarms + double(RC.FalseAlarm);
            vprintf(3, '%s: trial %d complete (%d hits, %d false alarms so far)', ...
                class(obj), trialID, obj.nHits, obj.nFalseAlarms)
        end
    end
end
