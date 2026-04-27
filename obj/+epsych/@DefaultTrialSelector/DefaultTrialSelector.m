classdef DefaultTrialSelector < epsych.TrialSelector
    % epsych.DefaultTrialSelector  Default balancing trial selector.
    %
    % Selects from the least-used trials, breaking ties randomly.
    % Functionally equivalent to the legacy DefaultTrialSelectFcn behavior.
    %
    % Usage:
    %   sel = epsych.DefaultTrialSelector();
    %   sel.initialize(snapshot);
    %   id = sel.selectNext(trialIndex);
    %   sel.onComplete(id, data);
    %
    % See also: epsych.TrialSelector, epsych.Protocol.runtimeSnapshot

    properties (SetAccess = private)
        TrialCount  (:,1) double  = zeros(0,1)  % Use count per trial row
        activeTrials (:,1) logical = false(0,1)  % Active trial mask
    end

    methods
        function initialize(obj, snapshot)
            % initialize(obj, snapshot)
            % Set up trial counts and active mask from Protocol snapshot.
            %
            % Parameters:
            %   snapshot - struct from Protocol.runtimeSnapshot()
            obj.TrialCount   = zeros(snapshot.ntrials, 1);
            obj.activeTrials = true(snapshot.ntrials, 1);
        end

        function nextTrialID = selectNext(obj, ~)
            % nextTrialID = selectNext(obj, trialIndex)
            % Select the least-used active trial, breaking ties at random.
            % Increments the internal use count for the selected trial.
            %
            % Parameters:
            %   trialIndex - (ignored) current sequential trial number
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

        function onRecompile(obj, snapshot)
            % onRecompile(obj, snapshot)
            % Reconcile trial counts with the new snapshot after recompile.
            % Resets counts and active mask when trial count changes.
            %
            % Parameters:
            %   snapshot - struct from Protocol.runtimeSnapshot() after recompile
            oldN = numel(obj.TrialCount);
            newN = snapshot.ntrials;
            if newN == oldN
                return
            end
            obj.TrialCount   = zeros(newN, 1);
            obj.activeTrials = true(newN, 1);
            vprintf(2, 'DefaultTrialSelector: counts reset after recompile (was %d trials, now %d)', oldN, newN);
        end
    end
end
