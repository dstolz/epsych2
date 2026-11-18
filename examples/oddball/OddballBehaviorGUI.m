classdef OddballBehaviorGUI < gui.BehaviorGUI
    % OddballBehaviorGUI  Behavior GUI for the auditory oddball example, in
    % which YOU are the subject.
    %
    % A stream of short sounds plays, one per trial. Most are STANDARDS; now
    % and then a DEVIANT. Press RESPOND (or the space bar) inside the
    % response window when you hear a deviant, and let the standards go by.
    % After every sound the GUI says how that trial scored -- HIT, MISS,
    % FALSE ALARM, or CORRECT REJECT -- and the tally, the performance panel,
    % the plots and the trial history follow along.
    %
    % The window has four parts:
    %   - the transport bar: Start (gui.components.SessionGate), Pause/Resume,
    %     Stop, the run-mode lamp, and the running tally;
    %   - the subject panel: a lamp that lights while a sound plays, the
    %     RESPOND button (armed only while the response window is open), and
    %     the feedback;
    %   - the operator's settings: the trial structure (how many standards
    %     before a deviant, the silent interval, the response window) and the
    %     two sound banks, each changeable mid-session;
    %   - the displays: session performance, hit/false-alarm rate and d' over
    %     trials, hit rate by deviant sound and by the number of standards
    %     that preceded it, reaction times, and the trial history.
    %
    % THE GUI IS THE RIG. On a hardware rig a device would play the sound,
    % time the window, score the press and raise the completion flag. Here
    % this class does it on its own timer: each NewTrial starts a timeline
    % (silent interval, sound onset, response window); the outcome is
    % written as an epsych.BitMask code into RespCode with the reaction time
    % in RT_ms, and x_TrialComplete_1 is raised -- the flag
    % ep_TimerFcn_RunTime polls -- which completes the trial. WHICH sound to
    % play is not decided here: OddballSelector chose it and wrote it into
    % StimFile before the trial was dispatched.
    %
    % START, PAUSE, STOP. Start is the stock session gate: the constructor
    % holds until it is pressed (WaitForBegin), which under epsych.RunExpt
    % holds the whole trial loop. Pause and Resume broadcast the run mode --
    % Pause exactly as RunExpt's own Pause button does -- so every display
    % and RunExpt's mode lamp agree; RunExpt's Pause pauses this GUI too, and
    % Resume here resumes it. A pause takes effect at the next sound: a
    % response window already open is allowed to finish, and the silent
    % interval before the next sound starts over on Resume. Stop ends the
    % session through RunExpt's own Stop when RunExpt is running it, and
    % otherwise stops the session timer, whose stop function saves.
    %
    % Launch it in a real session by setting a project's Behavior GUI to
    % OddballBehaviorGUI (the class must be on the path), or without RunExpt
    % with run_oddball_experiment (same folder).
    %
    % Options (constructor):
    %   WaitForBegin - Hold the session at Start (default true). RunExpt
    %                  calls feval(name, RUNTIME), so the defaults are the
    %                  ones a real session needs.
    %   PlayAudio    - Play the sounds (default true). False runs the task
    %                  silently -- the lamp still marks every sound -- for a
    %                  headless test or a machine with no audio device.
    %
    % Public methods, so a script can do what the buttons do:
    %   respond, startSession, pauseSession, resumeSession,
    %   stopSession(Confirm=false), setBank("standard"|"deviant", files)
    %
    % See also gui.BehaviorGUI, OddballSelector, create_oddball_protocol,
    %   run_oddball_experiment

    properties (SetAccess = private)
        % Subject-facing
        StimLamp      matlab.ui.control.Lamp
        RespondButton matlab.ui.control.Button
        FeedbackLabel matlab.ui.control.Label
        TrialLabel    matlab.ui.control.Label
        % Operator-facing
        Gate          = []   % gui.components.SessionGate: the Start button
        PauseButton   matlab.ui.control.Button
        StopButton    matlab.ui.control.Button
        StatusLabel   matlab.ui.control.Label
        TallyLabel    matlab.ui.control.Label
        StandardList  matlab.ui.control.ListBox
        DeviantList   matlab.ui.control.ListBox

        % Second analysis, over RunLength: hit rate by how many standards
        % preceded the deviant. obj.Psych groups by deviant sound instead.
        RunLengthPsych = []

        IsStarted (1,1) logical = false
        IsPaused  (1,1) logical = false
        IsStopped (1,1) logical = false
    end

    properties (Access = private)
        RigTimer = []
        RigState (1,:) char = 'idle'   % idle | iti | stim | respwin | done
        StateClock = []                % tic for the current state
        StateDur (1,1) double = 0      % seconds the current state lasts
        StimClock = []                 % tic at sound onset: RT and the lamp run from it
        TrialIsDeviant (1,1) logical = false
        SoundDur (1,1) double = 0      % seconds
        LampIsOn (1,1) logical = false

        PlayAudio (1,1) logical = true
        AudioFailed (1,1) logical = false
        Player = []                    % audioplayer for the trial in hand
        PreviewPlayer = []             % audioplayer for the banks' Play buttons
        SoundCache = []                % containers.Map: file -> struct(y, fs)
    end

    properties (Constant, Access = private)
        LAMP_OFF = [0.25 0.25 0.25]
        LAMP_ON  = [1 0.85 0.1]
        MIN_LAMP_SEC = 0.1             % a very short sound still shows
        AUDIO_FILTER = {'*.wav;*.flac;*.ogg;*.mp3;*.m4a', 'Audio files'}
    end

    methods
        function obj = OddballBehaviorGUI(RUNTIME, options)
            % obj = OddballBehaviorGUI(RUNTIME, WaitForBegin=true, PlayAudio=true)
            arguments
                RUNTIME (1,1)
                options.WaitForBegin (1,1) logical = true
                options.PlayAudio (1,1) logical = true
            end

            obj@gui.BehaviorGUI(RUNTIME, Name = 'Oddball Detection', ...
                DefaultPosition = [60 60 1340 800]);
            obj.PlayAudio = options.PlayAudio;

            % After the base constructor, so the Start button exists to be
            % pressed. Closing the window during the wait deletes obj, which
            % is how the operator calls a run off before it starts. Only
            % when there is a session to hold: never in a review (blocking
            % would hang epsych.ReviewSession inside feval), and never over a
            % runtime with no trials yet -- epsych.SelfTest check I6 opens
            % this GUI that way and would wait forever.
            hasSession = false;
            try
                hasSession = isstruct(RUNTIME.TRIALS) && ~isempty(RUNTIME.TRIALS);
            catch
            end
            if options.WaitForBegin && ~obj.ReviewMode && hasSession
                obj.waitForSessionGate();
            end

            if nargout == 0, clear obj; end
        end

        function delete(obj)
            % The base class tears down listeners, registered components and
            % the figure; the rig timer and the players are this class's.
            try
                if ~isempty(obj.RigTimer) && isvalid(obj.RigTimer)
                    stop(obj.RigTimer);
                    delete(obj.RigTimer);
                end
            catch
            end
            try
                if ~isempty(obj.Player), stop(obj.Player); end
                if ~isempty(obj.PreviewPlayer), stop(obj.PreviewPlayer); end
            catch
            end
        end

        function respond(obj)
            % respond(obj)
            % The RESPOND button and the space bar. Ignored outside the
            % response window, so a late press after a deviant is lost
            % rather than counted against the standard that follows.
            if ~strcmp(obj.RigState, 'respwin'), return; end
            % The window's end is a time, not the tick that notices it: a
            % rig timer running late must not let a press after the window
            % count as a response.
            if toc(obj.StateClock) >= obj.StateDur
                obj.score_(false);
                return
            end
            obj.score_(true);
        end

        function startSession(obj)
            % startSession(obj)
            % Press Start: open the session gate.
            if ~isempty(obj.Gate) && isvalid(obj.Gate)
                obj.Gate.release();
            end
        end

        function pauseSession(obj)
            % pauseSession(obj)
            % Hold before the next sound. Broadcast as a run-mode change, the
            % same one RunExpt's Pause button sends, so this GUI's own
            % handler is the one place a pause takes effect.
            if ~obj.IsStarted || obj.IsPaused || obj.IsStopped || obj.ReviewMode, return; end
            epsych.SessionNotes.log(obj.RUNTIME, 'Session paused by the operator');
            obj.broadcastMode_(hw.DeviceState.Pause);
        end

        function resumeSession(obj)
            % resumeSession(obj)
            % Release a pause, whether this GUI or RunExpt paused it. The
            % silent interval before the next sound starts over.
            if ~obj.IsPaused || obj.IsStopped || obj.ReviewMode, return; end
            epsych.SessionNotes.log(obj.RUNTIME, 'Session resumed by the operator');
            obj.broadcastMode_(obj.runMode_());
        end

        function stopSession(obj, options)
            % stopSession(obj, Confirm=true)
            % End the session. Completed trials are kept; the trial in
            % progress, if any, is not recorded. Through RunExpt's own Stop
            % when RunExpt is running this session (mode broadcast, timer
            % stop, save); otherwise by stopping the session timer, whose
            % stop function winds the session up.
            arguments
                obj
                options.Confirm (1,1) logical = true
            end
            if obj.IsStopped || obj.ReviewMode, return; end

            if options.Confirm
                choice = uiconfirm(obj.h_figure, ...
                    'End the session now? Every completed trial is kept.', ...
                    'Stop Session', Options = {'Stop', 'Cancel'}, ...
                    DefaultOption = 'Cancel', CancelOption = 'Cancel', Icon = 'warning');
                if ~strcmp(choice, 'Stop'), return; end
            end

            epsych.SessionNotes.log(obj.RUNTIME, 'Session stopped by the operator');
            obj.stopRig_();

            rx = obj.drivingRunExpt_();
            if ~isempty(rx)
                rx.halt();
                return
            end
            t = [];
            try
                t = obj.RUNTIME.TIMER;
            catch
            end
            if ~isempty(t) && isa(t, 'timer') && isvalid(t) && strcmp(t.Running, 'on')
                stop(t);
            else
                obj.broadcastMode_(hw.DeviceState.Stop);
            end
        end

        function setBank(obj, which, files)
            % setBank(obj, which, files)
            % Replace a sound bank: which = "standard" or "deviant", files =
            % the audio files to draw from. Takes effect through
            % OddballSelector at the next selection: what was already played
            % stays as it was, a bank of the same size keeps its shuffled
            % order, and any other change starts at that bank's next block.
            % Recorded in the session notes.
            arguments
                obj
                which (1,1) string {mustBeMember(which, ["standard", "deviant"])}
                files (1,:) string
            end
            if obj.ReviewMode, return; end
            assert(~isempty(files), 'A sound bank needs at least one file.')
            for k = 1:numel(files)
                f = char(files(k));
                assert(isfile(f), 'No such file: %s', f)
                [~, attr] = fileattrib(f);
                files(k) = attr.Name;
                audioinfo(char(files(k))); % throws on a file that is not audio
            end

            p = obj.bankParameter_(which);
            assert(~isempty(p), 'This protocol has no %s bank parameter.', which)
            p.Value = cellstr(files);
            obj.refreshBankLists_();

            [~, names, ext] = fileparts(files);
            epsych.SessionNotes.log(obj.RUNTIME, '%s sounds set to %d file(s): %s', ...
                capitalize_(which), numel(files), strjoin(names + ext, ', '));
            obj.setStatus_(sprintf('%s bank: %d file(s), from the next block.', ...
                capitalize_(which), numel(files)));
        end
    end

    methods (Access = protected)
        function p = createPsych(obj, R)
            % Hit rate by deviant sound: deviants are TrialType 0 (the
            % stimulus), standards TrialType 1 (catch), and StimID says which
            % file of its bank a trial played. [] against a runtime without
            % the parameter (epsych.SelfTest check I6).
            p = [];
            if isfield(obj.P, 'StimID')
                p = psychophysics.Detection(R, obj.P.StimID);
            end
        end

        function build(obj, fig)
            obj.SoundCache = containers.Map('KeyType', 'char', 'ValueType', 'any');

            g = uigridlayout(fig, [2 3]);
            g.RowHeight   = {48, '1x'};
            g.ColumnWidth = {380, 320, '1x'};

            obj.buildTransport_(g);
            obj.buildSubjectAndBanks_(g);
            obj.buildSettings_(g);
            obj.buildDisplays_(g);

            obj.Keys.bind('space', @() obj.respond(), ...
                Description = 'Respond: that was a deviant', Group = 'Oddball');

            obj.refreshBankLists_();
            obj.updateTransport_();

            % The rig timer runs for the life of the window and does nothing
            % until a run mode arms the first trial. A review has no rig.
            if obj.ReviewMode
                obj.setStatus_('Reviewing a saved session.');
                return
            end
            obj.RigTimer = timer( ...
                Name = [obj.PreferenceTag '_rig'], ...
                Period = 0.01, ...
                ExecutionMode = 'fixedSpacing', ...
                BusyMode = 'drop', ...
                TimerFcn = @(~,~) obj.rigTick_(), ...
                ErrorFcn = @(~,evt) vprintf(0, 1, '%s rig timer error: %s', ...
                    class(obj), evt.Data.message));
            start(obj.RigTimer);
        end

        function onNewTrial(obj, ~, ~)
            % The runtime just dispatched the next trial; the selector had
            % already written its sound into StimFile. Start its timeline.
            if obj.IsStopped, return; end
            obj.beginTrial_();
        end

        function onModeChange(obj, ~, event)
            obj.applyMode_(event.NewMode);
        end

        function onNewData(obj, ~, ~)
            % obj.Psych ingested the completed trial before this hook ran.
            P = obj.Psych;
            if isempty(P) || ~isvalid(P) || isempty(P.DATA), return; end
            R = P.Results;
            obj.TallyLabel.Text = sprintf( ...
                'Hits %d   Misses %d   False alarms %d   Correct rejects %d', ...
                sum(R.N.Hit), sum(R.N.Miss), R.Catch.FalseAlarm, R.Catch.CorrectReject);
        end
    end

    methods (Access = private)
        % ---------------------------------------------------------------
        % Layout
        % ---------------------------------------------------------------
        function buildTransport_(obj, g)
            bar = uigridlayout(g, [1 6]);
            bar.Layout.Row = 1; bar.Layout.Column = [1 3];
            % The first column fits the gate's retired text, "Session Complete".
            bar.ColumnWidth = {180, 110, 110, 120, '1x', 'fit'};
            bar.Padding = [0 0 0 0];
            bar.ColumnSpacing = 8;

            % Start is the stock gate. It retires into a status line once
            % pressed, so the operator can always tell a session that is
            % waiting from one that is running or finished.
            if ~obj.ReviewMode
                obj.Gate = obj.add('gui.components.SessionGate', cell_(bar, 1, 1), ...
                    Text = 'Start', FontSize = 16, ...
                    Tooltip = 'Start presenting sounds; nothing plays until this is pressed');
            end

            obj.PauseButton = uibutton(bar, Text = 'Pause', FontSize = 16, ...
                FontWeight = 'bold', BackgroundColor = [1.00 0.80 0.20], ...
                Tooltip = 'Hold before the next sound', ...
                ButtonPushedFcn = @(~,~) obj.togglePause_());
            obj.PauseButton.Layout.Column = 2;

            obj.StopButton = uibutton(bar, Text = 'Stop', FontSize = 16, ...
                FontWeight = 'bold', FontColor = [1 1 1], BackgroundColor = [0.85 0.25 0.25], ...
                Tooltip = 'End the session; completed trials are kept', ...
                ButtonPushedFcn = @(~,~) obj.stopSession());
            obj.StopButton.Layout.Column = 3;

            obj.add('gui.components.ModeIndicator', cell_(bar, 1, 4), FontSize = 12);

            obj.StatusLabel = uilabel(bar, Text = 'Press Start when you are ready.', ...
                FontWeight = 'bold', FontSize = 13);
            obj.StatusLabel.Layout.Column = 5;

            obj.TallyLabel = uilabel(bar, Text = '', FontSize = 13, ...
                HorizontalAlignment = 'right');
            obj.TallyLabel.Layout.Column = 6;
        end

        function buildSubjectAndBanks_(obj, g)
            c = uigridlayout(g, [2 1]);
            c.Layout.Row = 2; c.Layout.Column = 1;
            c.RowHeight = {'1x', 290};
            c.Padding = [0 0 0 0];

            % --- Subject panel: what the "animal" sees -------------------
            % Nothing here says which kind of sound is coming: subject and
            % operator share one screen, and the lamp lights alike for both.
            pnl = uipanel(c, Title = 'Subject - that''s you: respond to the odd one out');
            sg = uigridlayout(pnl, [4 1]);
            sg.RowHeight = {'1x', 96, 44, 22};

            lampCell = uigridlayout(sg, [1 3]);
            lampCell.ColumnWidth = {'1x', 90, '1x'};
            lampCell.Padding = [0 0 0 0];
            obj.StimLamp = uilamp(lampCell, Color = obj.LAMP_OFF);
            obj.StimLamp.Layout.Column = 2;

            obj.RespondButton = uibutton(sg, Text = 'RESPOND', ...
                FontSize = 28, FontWeight = 'bold', Enable = 'off', ...
                Tooltip = 'Press (or hit the space bar) when you hear a deviant; armed during the response window', ...
                ButtonPushedFcn = @(~,~) obj.respond());

            obj.FeedbackLabel = uilabel(sg, Text = '', FontSize = 22, ...
                FontWeight = 'bold', HorizontalAlignment = 'center');

            obj.TrialLabel = uilabel(sg, Text = 'Waiting for Start', ...
                HorizontalAlignment = 'center', FontColor = [0.4 0.4 0.4]);

            % --- Sound banks ---------------------------------------------
            pnl = uipanel(c, Title = 'Sound Banks');
            pnl.Layout.Row = 2;
            bg = uigridlayout(pnl, [3 2]);
            bg.RowHeight = {18, '1x', 26};
            bg.Padding = [6 6 6 6];

            uilabel(bg, Text = 'Standards (withhold)', FontWeight = 'bold');
            uilabel(bg, Text = 'Deviants (respond)', FontWeight = 'bold');
            obj.StandardList = uilistbox(bg, Items = {}, ...
                Tooltip = 'Drawn block-randomized: each plays once before any repeats');
            obj.DeviantList = uilistbox(bg, Items = {}, ...
                Tooltip = 'Drawn block-randomized: each plays once before any repeats');

            for which = ["standard", "deviant"]
                row = uigridlayout(bg, [1 2]);
                row.Padding = [0 0 0 0];
                row.ColumnSpacing = 4;
                uibutton(row, Text = 'Choose...', Enable = ~obj.ReviewMode, ...
                    Tooltip = sprintf('Pick the %s .wav files', which), ...
                    ButtonPushedFcn = @(~,~) obj.chooseBank_(which));
                uibutton(row, Text = 'Play', ...
                    Tooltip = 'Listen to the selected sound (not while a trial is presenting)', ...
                    ButtonPushedFcn = @(~,~) obj.previewSound_(which));
            end
        end

        function buildSettings_(obj, g)
            c = uigridlayout(g, [2 1]);
            c.Layout.Row = 2; c.Layout.Column = 2;
            c.RowHeight = {205, '1x'};
            c.Padding = [0 0 0 0];

            % Staged edits, committed together by Update (or Ctrl+Enter).
            col = obj.controlColumn(c, Title = 'Trial Structure', Row = 1, Rows = 6);
            obj.addControl(col, 'MinStandards', Text = 'Fewest standards per deviant');
            obj.addControl(col, 'MaxStandards', Text = 'Most standards per deviant');
            obj.addControl(col, 'ITI', Type = 'range', Text = 'Silent interval (ms)');
            obj.addControl(col, 'RespWinDelay', Text = 'Window opens after (ms)');
            obj.addControl(col, 'RespWinDur', Text = 'Response window (ms)');
            obj.addUpdateButton(col);

            pnl = uipanel(c, Title = 'Session Performance');
            pnl.Layout.Row = 2;
            obj.add('gui.components.SessionPerformance', pnl);
        end

        function buildDisplays_(obj, g)
            c = uigridlayout(g, [2 1]);
            c.Layout.Row = 2; c.Layout.Column = 3;
            c.RowHeight = {'1.3x', '1x'};
            c.Padding = [0 0 0 0];

            tg = uitabgroup(c);
            tg.Layout.Row = 1;

            t = uitab(tg, Title = 'Performance over trials');
            obj.add('gui.components.SlidingWindowPerformancePlot', t);

            t = uitab(tg, Title = 'Hit rate by deviant');
            h = obj.add('gui.components.PsychPlot', t);
            if ~isempty(h), h.PlotType = 'HitRate'; end

            % A second Detection over RunLength: did a deviant get harder to
            % catch, or easier, the longer the run of standards before it?
            t = uitab(tg, Title = 'Hit rate by # standards');
            if isfield(obj.P, 'RunLength')
                try
                    obj.RunLengthPsych = psychophysics.Detection(obj.RUNTIME, obj.P.RunLength);
                    obj.register(obj.RunLengthPsych);
                    h = gui.components.PsychPlot(obj.RunLengthPsych, axes(t));
                    h.PlotType = 'HitRate';
                    obj.register(h, 'Hit Rate by Run Length');
                catch ME
                    vprintf(2, '%s: no run-length plot (%s)', class(obj), ME.message)
                end
            end

            t = uitab(tg, Title = 'Reaction times');
            obj.add('gui.components.ParameterScatter', t, ...
                XParameter = 'Trial Number', YParameter = 'RT_ms', ColorParameter = 'Response');

            pnl = uipanel(c, Title = 'Trial History');
            pnl.Layout.Row = 2;
            h = obj.add('gui.components.History', pnl);
            if ~isempty(h)
                % StimFile is a full path; StimID names the sound compactly.
                % A column choice the operator saved still wins.
                h.ParametersOfInterest = {'StimID', 'RunLength', 'RunPosition', 'RT_ms', 'ITI'};
            end
        end

        % ---------------------------------------------------------------
        % Session control
        % ---------------------------------------------------------------
        function applyMode_(obj, mode)
            % The one place a run mode takes effect, whoever broadcast it.
            switch mode
                case {hw.DeviceState.Record, hw.DeviceState.Preview}
                    if obj.IsStopped, return; end
                    obj.IsStarted = true;
                    obj.IsPaused  = false;
                    if mode == hw.DeviceState.Preview
                        obj.setStatus_('Preview running (test data). Respond to the odd one out.');
                    else
                        obj.setStatus_('Running. Respond to the odd one out.');
                    end
                    % Trial 1 was dispatched inside ep_TimerFcn_Start, before
                    % this window existed, so its NewTrial was never heard.
                    if strcmp(obj.RigState, 'idle')
                        obj.beginTrial_();
                    end

                case hw.DeviceState.Pause
                    if ~obj.IsStarted || obj.IsStopped, return; end
                    obj.IsPaused = true;
                    obj.setStatus_('PAUSED - press Resume to continue.');

                otherwise
                    if ~mode.isIdle(), return; end
                    obj.IsStopped = true;
                    obj.IsPaused  = false;
                    obj.stopRig_();
                    obj.setStatus_('Session ended.');
                    obj.TrialLabel.Text = 'Session ended';
            end
            obj.updateTransport_();
        end

        function togglePause_(obj)
            if obj.IsPaused
                obj.resumeSession();
            else
                obj.pauseSession();
            end
        end

        function updateTransport_(obj)
            live = obj.IsStarted && ~obj.IsStopped && ~obj.ReviewMode;
            obj.PauseButton.Enable = live;
            obj.StopButton.Enable  = live;
            if obj.IsPaused
                obj.PauseButton.Text = 'Resume';
                obj.PauseButton.BackgroundColor = [0.45 0.75 0.45];
                obj.PauseButton.Tooltip = 'Continue with the next sound';
            else
                obj.PauseButton.Text = 'Pause';
                obj.PauseButton.BackgroundColor = [1.00 0.80 0.20];
                obj.PauseButton.Tooltip = 'Hold before the next sound';
            end
        end

        function broadcastMode_(obj, mode)
            H = [];
            try
                H = obj.RUNTIME.EVENTS;
            catch
            end
            if ~isempty(H) && isvalid(H)
                H.notify('ModeChange', epsych.eventModeChange(mode));
            else
                obj.applyMode_(mode); % no session hub: act on it here alone
            end
        end

        function mode = runMode_(obj)
            mode = hw.DeviceState.Record;
            try
                if obj.RUNTIME.isTest, mode = hw.DeviceState.Preview; end
            catch
            end
        end

        function rx = drivingRunExpt_(obj)
            % The epsych.RunExpt running THIS session, or []. Same runtime
            % handle required, so a RunExpt window running something else is
            % never stopped from here.
            rx = [];
            try
                c = epsych.SelfTest.findActiveRunExpt();
                if ~isempty(c) && c.STATE == PRGMSTATE.RUNNING ...
                        && isa(c.RUNTIME, 'epsych.Runtime') && c.RUNTIME == obj.RUNTIME
                    rx = c;
                end
            catch ME
                vprintf(3, '%s: no RunExpt found (%s)', class(obj), ME.message)
            end
        end

        function setStatus_(obj, txt)
            if ~isempty(obj.StatusLabel) && isvalid(obj.StatusLabel)
                obj.StatusLabel.Text = txt;
            end
        end

        % ---------------------------------------------------------------
        % The rig: one trial = silent interval, sound, response window
        % ---------------------------------------------------------------
        function tf = rigReady_(obj)
            % Only against a runtime with this protocol, and never in a
            % review: this GUI writes parameters and raises
            % x_TrialComplete_1, which over a finished session would score
            % trials nobody ran. epsych.SelfTest opens it against a runtime
            % with no parameters at all.
            tf = ~obj.ReviewMode && ~obj.IsStopped ...
                && all(isfield(obj.P, {'TrialType', 'ITI', 'RespWinDelay', 'RespWinDur', ...
                    'StimFile', 'RespCode', 'RT_ms', 'InTrial', 'x_TrialComplete_1'})) ...
                && ~isempty(obj.RUNTIME.TRIALS) && isstruct(obj.RUNTIME.TRIALS);
        end

        function beginTrial_(obj)
            if ~obj.rigReady_(), return; end
            T = obj.RUNTIME.TRIALS(1);

            % The runtime never clears the completion flag; a stuck 1 would
            % complete a "trial" on every tick.
            obj.P.x_TrialComplete_1.Value = 0;

            row = T.NextTrialID;
            obj.TrialIsDeviant = T.trials{row, T.writeParamIdx.TrialType} == 0;

            % Never names the kind of sound: the subject reads this too.
            obj.TrialLabel.Text = sprintf('Trial %d', T.TrialIndex);
            obj.RespondButton.Enable = 'off';
            obj.setLamp_(false);
            setReadParameter_(obj.P.InTrial, true);

            % Load and arm the sound now, during the silent interval, so the
            % onset is a play() and not a file read.
            obj.prepareSound_(char(string(obj.P.StimFile.Value)));

            obj.setState_('iti', obj.paramMs_('ITI', 1000) / 1000);
        end

        function rigTick_(obj)
            % A window deleted without its close request (delete(fig),
            % close all force) never ran the teardown that stops this timer.
            if isempty(obj.h_figure) || ~isvalid(obj.h_figure)
                stop(obj.RigTimer);
                return
            end
            try
                switch obj.RigState
                    case 'iti'
                        if obj.IsPaused
                            obj.StateClock = tic; % hold; the full interval runs on Resume
                        elseif toc(obj.StateClock) >= obj.StateDur
                            obj.onset_();
                        end
                    case 'stim'
                        obj.updateLamp_();
                        if toc(obj.StimClock) >= obj.StateDur
                            obj.openWindow_();
                        end
                    case 'respwin'
                        obj.updateLamp_();
                        if toc(obj.StateClock) >= obj.StateDur
                            obj.score_(false);
                        end
                    otherwise
                        obj.updateLamp_(); % idle / done: only let the lamp go out
                end
            catch ME
                vprintf(0, 1, ME)
            end
        end

        function onset_(obj)
            obj.FeedbackLabel.Text = '';
            obj.StimClock = tic;
            obj.setLamp_(true);
            if ~isempty(obj.Player)
                try
                    play(obj.Player);
                catch ME
                    obj.audioFailed_(ME);
                end
            end
            delay = obj.paramMs_('RespWinDelay', 100) / 1000;
            obj.setState_('stim', delay);
            if delay <= 0
                obj.openWindow_();
            end
        end

        function openWindow_(obj)
            obj.RespondButton.Enable = 'on';
            obj.setState_('respwin', obj.paramMs_('RespWinDur', 1200) / 1000);
        end

        function score_(obj, responded)
            % The whole contingency:
            %                 responded            withheld
            %   deviant       Hit + Reward         Miss
            %   standard      FalseAlarm + Punish  CorrectReject
            % RT is from sound onset; -1 when there was no response, since a
            % parameter cannot hold NaN (see create_oddball_protocol).
            rt = -1;
            if responded
                rt = round(toc(obj.StimClock) * 1000);
            end

            if obj.TrialIsDeviant
                if responded, bits = [epsych.BitMask.Hit, epsych.BitMask.Reward];
                else,         bits = epsych.BitMask.Miss;
                end
                bits(end+1) = epsych.BitMask.TrialType_0;
            else
                if responded, bits = [epsych.BitMask.FalseAlarm, epsych.BitMask.Punish];
                else,         bits = epsych.BitMask.CorrectReject;
                end
                bits(end+1) = epsych.BitMask.TrialType_1;
            end

            obj.RespondButton.Enable = 'off';
            obj.showFeedback_(bits(1));

            rc = epsych.BitMask.Bits2Mask(uint32(bits));
            setReadParameter_(obj.P.RT_ms, rt);
            setReadParameter_(obj.P.RespCode, double(rc));
            setReadParameter_(obj.P.InTrial, false);

            % Hands the trial to the runtime: the next ep_TimerFcn_RunTime
            % tick records it, broadcasts NewData, selects and dispatches the
            % next trial -- whose NewTrial starts the next timeline here.
            obj.P.x_TrialComplete_1.Value = 1;
            obj.setState_('done', 0);
        end

        function stopRig_(obj)
            obj.setState_('idle', 0);
            if ~isempty(obj.RespondButton) && isvalid(obj.RespondButton)
                obj.RespondButton.Enable = 'off';
            end
            obj.setLamp_(false);
        end

        function showFeedback_(obj, outcomeBit)
            names = struct('Hit', 'HIT', 'Miss', 'MISS', ...
                'FalseAlarm', 'FALSE ALARM', 'CorrectReject', 'CORRECT REJECT');
            n = char(outcomeBit);
            if ~isfield(names, n), return; end
            obj.FeedbackLabel.Text = names.(n);
            obj.FeedbackLabel.FontColor = epsych.BitMask.getDefaultColors(outcomeBit);
        end

        function setState_(obj, name, durSec)
            obj.RigState = name;
            obj.StateClock = tic;
            obj.StateDur = durSec;
        end

        function updateLamp_(obj)
            if obj.LampIsOn && ~isempty(obj.StimClock) ...
                    && toc(obj.StimClock) >= max(obj.SoundDur, obj.MIN_LAMP_SEC)
                obj.setLamp_(false);
            end
        end

        function setLamp_(obj, on)
            obj.LampIsOn = on;
            if isempty(obj.StimLamp) || ~isvalid(obj.StimLamp), return; end
            if on
                obj.StimLamp.Color = obj.LAMP_ON;
            else
                obj.StimLamp.Color = obj.LAMP_OFF;
            end
        end

        function ms = paramMs_(obj, name, fallback)
            % A live GUI must not stall on a value read mid-dispatch, so
            % anything unusable degrades to the fallback.
            ms = fallback;
            try
                v = obj.P.(name).Value;
                if isscalar(v) && isfinite(v) && v >= 0
                    ms = double(v);
                end
            catch
            end
        end

        % ---------------------------------------------------------------
        % Sound
        % ---------------------------------------------------------------
        function prepareSound_(obj, file)
            obj.Player = [];
            obj.SoundDur = 0;
            if isempty(file), return; end
            s = obj.loadSound_(file);
            if isempty(s), return; end
            obj.SoundDur = size(s.y, 1) / s.fs;
            if ~obj.PlayAudio || obj.AudioFailed, return; end
            try
                obj.Player = audioplayer(s.y, s.fs);
            catch ME
                obj.audioFailed_(ME);
            end
        end

        function s = loadSound_(obj, file)
            % Cached by path: a bank is a handful of short files played over
            % and over, and the read belongs in the silent interval only once.
            s = [];
            if isKey(obj.SoundCache, file)
                s = obj.SoundCache(file);
                return
            end
            try
                [y, fs] = audioread(file);
                s = struct('y', y, 'fs', fs);
                obj.SoundCache(file) = s;
            catch ME
                vprintf(0, 1, '%s: cannot read sound "%s": %s', class(obj), file, ME.message)
            end
        end

        function audioFailed_(obj, ME)
            % No audio device (a remote session, a headless machine): say so
            % once and carry on silently; the lamp still marks every sound.
            if obj.AudioFailed, return; end
            obj.AudioFailed = true;
            obj.Player = [];
            vprintf(0, 1, '%s: audio playback failed, continuing without sound: %s', ...
                class(obj), ME.message)
            obj.setStatus_('Audio playback failed - the lamp still marks each sound.');
        end

        function previewSound_(obj, which)
            if ismember(obj.RigState, {'stim', 'respwin'})
                obj.setStatus_('Not while a trial is presenting - Pause first.');
                return
            end
            lst = obj.bankList_(which);
            file = lst.Value;
            if isempty(file) || ~(ischar(file) || isstring(file))
                return
            end
            s = obj.loadSound_(char(file));
            if isempty(s) || ~obj.PlayAudio || obj.AudioFailed, return; end
            try
                obj.PreviewPlayer = audioplayer(s.y, s.fs);
                play(obj.PreviewPlayer);
            catch ME
                obj.audioFailed_(ME);
            end
        end

        function chooseBank_(obj, which)
            p = obj.bankParameter_(which);
            if isempty(p), return; end
            current = OddballSelector.bankFiles(p);
            startIn = pwd;
            if ~isempty(current), startIn = fileparts(current{1}); end
            [fn, pn] = uigetfile(obj.AUDIO_FILTER, ...
                sprintf('Choose the %s sounds', which), [startIn filesep], ...
                'MultiSelect', 'on');
            figure(obj.h_figure); % uigetfile leaves focus elsewhere
            if isequal(fn, 0), return; end
            files = fullfile(pn, string(fn));
            try
                obj.setBank(which, files);
            catch ME
                uialert(obj.h_figure, ME.message, 'Sound Bank Not Changed');
            end
        end

        function refreshBankLists_(obj)
            for which = ["standard", "deviant"]
                lst = obj.bankList_(which);
                p = obj.bankParameter_(which);
                files = {};
                if ~isempty(p), files = OddballSelector.bankFiles(p); end
                [~, names, ext] = fileparts(string(files));
                lst.Items = cellstr(names + ext);
                lst.ItemsData = files;
                if ~isempty(files), lst.Value = files{1}; end
            end
        end

        function lst = bankList_(obj, which)
            if which == "standard"
                lst = obj.StandardList;
            else
                lst = obj.DeviantList;
            end
        end

        function p = bankParameter_(obj, which)
            % Invisible parameters, so not in obj.P; ask the runtime.
            names = struct('standard', 'StandardFiles', 'deviant', 'DeviantFiles');
            p = [];
            try
                p = obj.RUNTIME.find_parameter(names.(char(which)), ...
                    includeInvisible = true, silenceParameterNotFound = true);
            catch
            end
            if ~isempty(p), p = p(1); end
        end
    end
end


function c = cell_(parent, row, col)
% A borderless one-cell grid at a fixed position, for a component that
% builds into whatever container it is given and would otherwise take the
% next free cell of the parent grid.
c = uigridlayout(parent, [1 1]);
c.Layout.Row = row;
c.Layout.Column = col;
c.Padding = [0 0 0 0];
end


function s = capitalize_(s)
s = char(s);
s(1) = upper(s(1));
end


function setReadParameter_(p, val)
% Rig-side write to a read-back parameter: Access='Read' blocks set.Value,
% so widen access for the write and restore it. This GUI stands in for the
% rig, the only writer such a parameter has.
if isempty(p), return; end
ac = p.Access;
p.Access = 'Any';
p.Value = val;
p.Access = ac;
end
