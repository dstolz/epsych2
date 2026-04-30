classdef cl_AppetitiveStimDetect < epsych.TrialSelector
    % cl_AppetitiveStimDetect  Trial selector for the appetitive stimulus-detection task.
    %
    % Implements a 1-up/1-down staircase on signal depth, with optional catch
    % trials and reminder-trial override.  Register this class as the trialFunc
    % in Protocol Options to replace the legacy cl_TrialSelection_Appetitive_StimDetect
    % function.
    %
    % Trial type codes (TrialType column in the trials table):
    %   0 – STIM   (signal-present trial)
    %   1 – CATCH  (no signal)
    %   2 – REMIND (reminder / training trial)
    %
    % Required TRIALS.Parameters fields (hw.Parameter handles):
    %   ReminderTrials, StepOnHit, StepOnMiss, MinDepth, MaxDepth,
    %   P_Catch, RepeatDelayOnAbort, StimDelay
    %
    % Usage:
    %   sel = cl_AppetitiveStimDetect();
    %   sel.initialize(TRIALS);
    %   sel.setRuntime(RUNTIME, subjectIdx);
    %   id  = sel.selectNext(TRIALS);
    %   sel.onComplete(id, data);
    %   sel.onRecompile(TRIALS);
    %
    % See also: epsych.TrialSelector, cl_TrialSelection_Appetitive_StimDetect

    properties (Access = private)
        TT_STIM_  (1,1) double = 0    % TrialType code: signal-present trial
        TT_CATCH_ (1,1) double = 1    % TrialType code: catch (no-signal) trial
        TT_REMIND_(1,1) double = 2    % TrialType code: reminder trial
    end

    methods

        function initialize(obj, TRIALS)
            % initialize(obj, TRIALS)
            % Called once at run start before the first selectNext call.

        end


        function nextTrialID = selectNext(obj, TRIALS)
            % nextTrialID = selectNext(obj, TRIALS)
            % Select the next trial row using the staircase and catch-trial logic.
            %
            % Parameters:
            %   TRIALS - runtime TRIALS struct for this subject
            %
            % Returns:
            %   nextTrialID - scalar row index into the trials table

            P = TRIALS.parameters;

            % Build numeric vectors from the trials table columns and a named
            % parameter map. TRIALS.parameters is the compiled writable-parameter
            % array; column k of TRIALS.trials corresponds to TRIALS.parameters(k).
            Pmap = struct();
            for k = 1:numel(P)
                T.(P(k).validName) = [TRIALS.trials{:, k}];
                Pmap.(P(k).validName) = P(k);
            end

            % On the first trial return the first STIM row immediately
            if TRIALS.TrialIndex == 1
                nextTrialID = find(T.TrialType == obj.TT_STIM_, 1);
                return
            end


            % Reminder override: force the REMIND row and set the HW flag
            if Pmap.ReminderTrials.Value == 1
                nextTrialID = find(T.TrialType == obj.TT_REMIND_, 1);
                return
            end


            % Decode completed-trial response codes (see epsych.BitMask.list)
            RC = epsych.BitMask.decode([TRIALS.DATA.RespCode]);

            % Last STIM depth: use stored value; fall back to compiled max on first STIM
            lastStimTrialIdx = find(RC.("TrialType_" + obj.TT_STIM_), 1, 'last');
            stim = [TRIALS.DATA.Depth];
            if isempty(lastStimTrialIdx)
                lastStim = max(T.Depth); % no prior STIM: start at max depth
            else
                lastStim = stim(lastStimTrialIdx);
            end


            % Staircase update based on the most recent trial outcome
            nextStim = lastStim; % default: no change (CR, FA, or fallback)

            % Repeat-delay logic: if enabled, repeat the same stimulus after an Abort by temporarily overriding nextStim
            rda = Pmap.RepeatDelayOnAbort.Value && RC.Abort(end);

            if RC.Hit(end)
                nextStim = lastStim - Pmap.StepOnHit.Value;

                if rda
                    obj.restore_stimdelay_randomization_(Pmap.StimDelay);
                end

            elseif RC.Miss(end)
                nextStim = lastStim + Pmap.StepOnMiss.Value;

                if rda
                    obj.restore_stimdelay_randomization_(Pmap.StimDelay);
                end

            elseif RC.Abort(end)
                tooManyAborts = length(RC.Abort) >= 3 && all(RC.Abort(end-2:end));

                if ~isfield(Pmap.StimDelay.UserData, 'CORRECTVAL')
                    Pmap.StimDelay.UserData.CORRECTVAL = [];
                end

                if rda && tooManyAborts
                    vprintf(2, 'Too many Aborts: resetting nextStim to max depth and clearing StimDelay randomization')
                    obj.restore_stimdelay_randomization_(Pmap.StimDelay);

                elseif rda
                    sdval = Pmap.StimDelay.Value;

                    if ~isfield(Pmap.StimDelay.UserData, 'CORRECTVAL') || isempty(Pmap.StimDelay.UserData.CORRECTVAL)
                        Pmap.StimDelay.UserData = Pmap.StimDelay.toStruct;

                        Pmap.StimDelay.isRandom = false;

                        Pmap.StimDelay.Value = sdval;
                        Pmap.StimDelay.UserData.CORRECTVAL = sdval;
                    end

                    vprintf(3, 'Repeating trial due to Abort: nextStim = %g, StimDelay = %g', nextStim, sdval)
                end
            end
            % CorrectReject or FalseAlarm: nextStim unchanged (= lastStim)

            % Clamp to configured staircase bounds
            nextStim = max(nextStim, Pmap.MinDepth.Value);
            nextStim = min(nextStim, Pmap.MaxDepth.Value);
            vprintf(4, 'nextStim = %g', nextStim)


            % Write updated depth into all STIM rows of the live trials table
            % so the runtime dispatch loop sends the correct value to hardware.
            ind = T.TrialType == obj.TT_STIM_;
            depthCol = find(strcmp({TRIALS.parameters.validName}, 'Depth'), 1);
            [obj.runtime_.TRIALS(obj.subjectIdx_).trials{ind, depthCol}] = deal(nextStim);

            % Catch-trial scheduling based on p(Catch)
            pCT = Pmap.P_Catch.Value;
            if RC.Abort(end), pCT = 0; end
            vprintf(4, 'p(Catch) = %g', pCT)

            if length(RC.("TrialType_" + obj.TT_STIM_)) >= 10
                nLast10Stim = sum(RC.("TrialType_" + obj.TT_STIM_)(end-9:end));
            else
                nLast10Stim = 0;
            end

            if pCT > 0 && ~RC.("TrialType_" + obj.TT_CATCH_)(end) && (rand() < pCT || nLast10Stim >= 10)
                nextTrialID = find(T.TrialType == obj.TT_CATCH_, 1);
            else
                nextTrialID = find(T.TrialType == obj.TT_STIM_, 1);
            end
        end

        function onRecompile(obj, TRIALS)
            % onRecompile(obj, TRIALS)
            % Called when an operator triggers a recompile during an active run.
            % Reconcile internal state with the updated TRIALS struct (e.g., resize trial counts).
            %
            % Parameters:
            %   TRIALS - runtime TRIALS struct for this subject after recompile
        end
    end

    methods (Access = private)

        function restore_stimdelay_randomization_(~, pStimDelay)
            % restore_stimdelay_randomization_(obj, pStimDelay)
            % Restore the isRandom flag on pStimDelay from its saved UserData
            % and clear the CORRECTVAL sentinel so normal randomization resumes.
            %
            % Parameters:
            %   pStimDelay - hw.Parameter handle for StimDelay
            if isfield(pStimDelay.UserData, 'isRandom') && ~isempty(pStimDelay.UserData.isRandom)
                pStimDelay.isRandom = pStimDelay.UserData.isRandom;
            end
            pStimDelay.UserData.CORRECTVAL = [];
        end

    end

end
