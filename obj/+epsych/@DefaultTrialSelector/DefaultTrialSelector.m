classdef DefaultTrialSelector < epsych.TrialSelector
    % epsych.DefaultTrialSelector  Default balancing trial selector.
    %
    % Selects from the least-used trials, breaking ties randomly.
    % Functionally equivalent to the legacy DefaultTrialSelectFcn behavior.
    %
    % Usage:
    %   sel = epsych.DefaultTrialSelector();
    %   sel.initialize(TRIALS);
    %   id = sel.selectNext(TRIALS);
    %   sel.onComplete(id, data);
    %
    % See also: epsych.TrialSelector

    properties (SetAccess = private)
        TrialCount  (:,1) double  = zeros(0,1)  % Use count per trial row
        activeTrials (:,1) logical = false(0,1)  % Active trial mask
    end

    methods
        function initialize(obj, TRIALS)
            % initialize(obj, TRIALS)
            % Set up trial counts and active mask from the runtime TRIALS struct.
            %
            % Parameters:
            %   TRIALS - runtime TRIALS struct for this subject
            n = size(TRIALS.trials, 1);
            obj.TrialCount   = zeros(n, 1);
            obj.activeTrials = true(n, 1);
        end

        function nextTrialID = selectNext(obj, ~)
            % nextTrialID = selectNext(obj, TRIALS)
            % Select the least-used active trial, breaking ties at random.
            % Increments the internal use count for the selected trial.
            %
            % Parameters:
            %   TRIALS - (ignored) runtime TRIALS struct for this subject
            %
            % Returns:
            %   nextTrialID - row index into the trials matrix
            activeCounts = obj.TrialCount(obj.activeTrials);
            activeIdx    = find(obj.activeTrials);
            m   = min(activeCounts);
            idx = activeIdx(activeCounts == m);
            nextTrialID = idx(randi(length(idx), 1));
            obj.TrialCount(nextTrialID) = obj.TrialCount(nextTrialID) + 1;
        end

        function onRecompile(obj, TRIALS)
            % onRecompile(obj, TRIALS)
            % Reconcile trial counts with the updated TRIALS struct after recompile.
            % Resets counts and active mask when trial count changes.
            %
            % Parameters:
            %   TRIALS - runtime TRIALS struct for this subject after recompile
            oldN = numel(obj.TrialCount);
            newN = size(TRIALS.trials, 1);
            if newN == oldN
                return
            end
            obj.TrialCount   = zeros(newN, 1);
            obj.activeTrials = true(newN, 1);
            vprintf(2, 'DefaultTrialSelector: counts reset after recompile (was %d trials, now %d)', oldN, newN);
        end
    end
end
