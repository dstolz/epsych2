classdef TrialSelector < handle
    % epsych.TrialSelector  Abstract base class for pluggable trial selection.
    %
    % Subclass this class and implement all abstract methods to create a
    % custom trial selection strategy. Instantiate via
    % epsych.TrialSelector.create(selectorConfig).
    %
    % Required abstract methods (must be implemented by subclasses):
    %   initialize(obj, snapshot)      - Set up internal state from Protocol snapshot.
    %   nextTrialID = selectNext(obj, trialIndex) - Select and return the next trial row.
    %   onRecompile(obj, snapshot)     - Reconcile state after operator-triggered recompile.
    %
    % Optional concrete methods (override to add adaptive behavior):
    %   onComplete(obj, trialID, data) - Called after each trial completes.
    %
    % Example:
    %   sel = epsych.TrialSelector.create(snap.selectorConfig);
    %   sel.initialize(snap);
    %   id = sel.selectNext(1);
    %   sel.onComplete(id, responseData);
    %
    % See also: epsych.DefaultTrialSelector, epsych.Protocol.runtimeSnapshot

    methods (Abstract)
        initialize(obj, snapshot)
        % initialize(obj, snapshot)
        % Called once at run start with the Protocol runtime snapshot.
        % Sets up internal state (trial counts, active trial mask, etc.).
        %
        % Parameters:
        %   snapshot - struct from Protocol.runtimeSnapshot()

        nextTrialID = selectNext(obj, TRIALS)
        % nextTrialID = selectNext(obj, TRIALS)
        % Select the next trial row index and update internal selection state.
        %
        % Parameters:
        %   TRIALS - struct, the current runtime TRIALS entry for this subject.
        %            Contains: trials, writeparams, writeParamIdx, readparams,
        %            TrialIndex, NextTrialID, DATA, HW, S, selector, etc.
        %
        % Returns:
        %   nextTrialID - scalar row index into the trials matrix

        onRecompile(obj, snapshot)
        % onRecompile(obj, snapshot)
        % Called when an operator triggers a recompile during an active run.
        % Reconcile internal state with the new snapshot (e.g., resize trial counts).
        %
        % Parameters:
        %   snapshot - struct from Protocol.runtimeSnapshot() after recompile
    end

    methods
        function onComplete(~, ~, ~)
            % onComplete(obj, trialID, data)
            % Called after each trial completes with the trial's response data.
            % Default implementation is a no-op. Override for adaptive selection.
            %
            % Parameters:
            %   trialID - scalar row index of the completed trial
            %   data    - struct of response parameter values from runtime
        end
    end

    methods (Static)
        function sel = create(selectorConfig)
            % sel = create(selectorConfig)
            % Instantiate a selector from selectorConfig.trialFunc.
            % Falls back to epsych.DefaultTrialSelector when trialFunc is empty.
            %
            % Parameters:
            %   selectorConfig - struct with field trialFunc (char or empty)
            %
            % Returns:
            %   sel - epsych.TrialSelector subclass instance
            tf = selectorConfig.trialFunc;

            if isempty(tf) || (ischar(tf) && strcmp(strtrim(tf), '')) ...
                    || (ischar(tf) && strcmp(tf, '< default >'))
                sel = epsych.DefaultTrialSelector();
                return
            end

            if ischar(tf) || isstring(tf)
                className = char(string(tf));
                if exist(className, 'class') == 8
                    sel = feval(className);
                    assert(isa(sel, 'epsych.TrialSelector'), ...
                        'epsych:TrialSelector:InvalidClass', ...
                        'Trial selector class "%s" must be a subclass of epsych.TrialSelector.', className);
                    return
                end
            end

            error('epsych:TrialSelector:UnresolvableSelector', ...
                'Cannot resolve trial selector "%s". Provide the name of an epsych.TrialSelector subclass.', ...
                char(string(tf)));
        end
    end
end
