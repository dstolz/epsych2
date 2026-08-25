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
    % See advanceHazard and documentation/paradigms/cl_AppetitiveStimDetect.md.
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
    % CatchTrialsEnabled parameter, which cl_AppetitiveDetection_BehaviorGUI
    % exposes as a checkbox. The selector creates it when the protocol does
    % not declare it, and an absent parameter means enabled. It is marked
    % PersistWithPhase, so the setting is saved into and restored from a phase
    % file like the rest of the stage's configuration.
    %
    % The stimulus delay is block-randomized when the protocol declares
    % StimDelayList. Its Min and Max are the ends of the delay list and
    % StimDelayStep.Value is the spacing, so 1000 / 4000 / 250 means
    % 1000:250:4000 ms; StimDelayJitter.Value adds +/-j ms to each delivered
    % value. Those feed an epsych.BlockSequence indexed by the selector, so
    % every delay appears exactly its share within each block instead of
    % merely on average -- which is what StimDelay.isRandom's randi([Min Max])
    % could not do. isRandom is consequently held FALSE for the whole session:
    % it redraws inside set.Value on dispatch and would throw the balanced
    % value away. cl_AppetitiveDetection_BehaviorGUI exposes the switch as the
    % "Randomize Stimulus Delay" checkbox over StimDelayBlockEnabled, which
    % the selector creates when the protocol does not declare it.
    %
    % The step needs a parameter of its own rather than living on
    % StimDelayList.Value, because hw.Parameter clamps Value into [Min Max]
    % -- a 250 ms step in a 1000-4000 ms list would silently become 1000. The
    % selector creates StimDelayStep, seeded from StimDelayList's own value,
    % so a protocol that only defines the list still works. See
    % ensureStimDelayStep and stimDelayValues.
    %
    % A protocol WITHOUT StimDelayList gets none of that: StimDelay is left
    % entirely to isRandom and the abort/CORRECTVAL machinery below, exactly
    % as before. See setupStimDelay_ and applyStimDelay_.
    %
    % The staircase step is a plain signed add: nextStim = lastStim +
    % Depth_StepOnHit (or OnMiss). The step carries its own sign, so a
    % negative Depth_StepOnHit is what steps down to a weaker stimulus.
    % Invert the staircase by negating the step value.
    %
    % Optional parameters:
    %   StimDelayList - Min and Max are the ends of the block-randomized delay
    %       list, as above. Absent means no block randomization.
    %   StimDelayStep - spacing between list values, in ms. Created by the
    %       selector when absent.
    %   StimDelayJitter - +/- jitter in ms applied to each delivered delay.
    %
    % See also: epsych.TrialSelector, epsych.BlockSequence,
    % cl_TrialSelection_Appetitive_StimDetect

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

        % --- Block-randomized stimulus delay ---------------------------
        % Engaged only when the protocol declares StimDelayList. Without it
        % every field here stays empty, stimDelayBlockActive_ is false, and
        % the isRandom/CORRECTVAL path in selectNext behaves exactly as it
        % always has. See setupStimDelay_.
        stimDelaySetup_ (1,1) logical = false % lazy setup has run
        stimDelaySeq_       = []  % epsych.BlockSequence over the delay list
        stimDelayList_      = []  % hw.Parameter: Min and Max are the list ends
        stimDelayStep_      = []  % hw.Parameter: spacing between list values
        stimDelayJitter_    = []  % hw.Parameter: +/- jitter in ms
        stimDelayEnabled_   = []  % hw.Parameter: the operator's Randomize checkbox
        stimDelayTraining_  = []  % hw.Parameter: StimDelayTrainingEnabled, when the GUI made it
        stimDelayCol_ (1,1) double = 0  % StimDelay's column in the trials table
        stimDelaySpec_ (1,:) double = []  % [values jitter limits], to detect an operator edit

        % Index into the sequence. The caller owns it (see
        % epsych.BlockSequence), which is what lets a repeat-on-abort hold
        % the same delay simply by not advancing.
        stimDelayIdx_ (1,1) double = 0
        repeatStimDelay_ (1,1) logical = false % hold the delay for the next trial
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
            % Select the next trial row, then set the stimulus delay for it.
            %
            % Split in two so the stimulus delay is applied on every path out
            % of the selection logic -- the first trial, the reminder
            % override, and the ordinary staircase/catch schedule all leave
            % through here -- rather than being repeated at each of
            % selectNextRow_'s several early returns.
            %
            % Parameters:
            %   TRIALS - runtime TRIALS struct for this subject
            %
            % Returns:
            %   nextTrialID - scalar row index into the trials table
            if ~obj.stimDelaySetup_, obj.setupStimDelay_(TRIALS); end
            nextTrialID = obj.selectNextRow_(TRIALS);
            obj.applyStimDelay_(TRIALS, nextTrialID);
        end

        function onRecompile(obj, TRIALS)
            % onRecompile(obj, TRIALS)
            % Called when an operator triggers a recompile during an active run.
            % Reconcile internal state with the updated TRIALS struct.
            %
            % A recompile that adds or removes a parameter shifts every column
            % after it, so the cached StimDelay column has to be re-read.
            %
            % Parameters:
            %   TRIALS - runtime TRIALS struct for this subject after recompile
            obj.stimDelayCol_ = obj.stimDelayColumn_(TRIALS);
        end
    end

    methods (Access = private)

        function nextTrialID = selectNextRow_(obj, TRIALS)
            % nextTrialID = selectNextRow_(obj, TRIALS)
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
            % makes this call before epsych.RunExpt launches the behavior GUI, so
            % the GUI's parameter snapshot already contains them.
            if isempty(obj.pCatchCurrent_)
                obj.pCatchCurrent_ = obj.ensureSelectorParameter_('P_Catch_Current', obj.pCatch_, ...
                    Format='%0.2f', ...
                    Description="Current catch-trial probability (hazard function)");
            end

            if isempty(obj.catchEnabled_)
                % PersistWithPhase: the operator sets this once for a
                % subject's stage and leaves it set, so it is a phase setting,
                % not a button press. Without it the Boolean/UpdateEveryTrial
                % heuristic in hw.Parameter.isTransientControl reads it as a
                % momentary control and a phase neither saves nor restores it.
                obj.catchEnabled_ = obj.ensureSelectorParameter_('CatchTrialsEnabled', true, ...
                    Type='Boolean', ...
                    Description="Present catch trials", ...
                    PersistWithPhase=true);
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

            % Cleared here and set only by the abort branch below, so an
            % outcome that does not ask for a repeat always advances the
            % block sequence. Under the block sequence "repeat the delay"
            % means "do not advance the index" -- there is no randomization
            % to suspend and no value to stash.
            obj.repeatStimDelay_ = false;

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

                elseif rda && obj.stimDelayBlockActive_()
                    % Holding the sequence index is the whole repeat: the
                    % delay for this trial is looked up at the same index and
                    % is therefore the identical value, jitter included.
                    obj.repeatStimDelay_ = true;
                    vprintf(3, 'Repeating trial due to Abort: nextStim = %g, holding stimulus delay index %d', ...
                        nextStim, obj.stimDelayIdx_)

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


        function v = stimDelayValues(pList, pStep)
            % v = cl_AppetitiveStimDetect.stimDelayValues(pList)
            % v = cl_AppetitiveStimDetect.stimDelayValues(pList, pStep)
            % The stimulus-delay pool the list parameters describe.
            %
            % StimDelayList.Min and .Max are the ends of the list and
            % StimDelayStep.Value is the spacing, so 1000 / 4000 / 250 means
            % 1000:250:4000. Colon semantics throughout -- a span that is not
            % a whole number of steps stops short of Max rather than adding a
            % short final step, which would put an unevenly spaced value into
            % a list whose whole point is even spacing.
            %
            % The step needs a parameter of its own because hw.Parameter
            % clamps Value into [Min Max] (and gui.components.Parameter_Control limits
            % the edit field to the same range), so a 250 ms step could not be
            % stored on -- or typed into -- a parameter whose Min is 1000.
            % StimDelayList.Value survives only as the seed StimDelayStep is
            % created with; see ensureStimDelayStep.
            %
            % A non-positive step, or Min == Max, is a single fixed delay
            % rather than an error: it is what an operator narrowing the list
            % passes through on the way down.
            %
            % Kept static and free of runtime state so the list can be
            % exercised headlessly, and so the GUI can compute it too.
            %
            % Parameters:
            %   pList - hw.Parameter for StimDelayList, or empty
            %   pStep - hw.Parameter for StimDelayStep; omit or pass empty to
            %           fall back to StimDelayList's own value
            %
            % Returns:
            %   v - row vector of delays in ms; empty when unusable
            arguments
                pList = []
                pStep = []
            end

            v = [];
            if isempty(pList), return; end

            lo   = pList.Min;
            hi   = pList.Max;
            step = cl_AppetitiveStimDetect.parameterLevel(pStep);
            if isempty(step)
                step = cl_AppetitiveStimDetect.parameterLevel(pList);
            end

            if isempty(step) || ~isfinite(lo) || ~isfinite(hi) || hi < lo, return; end
            if step <= 0 || hi == lo
                v = lo;
                return
            end
            v = lo:step:hi;
        end

        function p = ensureStimDelayStep(RUNTIME, pList)
            % p = cl_AppetitiveStimDetect.ensureStimDelayStep(RUNTIME, pList)
            % Resolve the stimulus-delay list step, creating it on the
            % session's hw.Software interface when the protocol has none.
            %
            % Shared by the selector and by the behavior GUI's build, so a
            % session started either way gets the same parameter with the same
            % default -- StimDelayList's own value, which is what an operator
            % who tried to put the step there will have set.
            %
            % Min = 0 and Max = Inf deliberately: these ARE bounds on the
            % step, unlike StimDelayList's, whose Min and Max are the ends of
            % the list rather than limits on anything it holds.
            %
            % Parameters:
            %   RUNTIME - epsych.Runtime, or empty
            %   pList   - hw.Parameter for StimDelayList, used for the default
            %
            % Returns:
            %   p - hw.Parameter handle, or [] when there is no runtime or no
            %       software interface to host it
            p = [];
            if isempty(RUNTIME) || isempty(RUNTIME.Interfaces), return; end

            p = RUNTIME.find_parameter('StimDelayStep', silenceParameterNotFound=true);
            if ~isempty(p)
                p = p(1);
            else
                sw = RUNTIME.Interfaces(arrayfun(@(x) isa(x,'hw.Software'), RUNTIME.Interfaces));
                if isempty(sw), return; end

                seed = cl_AppetitiveStimDetect.parameterLevel(pList);
                if isempty(seed) || seed <= 0
                    seed = max(1, pList.Max - pList.Min);   % two values: the ends
                end
                p = sw(1).add_parameter('StimDelayStep', seed, Type='Float', ...
                    Description="Spacing between stimulus-delay list values (ms)");
                p.Min = 0;
                p.Max = Inf;
                p.Value = seed;   % add_parameter seeds Values, not Value
            end

            % Asserted whether the parameter was found or created: the
            % operator owns this value for the session, so the dispatcher must
            % not re-apply a stale trial-table copy over an edit, and a phase
            % has to carry it.
            p.UpdateEveryTrial = false;
            p.PersistWithPhase = true;
            if isempty(p.Value) && ~isempty(p.Values)
                p.Value = p.Values{1};
            end
        end

        function j = stimDelayJitter(pJitter)
            % j = cl_AppetitiveStimDetect.stimDelayJitter(pJitter)
            % The +/- jitter a StimDelayJitter parameter asks for, in ms.
            %
            % A scalar, so epsych.BlockSequence reads it as symmetric
            % +/-j around each list value. Absent or unset means no jitter.
            %
            % Parameters:
            %   pJitter - hw.Parameter for StimDelayJitter, or empty
            %
            % Returns:
            %   j - non-negative scalar
            j = 0;
            if isempty(pJitter), return; end
            v = cl_AppetitiveStimDetect.parameterLevel(pJitter);
            if isempty(v) || ~isfinite(v), return; end
            j = abs(v);
        end

        function v = parameterLevel(p)
            % v = cl_AppetitiveStimDetect.parameterLevel(p)
            % A parameter's current value, falling back to its design-time level.
            %
            % add_parameter seeds Values, not Value, and the dispatcher has
            % not run when the selector first reads these -- selectNext is
            % called before the first dispatch. The compiled level is what the
            % dispatcher would have written anyway.
            %
            % Parameters:
            %   p - hw.Parameter handle, or empty
            %
            % Returns:
            %   v - scalar value, or empty
            v = [];
            if isempty(p), return; end
            v = p.Value;
            if isempty(v) && ~isempty(p.Values)
                v = p.Values{1};
            end
            if ~isempty(v), v = v(1); end
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
            % as the behavior GUI's onNewData used to -- withdraws the request in
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
            % p = ensureSelectorParameter_(obj, name, value, Type=..., Format=..., Description=..., PersistWithPhase=...)
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
            % PersistWithPhase is applied whether the parameter was found or
            % created: whether a phase should carry the value follows from what
            % the parameter is for, which the selector knows and the protocol
            % author may not have marked.
            %
            % Parameters:
            %   name  - parameter name
            %   value - initial value, used only when the parameter is created
            %   PersistWithPhase - mark the parameter as a persistent operator
            %       setting rather than transient session control, so a phase
            %       save records it and a phase load restores it (see
            %       hw.Parameter.isTransientControl). Only meaningful for
            %       Boolean parameters, which are otherwise assumed to be
            %       momentary buttons.
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
                options.PersistWithPhase (1,1) logical = false
            end

            p = [];
            if isempty(obj.runtime_), return; end

            p = obj.runtime_.find_parameter(name, silenceParameterNotFound=true);
            if ~isempty(p)
                p = p(1);
                p.PersistWithPhase = options.PersistWithPhase;
                return
            end

            sw = obj.runtime_.Interfaces(arrayfun(@(x) isa(x,'hw.Software'), ...
                obj.runtime_.Interfaces));
            if isempty(sw), return; end

            p = sw(1).add_parameter(name, value, ...
                Type=options.Type, Format=options.Format, Description=options.Description);

            p.UpdateEveryTrial = false;
            p.PersistWithPhase = options.PersistWithPhase;

            % add_parameter seeds Values, not Value; the first write is a
            % trial away, so seat the initial value now.
            p.Value = value;
        end

        function restore_stimdelay_randomization_(obj, pStimDelay)
            % restore_stimdelay_randomization_(obj, pStimDelay)
            % Restore the isRandom flag on pStimDelay from its saved UserData
            % and clear the CORRECTVAL sentinel so normal randomization resumes.
            %
            % A no-op under the block sequence, which never suspends anything
            % to restore: isRandom is held false for the whole session (it
            % would overwrite the drawn value on dispatch -- see
            % applyStimDelay_) and a repeat is a held index, not a stashed
            % value. Restoring a saved isRandom here would switch randi back
            % on underneath the sequence.
            %
            % Parameters:
            %   pStimDelay - hw.Parameter handle for StimDelay
            if obj.stimDelayBlockActive_(), return; end

            if isfield(pStimDelay.UserData, 'isRandom') && ~isempty(pStimDelay.UserData.isRandom)
                pStimDelay.isRandom = pStimDelay.UserData.isRandom;
            end
            pStimDelay.UserData.CORRECTVAL = [];
        end


        % ---------------------------------------------------------------- %
        % Block-randomized stimulus delay
        % ---------------------------------------------------------------- %

        function setupStimDelay_(obj, TRIALS)
            % setupStimDelay_(obj, TRIALS)
            % Resolve the block-randomized stimulus-delay machinery, once.
            %
            % Deferred to the first selection pass for the same reason as the
            % selector's other runtime parameters: initialize runs before
            % setRuntime, so there is no runtime to create a parameter on and
            % no live trials table to write into.
            %
            % A protocol that declares no StimDelayList gets none of this --
            % stimDelayList_ stays empty, stimDelayBlockActive_ is false, and
            % the isRandom/CORRECTVAL path in selectNextRow_ behaves exactly
            % as it always has.
            %
            % Parameters:
            %   TRIALS - runtime TRIALS struct for this subject
            obj.stimDelaySetup_ = true;

            if ~isfield(obj.P, 'StimDelayList')
                vprintf(3, 'No StimDelayList parameter; stimulus delay left to StimDelay.isRandom')
                return
            end
            if ~isfield(obj.P, 'StimDelay')
                vprintf(0, 1, 'StimDelayList is defined but StimDelay is not; the delay list cannot be delivered')
                return
            end

            obj.stimDelayList_ = obj.P.StimDelayList;
            if isfield(obj.P, 'StimDelayJitter')
                obj.stimDelayJitter_ = obj.P.StimDelayJitter;
            end
            obj.stimDelayStep_ = cl_AppetitiveStimDetect.ensureStimDelayStep( ...
                obj.runtime_, obj.stimDelayList_);

            obj.stimDelayCol_ = obj.stimDelayColumn_(TRIALS);
            if obj.stimDelayCol_ == 0
                vprintf(0, 1, ['StimDelay has no column in the compiled trials table; ' ...
                    'the delay list cannot be delivered'])
                obj.stimDelayList_ = [];
                return
            end

            % Default the operator's switch to whether the protocol actually
            % describes a list worth randomizing. A single-value list is a
            % fixed delay, which the operator asks for through the plain
            % Stimulus Delay field instead.
            dflt = numel(cl_AppetitiveStimDetect.stimDelayValues(obj.stimDelayList_, obj.stimDelayStep_)) > 1;
            obj.stimDelayEnabled_ = obj.ensureSelectorParameter_('StimDelayBlockEnabled', dflt, ...
                Type='Boolean', ...
                Description="Block-randomize the stimulus delay over StimDelayList", ...
                PersistWithPhase=true);

            obj.rebuildStimDelaySequence_();
        end

        function tf = stimDelayBlockActive_(obj)
            % tf = stimDelayBlockActive_(obj)
            % Whether the block sequence owns StimDelay right now.
            %
            % False while stimulus-delay training mode is on: gui.StaircaseTraining
            % steps StimDelay itself and writes it into the trials table, so
            % the two would overwrite each other every trial. The operator's
            % checkbox is deliberately left alone, so switching training back
            % off resumes the sequence where it stood.
            tf = false;
            if isempty(obj.stimDelayList_) || isempty(obj.stimDelaySeq_), return; end
            if ~isempty(obj.stimDelayEnabled_) && ~obj.stimDelayEnabled_.Value, return; end

            if isempty(obj.stimDelayTraining_) && ~isempty(obj.runtime_)
                p = obj.runtime_.find_parameter('StimDelayTrainingEnabled', silenceParameterNotFound=true);
                if ~isempty(p), obj.stimDelayTraining_ = p(1); end
            end
            if ~isempty(obj.stimDelayTraining_) && logical(obj.stimDelayTraining_.Value), return; end

            tf = true;
        end

        function applyStimDelay_(obj, TRIALS, nextTrialID)
            % applyStimDelay_(obj, TRIALS, nextTrialID)
            % Write the next block-randomized stimulus delay into the live
            % trials table, for whichever row was just selected.
            %
            % The value goes into the table rather than straight onto the
            % parameter because dispatchNextTrial assigns every
            % UpdateEveryTrial parameter from the table a moment later, and
            % would otherwise overwrite it. Writing only the selected row is
            % enough: this runs on every selection pass, whatever row it
            % chose, so catch and reminder trials carry a delay from the same
            % sequence as stimulus trials.
            %
            % Parameters:
            %   TRIALS      - runtime TRIALS struct for this subject
            %   nextTrialID - row index the selection just settled on
            if isempty(obj.stimDelayList_), return; end

            obj.rebuildStimDelaySequence_();   % no-op unless the operator edited the list
            if ~obj.stimDelayBlockActive_(), return; end

            % isRandom would redraw randi([Min Max]) inside set.Value on
            % dispatch and throw the balanced value away. Held false here
            % rather than once at setup because a phase load can turn it back
            % on halfway through a session.
            if obj.P.StimDelay.isRandom
                vprintf(2, 'StimDelay.isRandom cleared: the delay is driven by StimDelayList')
                obj.P.StimDelay.isRandom = false;
            end

            % The trials table the dispatcher reads is the runtime's, and
            % ep_TimerFcn_Start does not install it until after the
            % session-start selectNext returns -- so there is nowhere to write
            % on trial 1. That trial keeps its compiled delay and the sequence
            % starts at trial 2, which is exactly what the depth staircase
            % does: selectNextRow_ returns the first stimulus row on trial 1
            % without touching Depth either. Checked before the index
            % advances, so no value is silently skipped.
            if ~obj.trialsTableLive_()
                vprintf(2, 'Trial #%d: trials table not live yet; keeping the compiled stimulus delay', ...
                    TRIALS.TrialIndex)
                return
            end

            if ~obj.repeatStimDelay_ || obj.stimDelayIdx_ < 1
                obj.stimDelayIdx_ = obj.stimDelayIdx_ + 1;
            end

            try
                [v, info] = obj.stimDelaySeq_.valueAt(obj.stimDelayIdx_);
            catch ME
                vprintf(0, 1, 'Stimulus-delay sequence failed at index %d: %s', obj.stimDelayIdx_, ME.message)
                return
            end

            obj.runtime_.TRIALS(obj.subjectIdx_).trials{nextTrialID, obj.stimDelayCol_} = v;

            vprintf(3, 'Trial #%d: StimDelay %g ms (base %g, jitter %+0.1f, block %d pos %d)', ...
                TRIALS.TrialIndex, v, info.Base, info.Jitter, info.Block, info.PositionInBlock)
        end

        function rebuildStimDelaySequence_(obj)
            % rebuildStimDelaySequence_(obj)
            % Build the sequence, or reconcile it with an operator edit to the
            % list bounds, the step, or the jitter.
            %
            % Compared against a cached spec rather than rebuilt every trial:
            % assigning Values or Jitter freezes the delivered prefix and
            % abandons the partial block in progress (see
            % epsych.BlockSequence), so an unconditional assignment would
            % throw the balance away once per trial.
            if isempty(obj.stimDelayList_), return; end

            v = cl_AppetitiveStimDetect.stimDelayValues(obj.stimDelayList_, obj.stimDelayStep_);
            j = cl_AppetitiveStimDetect.stimDelayJitter(obj.stimDelayJitter_);
            lim = [obj.P.StimDelay.Min obj.P.StimDelay.Max];
            spec = [v NaN j NaN lim];   % NaN separates the three parts

            if isempty(v)
                if ~isempty(obj.stimDelaySeq_)
                    vprintf(0, 1, 'StimDelayList describes no values; the previous delay sequence is kept')
                end
                return
            end
            if isequaln(spec, obj.stimDelaySpec_), return; end

            if isempty(obj.stimDelaySeq_)
                % ValueLimits mirrors the clamp hw.Parameter applies on
                % dispatch, so the sequence's own record matches what the
                % hardware is actually given. JitterQuantum keeps delays on
                % whole milliseconds, as the randi path produced.
                obj.stimDelaySeq_ = epsych.BlockSequence(v, ...
                    Jitter        = j, ...
                    JitterQuantum = 1, ...
                    ValueLimits   = lim, ...
                    Label         = "StimDelay");
                obj.stimDelaySpec_ = spec;

                if ~obj.stimDelaySeq_.IsValid
                    vprintf(0, 1, 'Stimulus-delay sequence is unusable; the delay list will not be delivered')
                    obj.stimDelaySeq_ = [];
                    obj.stimDelayList_ = [];
                    return
                end

                if isscalar(v)
                    vprintf(1, 'Stimulus delay: fixed at %g ms, jitter +/-%g ms', v, j)
                else
                    vprintf(1, 'Stimulus delay: %d values, %g:%g:%g ms, jitter +/-%g ms, seed %d', ...
                        numel(v), v(1), v(2) - v(1), v(end), j, obj.stimDelaySeq_.Seed)
                end
                obj.warnStimDelayBounds_(v, j);
                return
            end

            % A mid-session edit. Every assignment is lazy, so the set is
            % validated together on the next read; trials already delivered
            % are frozen either way. A same-length replacement is a pure
            % lookup-table swap, so retuning the values keeps the ordering.
            obj.stimDelaySeq_.ValueLimits = lim;
            obj.stimDelaySeq_.Jitter = j;
            obj.stimDelaySeq_.Values = v;
            obj.stimDelaySpec_ = spec;

            vprintf(1, 'Stimulus delay list updated at trial %d: %d values, jitter +/-%g ms', ...
                obj.stimDelayIdx_ + 1, numel(v), j)
            obj.warnStimDelayBounds_(v, j);
        end

        function warnStimDelayBounds_(obj, v, j)
            % warnStimDelayBounds_(obj, v, j)
            % Report a list the StimDelay parameter's own bounds would clip.
            %
            % Clipping is silent otherwise -- hw.Parameter clamps on dispatch
            % -- and it biases the ends of the list, which is exactly the
            % thing a balanced sequence is for.
            lo = obj.P.StimDelay.Min;
            hi = obj.P.StimDelay.Max;
            if min(v) - j < lo || max(v) + j > hi
                vprintf(0, 1, ['Stimulus delay list %g-%g ms (jitter +/-%g) falls outside ' ...
                    'StimDelay bounds %g-%g ms; the ends will be clamped'], ...
                    min(v), max(v), j, lo, hi)
            end
        end

        function tf = trialsTableLive_(obj)
            % tf = trialsTableLive_(obj)
            % Whether RUNTIME.TRIALS holds a trials table this selector can
            % write into. False during the session-start selectNext, which
            % ep_TimerFcn_Start makes before it installs TRIALS on the runtime.
            tf = ~isempty(obj.runtime_) ...
                && numel(obj.runtime_.TRIALS) >= obj.subjectIdx_ ...
                && ~isempty(obj.runtime_.TRIALS(obj.subjectIdx_).trials);
        end

        function c = stimDelayColumn_(~, TRIALS)
            % c = stimDelayColumn_(obj, TRIALS)
            % StimDelay's column in the compiled trials table, or 0.
            c = 0;
            if ~isfield(TRIALS, 'writeParamIdx') || ~isstruct(TRIALS.writeParamIdx), return; end
            if ~isfield(TRIALS.writeParamIdx, 'StimDelay'), return; end
            c = TRIALS.writeParamIdx.StimDelay;
        end

    end

end
