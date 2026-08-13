classdef cl_AppetitiveStimDetect < epsych.TrialSelector
    % Trial selector for the appetitive stimulus-detection task.
    %
    % Implements the staircase, catch-trial handling, and reminder-trial override
    % used when this selector is configured as Protocol.Options.trialFunc.
    %
    % Required parameters:
    %   ReminderTrials, Depth_StepOnHit, Depth_StepOnMiss, P_Catch,
    %   RepeatDelayOnAbort, StimDelay, and Depth (Depth.Min/Depth.Max provide
    %   the staircase bounds) in TRIALS.parameters.
    %
    % Catch trials are scheduled by a hazard function rather than a flat
    % probability, so all three fields of P_Catch carry meaning:
    %   P_Catch.Min   - floor: the probability at the start of a session and
    %                   immediately after a catch trial
    %   P_Catch.Value - step added for every delivered stimulus trial
    %   P_Catch.Max   - ceiling the probability is clamped to
    % See advanceHazard and documentation/cl/cl_AppetitiveStimDetect.md.
    %
    % The Reminder button (ReminderTrials) brings the next trial forward and
    % presents it at 0 dB depth -- full modulation, the most salient stimulus
    % the task produces -- on the reminder row, so the trial re-engages the
    % subject without entering the staircase or the catch schedule. See
    % forceReminderTrial_. The request is a one-shot, consumed by the
    % selection pass that grants it -- see consumeReminderRequest_ for why it
    % cannot be cleared on trial completion instead.
    %
    % Catch trials can be switched off for a session through the
    % CatchTrialsEnabled parameter, which cl_AppetitiveDetection_BoxGUI
    % exposes as a checkbox. The selector creates it when the protocol does
    % not declare it, and an absent parameter means enabled.
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

        % Depth a reminder trial is presented at, in dB re 100% modulation.
        % 0 dB is full depth, the most salient stimulus the task can produce,
        % which is the point of a reminder: re-engage the subject with a
        % trial it cannot miss, wherever the staircase currently sits.
        REMINDER_DEPTH_ (1,1) double = 0


        P % struct of named parameter handles
        T % struct of named trial-column vectors

        pCatchCurrent_ = [] % hw.Parameter mirroring pCatch_ for the GUI and DATA
        catchEnabled_  = [] % hw.Parameter gating catch-trial presentation

        pCatch_ (1,1) double = 0 % accumulated catch-trial probability

        % Number of completed non-reminder trials the hazard has already
        % advanced on. Keyed on that count rather than on TrialIndex so the
        % hazard advances exactly once per real trial and a reminder -- which
        % adds a TrialIndex but no outcome -- cannot advance it at all.
        lastHazardOutcome_ (1,1) double = 0

        % TrialIndex whose selection has already been committed to a
        % reminder. Holds the choice across a repeated selectNext at the same
        % index once the request itself has been consumed; see
        % forceReminderTrial_.
        reminderIndex_ (1,1) double = NaN
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

            % The catch-trial hazard starts at its floor. It accumulates from
            % here rather than being recomputed from history, so a mid-session
            % change to the step size only affects subsequent trials.
            obj.pCatch_ = obj.P.P_Catch.Min;
            obj.lastHazardOutcome_ = 0;
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


            % Selector-owned runtime parameters: the live catch probability,
            % for the Trial State monitor and the saved DATA record, and the
            % operator's catch-trials on/off switch. Both are resolved (or
            % created) here rather than in initialize because ep_TimerFcn_Start
            % makes this call before epsych.RunExpt launches the box GUI, so
            % the GUI's parameter snapshot already contains them.
            if isempty(obj.pCatchCurrent_)
                obj.pCatchCurrent_ = obj.ensureSelectorParameter_('P_Catch_Current', obj.pCatch_, ...
                    Format='%0.2f', ...
                    Description="Current catch-trial probability (hazard function)");
            end

            if isempty(obj.catchEnabled_)
                obj.catchEnabled_ = obj.ensureSelectorParameter_('CatchTrialsEnabled', true, ...
                    Type='Boolean', ...
                    Description="Present catch trials");
            end


            % On the first trial return the first STIM row immediately
            if TRIALS.TrialIndex == 1


                nextTrialID = find(obj.T.TrialType == obj.TT_STIM_, 1);
                return
            end


            % Is a reminder pending? Read now but acted on at the very end:
            % the reminder changes which row is presented and nothing else,
            % so the schedule below advances exactly as it would have without
            % it. The second test re-honors a request already consumed at
            % this TrialIndex, so a repeated selectNext for the same trial
            % still yields the reminder.
            reminderRequested = obj.P.ReminderTrials.Value == 1 ...
                || TRIALS.TrialIndex == obj.reminderIndex_;


            % Decode completed-trial response codes (see epsych.BitMask.list)
            RC = epsych.BitMask.decode([TRIALS.DATA.RespCode]);
            stim = [TRIALS.DATA.Depth];

            % Drop reminder trials from the history the schedule reads. A
            % reminder is an operator interruption, not a measurement: its
            % outcome is not a datum about the subject's threshold, and the
            % trial it displaced still has to be accounted for. Removing it
            % here is what makes the session continue as though the reminder
            % had never been presented -- the staircase steps on the outcome
            % of the last real trial, once, whether or not a reminder came
            % between them.
            isReminder = RC.("TrialType_" + obj.TT_REMIND_);
            stim = stim(~isReminder);
            RC = structfun(@(v) v(~isReminder), RC, UniformOutput=false);

            % Nothing but reminders completed so far -- there is no outcome to
            % schedule from, so present the reminder or start the staircase.
            nOutcomes = nnz(~isReminder);
            if nOutcomes == 0
                nextTrialID = find(obj.T.TrialType == obj.TT_STIM_, 1);
                if reminderRequested, nextTrialID = obj.forceReminderTrial_(TRIALS); end
                return
            end

            % Last STIM depth: use stored value; fall back to compiled max on first STIM
            lastStimTrialIdx = find(RC.("TrialType_" + obj.TT_STIM_), 1, 'last');
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

            % Catch-trial scheduling: hazard function over p(Catch)
            pC = obj.P.P_Catch;

            % Operator switch (the GUI's "Present Catch Trials" checkbox).
            % While it is off the hazard is held at its floor rather than left
            % to accumulate, so re-enabling resumes from the bottom of the
            % schedule instead of firing a catch trial on the next draw. An
            % absent parameter means enabled, which is what a protocol without
            % the switch -- and epsych.SelfTest, which has no runtime to host
            % it -- gets.
            if ~isempty(obj.catchEnabled_) && ~obj.catchEnabled_.Value
                obj.pCatch_ = pC.Min;
                obj.lastHazardOutcome_ = nOutcomes;
                if ~isempty(obj.pCatchCurrent_), obj.pCatchCurrent_.Value = obj.pCatch_; end

                vprintf(4, 'Catch trials disabled')
                nextTrialID = find(obj.T.TrialType == obj.TT_STIM_, 1);

            else
                % Advance at most once per completed trial. nOutcomes counts
                % non-reminder trials, so a repeated selectNext for the same
                % trial is a no-op and an intervening reminder neither
                % advances the hazard nor lets the trial before it advance the
                % hazard twice.
                if obj.lastHazardOutcome_ ~= nOutcomes
                    obj.lastHazardOutcome_ = nOutcomes;
                    obj.pCatch_ = cl_AppetitiveStimDetect.advanceHazard(obj.pCatch_, ...
                        RC, obj.TT_STIM_, obj.TT_CATCH_, pC.Min, pC.Value, pC.Max);
                end

                % Re-clamp every trial so an operator edit to the Min/Max bounds
                % takes effect immediately rather than at the next step.
                obj.pCatch_ = min(max(obj.pCatch_, pC.Min), pC.Max);

                pCT = obj.pCatch_;
                if ~isempty(obj.pCatchCurrent_), obj.pCatchCurrent_.Value = pCT; end

                % An abort suppresses this draw without disturbing the hazard:
                % advanceHazard already left the accumulator alone, so p is
                % unchanged the next time around.
                if RC.Abort(end), pCT = 0; end
                vprintf(4, 'p(Catch) = %g', pCT)

                if pCT > 0 && ~RC.("TrialType_" + obj.TT_CATCH_)(end) && rand() < pCT
                    nextTrialID = find(obj.T.TrialType == obj.TT_CATCH_, 1);
                else
                    nextTrialID = find(obj.T.TrialType == obj.TT_STIM_, 1);
                end
            end

            % Reminder override, applied last so it takes the scheduled
            % trial's slot without altering the schedule: the staircase step,
            % the hazard, and the draw above have all already run exactly as
            % they would have if the button had never been pressed.
            if reminderRequested
                nextTrialID = obj.forceReminderTrial_(TRIALS);
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

    methods (Static)

        function p = advanceHazard(p, RC, ttStim, ttCatch, pMin, pStep, pMax)
            % p = advanceHazard(p, RC, ttStim, ttCatch, pMin, pStep, pMax)
            % Advance the catch-trial hazard by the one trial that just
            % completed: a delivered stimulus trial adds pStep, a completed
            % catch trial resets to pMin, and the result is clamped to
            % [pMin pMax].
            %
            % The probability is carried in p rather than recomputed from the
            % history, so changing pStep mid-session steps on from wherever
            % the hazard currently sits instead of rescaling it.
            %
            % Aborts are inert on both sides of the schedule. An aborted
            % stimulus trial never delivered a stimulus, so it does not
            % advance p; an aborted catch trial never measured a false-alarm
            % rate, so it does not reset p. A run of aborts therefore leaves
            % the catch rate exactly where it was. Reminder trials never
            % reach here at all -- selectNext drops them from the history
            % before reading it.
            %
            % Parameters:
            %   p       - probability before the completed trial
            %   RC      - struct from epsych.BitMask.decode over the completed
            %             trials; only the last element is read
            %   ttStim  - TrialType code for stimulus trials
            %   ttCatch - TrialType code for catch trials
            %   pMin    - floor probability (P_Catch.Min)
            %   pStep   - step per delivered stimulus trial (P_Catch.Value)
            %   pMax    - ceiling probability (P_Catch.Max)
            %
            % Returns:
            %   p - probability after the completed trial
            %
            % Kept static and free of runtime state so the schedule can be
            % exercised headlessly; see tmp/smoke_test_pcatch_hazard.m.
            if ~RC.Abort(end)
                if RC.("TrialType_" + ttCatch)(end)
                    p = pMin;
                elseif RC.("TrialType_" + ttStim)(end)
                    p = p + pStep;
                end
            end

            p = min(max(p, pMin), pMax);
        end

    end

    methods (Access = private)

        function consumeReminderRequest_(obj, TRIALS)
            % consumeReminderRequest_(obj, TRIALS)
            % Clear the operator's Reminder toggle now that the request has
            % been granted, and record the TrialIndex it was granted for.
            %
            % The request has to be consumed here rather than when the
            % reminder trial later completes. The runtime broadcasts NewData
            % for the completed trial BEFORE it calls selectNext for the next
            % one, so anything that clears the toggle on trial completion --
            % as the box GUI's onNewData used to -- withdraws the request in
            % the same pass that is about to honor it, and the Reminder
            % button does nothing but force the trial in progress to end.
            % Consuming it at the point of selection also leaves a press made
            % DURING a reminder trial standing, so holding the button down
            % over successive trials keeps producing reminders.
            %
            % reminderIndex_ keeps the choice stable if selectNext is called
            % again for the same trial, which the toggle can no longer do.
            %
            % Parameters:
            %   TRIALS - runtime TRIALS struct for this subject
            obj.reminderIndex_ = TRIALS.TrialIndex;

            if obj.P.ReminderTrials.Value ~= 1, return; end

            obj.P.ReminderTrials.Value = 0;
            vprintf(3,'Reminder request granted for trial #%d; ReminderTrials cleared', ...
                TRIALS.TrialIndex)
        end

        function nextTrialID = forceReminderTrial_(obj, TRIALS)
            % nextTrialID = forceReminderTrial_(obj, TRIALS)
            % Row for an operator-requested reminder trial: a signal-present
            % trial presented at REMINDER_DEPTH_ (0 dB, full modulation
            % depth).
            %
            % The reminder row's Depth is overwritten in the live trials
            % table rather than read from it, so the reminder is at full
            % depth no matter what the protocol compiled into that row, and
            % the stimulus rows the staircase owns are left alone.
            %
            % TrialType stays REMIND: the reminder's own depth is then
            % excluded from the staircase (which reads depths from stimulus
            % trials only) and from the catch-trial hazard, and the trial is
            % labeled as a reminder in the Next Trial panel and the Response
            % History. Its OUTCOME still steps the staircase, as any
            % completed trial does.
            %
            % The request is consumed here, at the moment the reminder is
            % committed to; see consumeReminderRequest_.
            %
            % Parameters:
            %   TRIALS - runtime TRIALS struct for this subject
            %
            % Returns:
            %   nextTrialID - scalar row index into the trials table
            nextTrialID = find(obj.T.TrialType == obj.TT_REMIND_, 1);

            if isempty(nextTrialID)
                % Borrowing a stimulus row would overwrite the depth the
                % staircase is holding there, so a protocol that compiled no
                % reminder row gets an ordinary stimulus trial instead.
                vprintf(0,1,['No reminder row (TrialType %d) in the compiled trials table; ' ...
                    'presenting an ordinary stimulus trial'], obj.TT_REMIND_)
                nextTrialID = find(obj.T.TrialType == obj.TT_STIM_, 1);
                obj.consumeReminderRequest_(TRIALS);
                return
            end

            obj.consumeReminderRequest_(TRIALS);

            if isempty(obj.runtime_), return; end

            depthCol = find(strcmp({TRIALS.parameters.validName}, 'Depth'), 1);
            if isempty(depthCol), return; end

            % Depth is clamped to its own bounds on dispatch, so a working
            % maximum below full depth would quietly weaken the reminder.
            if obj.P.Depth.Max < obj.REMINDER_DEPTH_
                vprintf(0,1,['Reminder depth %g dB is above Maximum Depth (%g dB) ' ...
                    'and will be clamped when dispatched'], obj.REMINDER_DEPTH_, obj.P.Depth.Max)
            end

            vprintf(3,'Reminder trial: Depth = %g dB', obj.REMINDER_DEPTH_)
            obj.runtime_.TRIALS(obj.subjectIdx_).trials{nextTrialID, depthCol} = obj.REMINDER_DEPTH_;
        end

        function p = ensureSelectorParameter_(obj, name, value, options)
            % p = ensureSelectorParameter_(obj, name, value, Type=..., Format=..., Description=...)
            % Resolve a selector-owned runtime parameter by name, creating it
            % on the hw.Software interface when the protocol does not declare
            % one.
            %
            % Declaring these in the protocol is preferable -- they then
            % persist and serialize -- but either way the selector reads and
            % writes them outside the compiled trials table, so they must stay
            % host-writable ('Read' access rejects every write) and carry
            % UpdateEveryTrial = false, which is what keeps dispatchNextTrial
            % from clobbering them with a stale trials-table value should the
            % operator recompile mid-run.
            %
            % Parameters:
            %   name  - parameter name
            %   value - initial value, used only when the parameter is created
            %
            % Returns:
            %   p - hw.Parameter handle, or [] when there is no runtime (as
            %       under epsych.SelfTest) or no software interface to host it.
            %       Callers must treat [] as "the parameter is absent".
            arguments
                obj
                name (1,:) char
                value
                options.Type (1,:) char = 'Float'
                options.Format (1,:) char = '%g'
                options.Description (1,1) string = ""
            end

            p = [];
            if isempty(obj.runtime_), return; end

            p = obj.runtime_.find_parameter(name, silenceParameterNotFound=true);
            if ~isempty(p), return; end

            sw = obj.runtime_.Interfaces(arrayfun(@(x) isa(x,'hw.Software'), ...
                obj.runtime_.Interfaces));
            if isempty(sw), return; end

            p = sw(1).add_parameter(name, value, ...
                Type=options.Type, Format=options.Format, Description=options.Description);

            p.UpdateEveryTrial = false;

            % add_parameter seeds Values, not Value; the first write is a
            % trial away, so seat the initial value now.
            p.Value = value;
        end

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
