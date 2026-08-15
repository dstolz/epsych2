classdef FirstExperimentBoxGUI < gui.BehaviorGUI
    % FirstExperimentBoxGUI  Box GUI for the first-experiment tutorial, in
    % which YOU are the subject.
    %
    % The left panel faces the subject: a stimulus lamp that flashes on go
    % trials and a RESPOND button that arms during the response window.
    % Press it when you saw a flash; withhold when you did not.
    %
    % The GUI also plays the role the rig hardware plays in a real
    % experiment: it runs the trial's timeline (ITI, flash, response
    % window), scores the outcome as an epsych.BitMask code, writes the
    % RespCode/RT_ms/InTrial read-back parameters, and raises
    % x_TrialComplete_1 — the flag ep_TimerFcn_RunTime polls on every
    % timer tick. That completes the trial: the runtime records the DATA
    % entry, broadcasts NewData, selects the next condition, dispatches
    % it, and broadcasts NewTrial, which starts this GUI's next timeline.
    % On a TDT or Teensy rig, everything in this paragraph happens in the
    % device; the parameter names are the contract, not where they are set.
    %
    % Launch in a real session by setting a project's Box GUI to
    % FirstExperimentBoxGUI (Subjects > Subjects & Projects, Project >
    % Edit Project..., Session Defaults tab); the class must be on the
    % path. Or run a session without RunExpt: run_first_experiment
    % (same folder).
    %
    % Walkthrough: https://github.com/dstolz/epsych2/wiki/Your-First-Experiment
    %
    % See also gui.BehaviorGUI, create_first_protocol, run_first_experiment

    properties (SetAccess = private)
        % Subject-facing
        StimLamp      matlab.ui.control.Lamp
        RespondButton matlab.ui.control.Button
        FeedbackLabel matlab.ui.control.Label
        % Operator-facing
        ModeLabel     matlab.ui.control.Label
        TrialLabel    matlab.ui.control.Label
        TallyLabel    matlab.ui.control.Label
    end

    properties (Access = private)
        RigTimer                       % periodic timer advancing the trial timeline
        RigState (1,:) char = 'idle'   % idle | iti | stim | respwin | done
        StateClock                     % tic handle for the current state
        StateDur (1,1) double = 0      % seconds the current state lasts
        RespClock                      % tic at response-window open, for RT
        LampIsOn (1,1) logical = false
        TrialIsGo (1,1) logical = false
        TrialFlashDur (1,1) double = 0 % ms
    end

    properties (Constant, Access = private)
        LAMP_OFF = [0.25 0.25 0.25]
        LAMP_ON  = [1 0.85 0.1]
    end

    methods
        function obj = FirstExperimentBoxGUI(RUNTIME)
            obj@gui.BehaviorGUI(RUNTIME, Name = 'First Experiment — Flash Detection', ...
                DefaultPosition = [100 100 950 560]);
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

        function respond(obj)
            % respond(obj)
            % The RESPOND button's callback. Public so a script (or the
            % smoke test) can press the button programmatically. Ignored
            % outside the response window — the button is only enabled
            % while the window is open, so a click cannot normally land
            % anywhere else.
            if ~strcmp(obj.RigState, 'respwin'), return; end
            obj.score_(true, NaN);
        end
    end

    methods (Access = protected)
        function p = createPsych(obj, R)
            % Track go-trial performance against FlashDur; feeds the
            % session performance panel and the tally. Returns [] against
            % a runtime whose protocol lacks the parameter (SelfTest I6).
            p = [];
            if isfield(obj.P, 'FlashDur')
                p = psychophysics.Detection(R, obj.P.FlashDur, ...
                    epsych.BitMask.TrialType_0);
            end
        end

        function build(obj, fig)
            g = uigridlayout(fig, [2 2]);
            g.RowHeight   = {26, '1x'};
            g.ColumnWidth = {'1.2x', '1x'};

            % Header: session mode, trial counter, running tally. The trial
            % label deliberately never names the upcoming trial type —
            % subject and operator share one screen here, and announcing
            % "catch trial" would tell the subject the answer.
            hdr = uigridlayout(g, [1 3]);
            hdr.Layout.Row = 1; hdr.Layout.Column = [1 2];
            hdr.Padding = [0 0 0 0];
            obj.ModeLabel = uilabel(hdr, Text = 'Mode: -', FontWeight = 'bold');
            obj.TrialLabel = uilabel(hdr, Text = 'Waiting for session start...');
            obj.TallyLabel = uilabel(hdr, Text = '', HorizontalAlignment = 'right');

            % --- Subject panel: what the "animal" sees -------------------
            pnl = uipanel(g, 'Title', 'Subject — that''s you');
            pnl.Layout.Row = 2; pnl.Layout.Column = 1;
            sg = uigridlayout(pnl, [3 1]);
            sg.RowHeight = {'2x', 90, 40};

            lampCell = uigridlayout(sg, [1 3]);
            lampCell.ColumnWidth = {'1x', 120, '1x'};
            lampCell.Padding = [0 0 0 0];
            obj.StimLamp = uilamp(lampCell, Color = obj.LAMP_OFF);
            obj.StimLamp.Layout.Column = 2;

            obj.RespondButton = uibutton(sg, ...
                Text = 'RESPOND', ...
                FontSize = 26, FontWeight = 'bold', ...
                Enable = 'off', ...
                Tooltip = 'Armed during the response window; press if you saw a flash', ...
                ButtonPushedFcn = @(~,~) obj.respond());
            obj.register(obj.RespondButton);

            obj.FeedbackLabel = uilabel(sg, Text = '', FontSize = 18, ...
                FontWeight = 'bold', HorizontalAlignment = 'center');

            % --- Operator panel ------------------------------------------
            og = uigridlayout(g, [3 1]);
            og.Layout.Row = 2; og.Layout.Column = 2;
            og.RowHeight = {150, '1x', 92};
            og.Padding = [0 0 0 0];

            % Editable timing parameters, committed by the update button.
            col = obj.controlColumn(og, Title = 'Session Controls', Row = 1, Rows = 4);
            obj.addControl(col, 'RespWinDelay', Text = 'Response window delay (ms)');
            obj.addControl(col, 'RespWinDur',   Text = 'Response window duration (ms)');
            obj.addUpdateButton(col);

            % Live per-flash-duration performance.
            pnl = uipanel(og, 'Title', 'Session Performance');
            pnl.Layout.Row = 2;
            obj.addPerformance(pnl);

            % Manual scoring: the operator can end the current trial with a
            % forced outcome at any point in its timeline — handy for
            % testing the data path without playing subject. These write
            % the same RespCode/TrialComplete contract as a real response.
            pnl = uipanel(og, 'Title', 'Manual Scoring (operator)');
            pnl.Layout.Row = 3;
            mg = uigridlayout(pnl, [1 4]);
            mg.Padding = [4 4 4 4];
            outcomes = [epsych.BitMask.Hit, epsych.BitMask.Miss, ...
                epsych.BitMask.FalseAlarm, epsych.BitMask.CorrectReject];
            labels = {'Hit', 'Miss', 'False Alarm', 'Correct Reject'};
            for k = 1:numel(outcomes)
                b = uibutton(mg, Text = labels{k}, ...
                    ButtonPushedFcn = @(~,~) obj.scoreManual_(outcomes(k)));
                obj.register(b);
            end

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
            obj.TallyLabel.Text = sprintf('%d trials | %d hits | %d false alarms', ...
                P.NumTrials, sum(P.Hit_Ind), sum(P.FA_Ind));
        end
    end

    methods (Access = private)

        function tf = rigReady_(obj)
            % The rig can only run against a runtime that actually has the
            % tutorial protocol loaded; the pre-flight SelfTest opens this
            % GUI against a synthetic runtime with no parameters at all.
            tf = all(isfield(obj.P, {'TrialType', 'FlashDur', 'ITI', ...
                'RespWinDelay', 'RespWinDur', 'RespCode', 'RT_ms', ...
                'InTrial', 'x_TrialComplete_1'})) ...
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
            obj.TrialIsGo     = T.trials{row, T.writeParamIdx.TrialType} == 0;
            obj.TrialFlashDur = T.trials{row, T.writeParamIdx.FlashDur};

            % The previous trial's HIT/MISS feedback is left up on purpose:
            % the next condition dispatches within one timer tick of
            % completion, so clearing here would blank it almost instantly.
            % It clears at this trial's stimulus onset instead.
            obj.TrialLabel.Text = sprintf('Trial %d', T.TrialIndex);
            obj.setLamp_(false);
            obj.RespondButton.Enable = 'off';
            obj.setReadParameter_(obj.P.InTrial, true);

            % ITI first: the lamp stays dark for the interval the dispatch
            % just drew into ITI.Value (isRandom redraws it every trial).
            obj.setState_('iti', obj.paramMs_('ITI', 1000) / 1000);
        end

        function rigTick_(obj)
            try
                switch obj.RigState
                    case 'iti'
                        if toc(obj.StateClock) >= obj.StateDur
                            % Trial onset: flash on go trials, nothing on
                            % catch trials. The response window opens at a
                            % fixed delay either way, so its timing never
                            % gives the trial type away.
                            obj.FeedbackLabel.Text = '';
                            obj.setState_('stim', obj.paramMs_('RespWinDelay', 400) / 1000);
                            if obj.TrialIsGo && obj.TrialFlashDur > 0
                                obj.setLamp_(true);
                            end
                        end
                    case 'stim'
                        elapsedMs = toc(obj.StateClock) * 1000;
                        if obj.LampIsOn && elapsedMs >= obj.TrialFlashDur
                            obj.setLamp_(false);
                        end
                        if elapsedMs >= obj.StateDur * 1000
                            obj.setLamp_(false);
                            obj.RespondButton.Enable = 'on';
                            obj.RespClock = tic;
                            obj.setState_('respwin', obj.paramMs_('RespWinDur', 1500) / 1000);
                        end
                    case 'respwin'
                        if toc(obj.RespClock) >= obj.StateDur
                            obj.score_(false, NaN);
                        end
                    otherwise
                        % idle / done: nothing to advance.
                end
            catch ME
                vprintf(0, 1, ME)
            end
        end

        function score_(obj, responded, forcedBit)
            % Score the current trial and complete it. The outcome matrix
            % is the whole task contingency:
            %       go trial      catch trial
            %   responded   Hit + Reward  FalseAlarm + Punish
            %   withheld    Miss          CorrectReject
            % forcedBit (from a manual-scoring button) overrides the
            % response half of that; NaN means score naturally.
            %
            % -1 is the no-response reaction time, because a parameter
            % cannot store NaN: the write is clamped with max(value, Min),
            % which ignores NaN and yields Min (see create_first_protocol).
            rt = -1;
            if responded && strcmp(obj.RigState, 'respwin')
                rt = round(toc(obj.RespClock) * 1000);
            end

            if isnan(forcedBit)
                if obj.TrialIsGo
                    if responded, bits = [epsych.BitMask.Hit, epsych.BitMask.Reward];
                    else,         bits = epsych.BitMask.Miss;
                    end
                else
                    if responded, bits = [epsych.BitMask.FalseAlarm, epsych.BitMask.Punish];
                    else,         bits = epsych.BitMask.CorrectReject;
                    end
                end
            else
                bits = forcedBit;
            end
            if obj.TrialIsGo
                bits(end+1) = epsych.BitMask.TrialType_0;
            else
                bits(end+1) = epsych.BitMask.TrialType_1;
            end

            obj.RespondButton.Enable = 'off';
            obj.setLamp_(false);
            obj.showFeedback_(bits(1));

            rc = epsych.BitMask.Bits2Mask(uint32(bits));
            obj.setReadParameter_(obj.P.RT_ms, rt);
            obj.setReadParameter_(obj.P.RespCode, double(rc));
            obj.setReadParameter_(obj.P.InTrial, false);

            % Raising the completion flag hands the trial to the runtime:
            % the next ep_TimerFcn_RunTime tick collects the Read
            % parameters into DATA, journals them, broadcasts NewData, and
            % dispatches the next condition (which fires onNewTrial here).
            obj.P.x_TrialComplete_1.Value = 1;
            obj.setState_('done', 0);
        end

        function scoreManual_(obj, outcomeBit)
            % Operator override: end the current trial with a forced
            % outcome, whatever point of its timeline it is at.
            if any(strcmp(obj.RigState, {'idle', 'done'})), return; end
            obj.score_(false, outcomeBit);
        end

        function showFeedback_(obj, outcomeBit)
            names = struct( ...
                'Hit', 'HIT', 'Miss', 'MISS', ...
                'FalseAlarm', 'FALSE ALARM', 'CorrectReject', 'CORRECT REJECT');
            n = char(outcomeBit);
            if ~isfield(names, n), return; end
            obj.FeedbackLabel.Text = names.(n);
            obj.FeedbackLabel.FontColor = epsych.BitMask.getDefaultColors(outcomeBit);
        end

        function stopRig_(obj)
            obj.setState_('idle', 0);
            obj.setLamp_(false);
            obj.RespondButton.Enable = 'off';
        end

        function setState_(obj, name, durSec)
            obj.RigState = name;
            obj.StateClock = tic;
            obj.StateDur = durSec;
        end

        function ms = paramMs_(obj, name, fallback)
            % Read a duration parameter defensively: a live experiment GUI
            % must never error or stall on a transiently empty, NaN, or
            % non-scalar Value (e.g. read during a dispatch), so anything
            % unusable degrades to the protocol's default instead.
            ms = fallback;
            try
                v = obj.P.(name).Value;
                if isscalar(v) && isfinite(v) && v >= 0
                    ms = double(v);
                end
            catch
            end
        end

        function setLamp_(obj, on)
            obj.LampIsOn = on;
            if on
                obj.StimLamp.Color = obj.LAMP_ON;
            else
                obj.StimLamp.Color = obj.LAMP_OFF;
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
