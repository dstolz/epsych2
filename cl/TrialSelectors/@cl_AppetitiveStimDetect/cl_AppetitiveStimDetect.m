classdef cl_AppetitiveStimDetect < epsych.TrialSelector
    % Trial selector for the appetitive stimulus-detection task.
    %
    % Implements the staircase, catch-trial handling, and reminder-trial override
    % used when this selector is configured as Protocol.Options.trialFunc.
    %
    % Required parameters:
    %   ReminderTrials, StepOnHit, StepOnMiss, P_Catch, RepeatDelayOnAbort,
    %   StimDelay, and Depth (Depth.Min/Depth.Max provide the staircase bounds)
    %   in TRIALS.parameters.
    %
    % Optional parameters:
    %   StepDirectionOnHit, StepDirectionOnMiss - sign (-1 = Down, +1 = Up) of
    %       the Depth step applied on a Hit/Miss. Default: -1 on Hit, +1 on
    %       Miss. Omit to keep the default down-on-hit/up-on-miss behavior.
    %
    % See also: epsych.TrialSelector, cl_TrialSelection_Appetitive_StimDetect

    properties (Access = private)
        TT_STIM_  (1,1) double = 0    % TrialType code: signal-present trial
        TT_CATCH_ (1,1) double = 1    % TrialType code: catch (no-signal) trial
        TT_REMIND_(1,1) double = 2    % TrialType code: reminder trial


        P % struct of named parameter handles
        T % struct of named trial-column vectors
    end

    methods

        function initialize(obj, TRIALS)
            % initialize(obj, TRIALS)
            % Called once at run start before the first selectNext call.

            % Build numeric vectors from the trials table columns and a named
            % parameter map. TRIALS.parameters is the compiled writable-parameter
            % array; column k of TRIALS.trials corresponds to TRIALS.parameters(k).

            obj.P = struct();
            for k = 1:numel(TRIALS.parameters)
                obj.T.(TRIALS.parameters(k).validName) = [TRIALS.trials{:, k}];
                obj.P.(TRIALS.parameters(k).validName) = TRIALS.parameters(k);
            end
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


            % On the first trial return the first STIM row immediately
            if TRIALS.TrialIndex == 1
                
                
                nextTrialID = find(obj.T.TrialType == obj.TT_STIM_, 1);
                return
            end


            % Reminder override: force the REMIND row and set the HW flag
            if obj.P.ReminderTrials.Value == 1
                nextTrialID = find(obj.T.TrialType == obj.TT_REMIND_, 1);
                return
            end


            % Decode completed-trial response codes (see epsych.BitMask.list)
            RC = epsych.BitMask.decode([TRIALS.DATA.RespCode]);

            % Last STIM depth: use stored value; fall back to compiled max on first STIM
            lastStimTrialIdx = find(RC.("TrialType_" + obj.TT_STIM_), 1, 'last');
            stim = [TRIALS.DATA.Depth];
            if isempty(lastStimTrialIdx)
                lastStim = max(obj.T.Depth); % no prior STIM: start at max depth
            else
                lastStim = stim(lastStimTrialIdx);
            end


            % Staircase update based on the most recent trial outcome
            nextStim = lastStim; % default: no change (CR, FA, or fallback)
            stepped = false; % true only when Depth actually changes (Hit/Miss)

            % Repeat-delay logic: if enabled, repeat the same stimulus after an Abort by temporarily overriding nextStim
            rda = obj.P.RepeatDelayOnAbort.Value && RC.Abort(end);

            if RC.Hit(end)
                nextStim = lastStim + obj.P.Depth_StepOnHit.Value;
                stepped = true;

                if rda
                    obj.restore_stimdelay_randomization_(obj.P.StimDelay);
                end

            elseif RC.Miss(end)
                nextStim = lastStim + obj.P.Depth_StepOnMiss.Value;
                stepped = true;

                if rda
                    obj.restore_stimdelay_randomization_(obj.P.StimDelay);
                end

            elseif RC.Abort(end)
                tooManyAborts = length(RC.Abort) >= 3 && all(RC.Abort(end-2:end));

                if ~isfield(obj.P.StimDelay.UserData, 'CORRECTVAL')
                    obj.P.StimDelay.UserData.CORRECTVAL = [];
                end

                if rda && tooManyAborts
                    vprintf(2, 'Too many Aborts: resetting nextStim to max depth and clearing StimDelay randomization')
                    obj.restore_stimdelay_randomization_(obj.P.StimDelay);

                elseif rda
                    sdval = obj.P.StimDelay.Value;

                    if ~isfield(obj.P.StimDelay.UserData, 'CORRECTVAL') || isempty(obj.P.StimDelay.UserData.CORRECTVAL)
                        obj.P.StimDelay.UserData = obj.P.StimDelay.toStruct;

                        obj.P.StimDelay.isRandom = false;

                        obj.P.StimDelay.Value = sdval;
                        obj.P.StimDelay.UserData.CORRECTVAL = sdval;
                    end

                    vprintf(3, 'Repeating trial due to Abort: nextStim = %g, StimDelay = %g', nextStim, sdval)
                end

            elseif RC.CorrectReject(end)
                % no change; restore StimDelay randomization
                obj.restore_stimdelay_randomization_(obj.P.StimDelay);

            elseif RC.FalseAlarm(end)
                if RC.Abort(end) % treat FA+Abort as an Abort for catch-trial scheduling purposes
                    nextTrialID = find(obj.T.TrialType == obj.TT_CATCH_, 1);
                    return
                end

                % no change; restore StimDelay randomization
                obj.restore_stimdelay_randomization_(obj.P.StimDelay);
            end


            % Only Hit/Miss move the staircase. Leaving the table untouched on
            % Abort/CorrectReject/FalseAlarm means a pending Hit/Miss step
            % survives any number of intervening catch trials instead of
            % being reverted back to lastStim by the next non-stepping outcome.
            if stepped

                vprintf(4, 'nextStim = %g', nextStim)

                % Write updated depth into all STIM rows of the live trials table
                % so the runtime dispatch loop sends the correct value to hardware.
                ind = obj.T.TrialType == obj.TT_STIM_;
                depthCol = find(strcmp({TRIALS.parameters.validName}, 'Depth'), 1);
                [obj.runtime_.TRIALS(obj.subjectIdx_).trials{ind, depthCol}] = deal(nextStim);
            end

            % Catch-trial scheduling based on p(Catch)
            pCT = obj.P.P_Catch.Value;
            if RC.Abort(end), pCT = 0; end
            vprintf(4, 'p(Catch) = %g', pCT)

            if length(RC.("TrialType_" + obj.TT_STIM_)) >= 10
                nLast10Stim = sum(RC.("TrialType_" + obj.TT_STIM_)(end-9:end));
            else
                nLast10Stim = 0;
            end

            if pCT > 0 && ~RC.("TrialType_" + obj.TT_CATCH_)(end) && (rand() < pCT || nLast10Stim >= 10)
                nextTrialID = find(obj.T.TrialType == obj.TT_CATCH_, 1);
            else
                nextTrialID = find(obj.T.TrialType == obj.TT_STIM_, 1);
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

        function s = stepSign_(obj, paramName, defaultSign)
            % s = stepSign_(obj, paramName, defaultSign)
            % Resolve an optional step-direction parameter to -1 (Down) or +1 (Up).
            %
            % Parameters:
            %   paramName   - name of an optional StepDirectionOnHit/OnMiss parameter
            %   defaultSign - sign to use when the parameter is absent or zero
            %
            % Returns:
            %   s - -1 or +1
            %
            % obj.P only contains parameters the protocol defines, so isfield is the
            % sanctioned optional-parameter check: an absent parameter means the
            % protocol keeps the default step direction unchanged.
            if isfield(obj.P, paramName) && sign(obj.P.(paramName).Value) ~= 0
                s = sign(obj.P.(paramName).Value);
            else
                s = defaultSign;
            end
        end

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
