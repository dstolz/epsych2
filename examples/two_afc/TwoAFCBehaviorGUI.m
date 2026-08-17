classdef TwoAFCBehaviorGUI < gui.BehaviorGUI
    % TwoAFCBehaviorGUI  Behavior GUI for the 2AFC tutorial, in which YOU are the
    % subject.
    %
    % Two lamps flash together, one brighter than the other; report which
    % side was brighter by clicking LEFT / RIGHT or pressing the arrow
    % keys. Every trial demands a choice — there is no "withhold" option,
    % which is what makes the task forced choice. Failing to answer inside
    % the response window aborts the trial (epsych.BitMask.Abort) rather
    % than scoring it.
    %
    % Like FirstExperimentBehaviorGUI (examples/first_experiment), this GUI also
    % plays the role the rig hardware plays in a real experiment: it runs
    % the trial timeline, scores the choice, writes the read-back
    % parameters, and raises x_TrialComplete_1 — the flag
    % ep_TimerFcn_RunTime polls on every tick. What is new here is the
    % two-alternative scoring. A 2AFC has no "signal absent" trial, so the
    % detection outcome names are recast by treating ONE alternative —
    % left, here — as the yes-response:
    %
    %   left correct  + chose left  = Hit           (+ Reward)
    %   left correct  + chose right = Miss          (+ Punish)
    %   right correct + chose right = CorrectReject (+ Reward)
    %   right correct + chose left  = FalseAlarm    (+ Punish)
    %   no answer in the window     = Abort
    %
    % plus a Choice_0 (left) or Choice_1 (right) bit recording WHAT was
    % chosen alongside whether it was correct. That recasting is what lets
    % the shipped analysis apply unchanged and with its DEFAULT trial-type
    % settings (stimulus = TrialType_0, catch = TrialType_1): percent
    % correct is (Hit + CorrectReject) over scored trials, d' is
    % discriminability, and the criterion is the subject's side bias —
    % negative when they favour LEFT. See psychophysics.SessionMetrics.
    %
    % Launch in a real session by setting a project's Behavior GUI to
    % TwoAFCBehaviorGUI (Subjects > Subjects & Projects, Project > Edit
    % Project..., Session Defaults tab); the class must be on the path. Or
    % run a session without RunExpt: run_2afc_experiment (same folder).
    %
    % Walkthrough: https://github.com/dstolz/epsych2/wiki/Two-AFC-Task
    %
    % See also gui.BehaviorGUI, create_2afc_protocol, run_2afc_experiment

    properties (SetAccess = private)
        % Subject-facing. The stimulus patches are plain uipanels rather
        % than uilamps: a lamp is drawn as a shaded sphere, and that
        % gradient swamps the luminance difference this task is about. A
        % panel's BackgroundColor renders as the flat, uniform field a
        % brightness discrimination needs.
        LeftPatch     matlab.ui.container.Panel
        RightPatch    matlab.ui.container.Panel
        LeftButton    matlab.ui.control.Button
        RightButton   matlab.ui.control.Button
        FeedbackLabel matlab.ui.control.Label
        % Operator-facing
        ModeLabel     matlab.ui.control.Label
        TrialLabel    matlab.ui.control.Label
        TallyLabel    matlab.ui.control.Label
        ChoiceTable   matlab.ui.control.Table
    end

    properties (Access = private)
        RigTimer                       % periodic timer advancing the trial timeline
        RigState (1,:) char = 'idle'   % idle | iti | stim | respwin | done
        StateClock                     % tic handle for the current state
        StateDur (1,1) double = 0      % seconds the current state lasts
        RespClock                      % tic at response-window open, for RT
        TrialCorrectSide (1,1) double = 0 % 0 = left, 1 = right
        TrialContrast (1,1) double = 0
    end

    properties (Constant, Access = private)
        PATCH_DARK = [0.06 0.06 0.06] % between trials, both fields near-black
    end

    methods
        function obj = TwoAFCBehaviorGUI(RUNTIME)
            obj@gui.BehaviorGUI(RUNTIME, Name = '2AFC — Which Side Was Brighter?', ...
                DefaultPosition = [100 100 1100 780]);
            if nargout == 0, clear obj; end
        end

        function delete(obj)
            % The base class tears down listeners, registered components,
            % and the figure; the rig timer is ours to stop.
            try
                if ~isempty(obj.RigTimer) && isvalid(obj.RigTimer)
                    stop(obj.RigTimer);
                    delete(obj.RigTimer);
                end
            catch
            end
        end

        function respondSide(obj, side)
            % respondSide(obj, side)
            % Register the subject's choice: 0 = left, 1 = right. Public so
            % a script (or the smoke test) can answer programmatically, and
            % the single path every response takes — button, arrow key, or
            % script. Ignored outside the response window.
            arguments
                obj
                side (1,1) double {mustBeMember(side, [0 1])}
            end
            if ~strcmp(obj.RigState, 'respwin'), return; end
            obj.score_(side);
        end
    end

    methods (Access = protected)
        function p = createPsych(obj, R)
            % Track choices against Contrast. No trial-type overrides are
            % needed: scoring left-correct trials as Hit/Miss and
            % right-correct trials as CorrectReject/FalseAlarm already
            % matches the defaults (stimulus = TrialType_0, catch =
            % TrialType_1), which is the reason for that mapping.
            p = [];
            if isfield(obj.P, 'Contrast')
                p = psychophysics.Detection(R, obj.P.Contrast);
            end
        end

        function build(obj, fig)
            g = uigridlayout(fig, [2 2]);
            g.RowHeight   = {26, '1x'};
            g.ColumnWidth = {'1.25x', '1x'};

            % Header. The trial label never names the upcoming side or
            % contrast: subject and operator share one screen here. For the
            % same reason this GUI has no gui.NextTrial panel — it displays
            % the dispatched condition, which would show the answer.
            hdr = uigridlayout(g, [1 3]);
            hdr.Layout.Row = 1; hdr.Layout.Column = [1 2];
            hdr.Padding = [0 0 0 0];
            obj.ModeLabel  = uilabel(hdr, Text = 'Mode: -', FontWeight = 'bold');
            obj.TrialLabel = uilabel(hdr, Text = 'Waiting for session start...');
            obj.TallyLabel = uilabel(hdr, Text = '', HorizontalAlignment = 'right');

            % --- Subject panel -------------------------------------------
            pnl = uipanel(g, 'Title', 'Subject — which side was brighter?');
            pnl.Layout.Row = 2; pnl.Layout.Column = 1;
            sg = uigridlayout(pnl, [3 2]);
            sg.RowHeight = {'2x', 80, 34};

            obj.LeftPatch  = uipanel(sg, BackgroundColor = obj.PATCH_DARK, ...
                BorderType = 'none');
            obj.RightPatch = uipanel(sg, BackgroundColor = obj.PATCH_DARK, ...
                BorderType = 'none');

            obj.LeftButton = uibutton(sg, Text = '◀  LEFT', ...
                FontSize = 22, FontWeight = 'bold', Enable = 'off', ...
                Tooltip = 'Left lamp was brighter (or press the left arrow key)', ...
                ButtonPushedFcn = @(~,~) obj.respondSide(0));
            obj.RightButton = uibutton(sg, Text = 'RIGHT  ▶', ...
                FontSize = 22, FontWeight = 'bold', Enable = 'off', ...
                Tooltip = 'Right lamp was brighter (or press the right arrow key)', ...
                ButtonPushedFcn = @(~,~) obj.respondSide(1));
            obj.register(obj.LeftButton);
            obj.register(obj.RightButton);

            obj.FeedbackLabel = uilabel(sg, Text = '', FontSize = 17, ...
                FontWeight = 'bold', HorizontalAlignment = 'center');
            obj.FeedbackLabel.Layout.Column = [1 2];

            % Arrow keys answer too, so a subject can keep their eyes on
            % the lamps instead of hunting for a button. Both routes call
            % respondSide, which ignores anything outside the window.
            fig.WindowKeyPressFcn = @(~,evt) obj.keyPressed_(evt);

            % --- Operator panel ------------------------------------------
            og = uigridlayout(g, [4 1]);
            og.Layout.Row = 2; og.Layout.Column = 2;
            og.RowHeight = {124, 168, 190, '1x'};
            og.Padding = [0 0 0 0];

            col = obj.controlColumn(og, Title = 'Session Controls', Row = 1, Rows = 3);
            obj.addControl(col, 'FlashDur',   Text = 'Flash duration (ms)');
            obj.addControl(col, 'RespWinDur', Text = 'Response window (ms)');
            obj.addUpdateButton(col);

            % Percent correct and criterion are the 2AFC numbers; the
            % criterion is the side bias, negative when the subject
            % favours LEFT (the nominal yes-response).
            pnl = uipanel(og, 'Title', 'Session Performance');
            pnl.Layout.Row = 2;
            obj.addPerformance(pnl, ShowDetail = false, ...
                Metrics = ["Trials", "PercentCorrect", "AbortRate", "DPrime", "Criterion"]);

            % Per-trial complement to the binned table below: every trial's
            % signed contrast plotted at the side actually chosen, colored by
            % outcome. Refreshes itself on every completed trial.
            pnl = uipanel(og, 'Title', 'Signed Contrast by Chosen Side');
            pnl.Layout.Row = 3;
            obj.register(gui.ParameterScatter(obj.RUNTIME, pnl, ...
                XParameter = 'SignedContrast', YParameter = 'ChoiceSide', ...
                ColorParameter = 'Response'));

            % The live psychometric function: P(chose right) against signed
            % contrast (negative = left brighter). A subject with no bias
            % produces a curve through 50% at zero.
            pnl = uipanel(og, 'Title', 'Choices by Signed Contrast');
            pnl.Layout.Row = 4;
            inner = uigridlayout(pnl, [1 1]);
            inner.Padding = [0 0 0 0];
            obj.ChoiceTable = uitable(inner);
            obj.ChoiceTable.ColumnName = {'Signed contrast', 'n', '% chose right'};
            obj.ChoiceTable.ColumnWidth = {'1x', 'fit', '1x'};

            % The rig timer runs for the life of the window; its tick does
            % nothing until a session mode change arms the first trial.
            obj.RigTimer = timer( ...
                Name = [obj.PreferenceTag '_rig'], ...
                Period = 0.02, ...
                ExecutionMode = 'fixedSpacing', ...
                BusyMode = 'drop', ...
                TimerFcn = @(~,~) obj.rigTick_(), ...
                ErrorFcn = @(~,evt) vprintf(0,1,'%s rig timer error: %s', ...
                    class(obj), evt.Data.message));
            start(obj.RigTimer);
        end

        function onNewTrial(obj, ~, ~)
            % The runtime just dispatched the next condition (and, on the
            % way in, pulsed ResetTrig/NewTrial). Start its timeline.
            obj.beginTrial_();
        end

        function onModeChange(obj, ~, event)
            obj.ModeLabel.Text = "Mode: " + event.NewMode.asString();
            running = any(event.NewMode == [hw.DeviceState.Record, hw.DeviceState.Preview]);
            if running
                obj.ModeLabel.FontColor = [0 0.5 0];
                % Trial 1 was dispatched before this window existed (the
                % TRIALS setter dispatches it inside ep_TimerFcn_Start), so
                % its NewTrial event was never heard. Start its timeline
                % now; later trials arrive through onNewTrial.
                if strcmp(obj.RigState, 'idle')
                    obj.beginTrial_();
                end
            else
                obj.ModeLabel.FontColor = [0.6 0.1 0.1];
                obj.stopRig_();
            end
        end

        function onNewData(obj, ~, ~)
            % obj.Psych ingested the completed trial before this hook ran.
            P = obj.Psych;
            if isempty(P) || ~isvalid(P) || isempty(P.DATA), return; end

            D = P.DATA;
            choice = [D.ChoiceSide];
            answered = choice >= 0;
            nCorrect = sum(bitget(uint32([D.RespCode]), uint32(epsych.BitMask.Hit)) | ...
                bitget(uint32([D.RespCode]), uint32(epsych.BitMask.CorrectReject)));
            obj.TallyLabel.Text = sprintf('%d trials | %d%% correct | %d aborted', ...
                numel(D), round(100 * nCorrect / max(1, sum(answered))), sum(~answered));

            % Signed contrast: negative = left lamp brighter (left correct).
            signed = [D.Contrast] .* (2 * [D.TrialType] - 1);
            lvls = unique(signed);
            S = strings(numel(lvls), 3);
            for k = 1:numel(lvls)
                ind = signed == lvls(k) & answered;
                S(k,:) = [compose("%+.2f", lvls(k)), compose("%d", sum(ind)), ...
                    compose("%.0f", 100 * mean(choice(ind) == 1))];
            end
            obj.ChoiceTable.Data = S;
        end
    end

    methods (Access = private)

        function tf = rigReady_(obj)
            % The rig can only run against a runtime that actually has the
            % tutorial protocol loaded; the pre-flight SelfTest opens this
            % GUI against a synthetic runtime with no parameters at all.
            tf = all(isfield(obj.P, {'TrialType', 'Contrast', 'BaseLevel', ...
                'FlashDur', 'ITI', 'RespWinDur', 'RespCode', 'ChoiceSide', ...
                'RT_ms', 'SignedContrast', 'InTrial', 'x_TrialComplete_1'})) ...
                && ~isempty(obj.RUNTIME.TRIALS) && isstruct(obj.RUNTIME.TRIALS);
        end

        function beginTrial_(obj)
            if ~obj.rigReady_(), return; end
            T = obj.RUNTIME.TRIALS(1);

            % Handing the completion flag back to 0 is this GUI's half of
            % the polling contract: the runtime never clears it, and a
            % stuck 1 would complete a "trial" on every 10 ms timer tick.
            obj.P.x_TrialComplete_1.Value = 0;

            row = T.NextTrialID;
            obj.TrialCorrectSide = T.trials{row, T.writeParamIdx.TrialType};
            obj.TrialContrast    = T.trials{row, T.writeParamIdx.Contrast};

            obj.TrialLabel.Text = sprintf('Trial %d', T.TrialIndex);
            obj.setPatches_(false);
            obj.armButtons_(false);
            obj.setReadParameter_(obj.P.InTrial, true);

            % ITI first: both lamps dark for the interval the dispatch just
            % drew into ITI.Value (isRandom redraws it every trial).
            obj.setState_('iti', obj.paramMs_('ITI', 1200) / 1000);
        end

        function rigTick_(obj)
            try
                switch obj.RigState
                    case 'iti'
                        if toc(obj.StateClock) >= obj.StateDur
                            % Stimulus: both lamps on, the target brighter
                            % by Contrast. They go off together, so
                            % duration carries no information about side.
                            obj.FeedbackLabel.Text = '';
                            obj.setPatches_(true);
                            obj.setState_('stim', obj.paramMs_('FlashDur', 150) / 1000);
                        end
                    case 'stim'
                        if toc(obj.StateClock) >= obj.StateDur
                            obj.setPatches_(false);
                            obj.armButtons_(true);
                            obj.RespClock = tic;
                            obj.setState_('respwin', obj.paramMs_('RespWinDur', 3000) / 1000);
                        end
                    case 'respwin'
                        if toc(obj.RespClock) >= obj.StateDur
                            obj.score_(-1); % no answer in time: abort
                        end
                    otherwise
                        % idle / done: nothing to advance.
                end
            catch ME
                vprintf(0, 1, ME)
            end
        end

        function keyPressed_(obj, evt)
            % Arrow keys are the subject's other input. Anything else is
            % ignored, and respondSide drops presses outside the window.
            switch evt.Key
                case {'leftarrow'},  obj.respondSide(0);
                case {'rightarrow'}, obj.respondSide(1);
            end
        end

        function score_(obj, choiceSide)
            % Score the current trial and complete it. choiceSide is 0
            % (left), 1 (right), or -1 when the response window lapsed.
            % -1 rather than NaN because a parameter cannot store NaN: the
            % write is clamped with max(value, Min), which ignores NaN and
            % yields Min instead (see create_2afc_protocol).
            rt = -1;
            answered = choiceSide >= 0;
            if answered && strcmp(obj.RigState, 'respwin')
                rt = round(toc(obj.RespClock) * 1000);
            end

            leftCorrect = obj.TrialCorrectSide == 0;
            if ~answered
                bits = epsych.BitMask.Abort;
            else
                correct = choiceSide == obj.TrialCorrectSide;
                % Outcome names are the detection ones recast with LEFT as
                % the yes-response: choosing left is a Hit when left was
                % correct and a FalseAlarm when it was not. Keeping Hit on
                % TrialType_0 trials is what lets psychophysics.Detection
                % and SessionMetrics score this session with their default
                % stimulus/catch settings.
                if leftCorrect
                    if correct, bits = epsych.BitMask.Hit;
                    else,       bits = epsych.BitMask.Miss;
                    end
                else
                    if correct, bits = epsych.BitMask.CorrectReject;
                    else,       bits = epsych.BitMask.FalseAlarm;
                    end
                end
                if correct
                    bits(end+1) = epsych.BitMask.Reward;
                else
                    bits(end+1) = epsych.BitMask.Punish;
                end
                % Which alternative was chosen, independent of correctness.
                if choiceSide == 1
                    bits(end+1) = epsych.BitMask.Choice_1;
                else
                    bits(end+1) = epsych.BitMask.Choice_0;
                end
            end
            if leftCorrect
                bits(end+1) = epsych.BitMask.TrialType_0;
            else
                bits(end+1) = epsych.BitMask.TrialType_1;
            end

            obj.armButtons_(false);
            obj.setPatches_(false);
            obj.showFeedback_(answered, answered && choiceSide == obj.TrialCorrectSide);

            rc = epsych.BitMask.Bits2Mask(uint32(bits));
            obj.setReadParameter_(obj.P.ChoiceSide, choiceSide);
            obj.setReadParameter_(obj.P.RT_ms, rt);
            obj.setReadParameter_(obj.P.RespCode, double(rc));
            % Negative = left brighter (left correct), matching the sign
            % convention every plot and analysis in this tutorial uses.
            obj.setReadParameter_(obj.P.SignedContrast, ...
                obj.TrialContrast * (2 * obj.TrialCorrectSide - 1));
            obj.setReadParameter_(obj.P.InTrial, false);

            % Raising the completion flag hands the trial to the runtime:
            % the next ep_TimerFcn_RunTime tick collects the Read
            % parameters into DATA, journals them, broadcasts NewData, and
            % dispatches the next condition (which fires onNewTrial here).
            obj.P.x_TrialComplete_1.Value = 1;
            obj.setState_('done', 0);
        end

        function showFeedback_(obj, answered, correct)
            if ~answered
                obj.FeedbackLabel.Text = 'TOO SLOW';
                obj.FeedbackLabel.FontColor = epsych.BitMask.getDefaultColors(epsych.BitMask.Abort);
            elseif correct
                obj.FeedbackLabel.Text = 'CORRECT';
                obj.FeedbackLabel.FontColor = epsych.BitMask.getDefaultColors(epsych.BitMask.Hit);
            else
                obj.FeedbackLabel.Text = 'INCORRECT';
                obj.FeedbackLabel.FontColor = epsych.BitMask.getDefaultColors(epsych.BitMask.FalseAlarm);
            end
        end

        function stopRig_(obj)
            obj.setState_('idle', 0);
            obj.setPatches_(false);
            obj.armButtons_(false);
        end

        function setState_(obj, name, durSec)
            obj.RigState = name;
            obj.StateClock = tic;
            obj.StateDur = durSec;
        end

        function armButtons_(obj, on)
            state = matlab.lang.OnOffSwitchState(on);
            obj.LeftButton.Enable  = state;
            obj.RightButton.Enable = state;
        end

        function setPatches_(obj, on)
            if ~on
                obj.LeftPatch.BackgroundColor  = obj.PATCH_DARK;
                obj.RightPatch.BackgroundColor = obj.PATCH_DARK;
                return
            end
            base = obj.paramValue_('BaseLevel', 0.35);
            bright = min(base + obj.TrialContrast, 1);
            if obj.TrialCorrectSide == 1
                lv = base; rv = bright;
            else
                lv = bright; rv = base;
            end
            obj.LeftPatch.BackgroundColor  = [lv lv lv];
            obj.RightPatch.BackgroundColor = [rv rv rv];
        end

        function ms = paramMs_(obj, name, fallback)
            ms = obj.paramValue_(name, fallback);
        end

        function v = paramValue_(obj, name, fallback)
            % Read a parameter defensively: a live experiment GUI must
            % never error or stall on a transiently empty, NaN, or
            % non-scalar Value (e.g. read during a dispatch), so anything
            % unusable degrades to the protocol's default instead.
            v = fallback;
            try
                x = obj.P.(name).Value;
                if isscalar(x) && isfinite(x) && x >= 0
                    v = double(x);
                end
            catch
            end
        end
    end

    methods (Static, Access = private)
        function setReadParameter_(p, val)
            % Rig-side write to a read-back parameter. Hardware backends
            % refresh these from the device; hw.Software stores the Value
            % in the parameter object, but Access='Read' blocks set.Value,
            % so widen access for the write and restore it. This GUI is
            % standing in for the rig, which is the only reason code like
            % this exists outside a simulation.
            if isempty(p), return; end
            ac = p.Access;
            p.Access = 'Any';
            p.Value = val;
            p.Access = ac;
        end
    end
end
