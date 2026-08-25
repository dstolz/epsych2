classdef PumpBehaviorGUI < gui.BehaviorGUI
    %PUMPBEHAVIORGUI Minimal behavior GUI for exercising the gui.components.SyringePump panel.
    %   A gui.components.SyringePump operator panel beside the two things needed to see
    %   whether it behaves during a session: the trial controls that write
    %   the same pump, and a readout of the reward volume the pump reported
    %   back on every completed trial.
    %
    %   Launch it from a session by naming this class as a project's Behavior GUI
    %   (Subjects > Subjects & Projects, Project > Edit Project...); or run it
    %   without hardware with run_pump_session.
    %
    %   Trials do not start on their own: the window opens with a Begin
    %   Experiment button and the session holds until it is pressed, under
    %   RunExpt's Run / Preview buttons as well as run_pump_session.
    %
    %   The button is a gui.components.SessionGate (obj.addSessionGate) and the hold is
    %   the CONSTRUCTOR blocking on it. RunExpt builds the behavior GUI from
    %   the PsychTimer's StartFcn, start() does not return until that
    %   callback does, and a timer will not fire its TimerFcn during another
    %   of its own callbacks — so blocking here holds the trial loop. Pass
    %   WaitForBegin=false to skip the gate (headless tests, or a caller
    %   doing its own waiting).
    %
    %   Once released, THIS GUI runs the trial cycle, the way
    %   FirstExperimentBehaviorGUI and TwoAFCBehaviorGUI do for their
    %   paradigms: the runtime's trial loop only writes the dispatched
    %   Volume and Rate to the pump and then polls x_TrialComplete_1, so
    %   something has to pulse Start and decide when the trial is over. On
    %   every dispatch this GUI clears that flag, pulses the pump, waits out
    %   the dispense and then the trial's ITI, and raises the flag again —
    %   which is what makes the runtime collect the pump's read-back into
    %   DATA and dispatch the next reward. Pass DriveTrials=false for a
    %   caller that runs its own loop (run_pump_session does).
    %
    % See also gui.components.SyringePump, run_pump_session, create_pump_protocol,
    %          documentation/gui/gui_SyringePump.md

    properties (SetAccess = private)
        Pump = []       % the gui.components.SyringePump panel under test
        RigState (1,:) char = 'idle' % idle | dispense | iti | done
    end

    properties (Dependent, SetAccess = private)
        BeginRequested (1,1) logical % the session has been released to run
    end

    properties (Access = private)
        LastVolumeH_ = []   % per-trial dispensed-volume label
        StateH_ = []        % what the trial cycle is doing right now
        PrevInfused_ = NaN  % VolumeInfused at the previous trial end
        Gate_ = []          % gui.components.SessionGate holding the session
        DriveTrials_ (1,1) logical = true % run the trial cycle from here
        RigTimer_ = []      % advances the trial cycle off the session timer
        StateClock_ = []    % tic handle for the current state
        StateDur_ (1,1) double = 0 % seconds the current state should last
        LastStatusPoll_ = []       % tic since the pump was last asked for Status
    end

    properties (Constant, Access = private)
        % The pump is asked whether it is still running no more often than
        % this. Each ask is an RS-232 round trip, and gui.components.SyringePump is
        % already polling the same link four times a second.
        STATUS_POLL_PERIOD = 0.25
    end

    methods
        function obj = PumpBehaviorGUI(RUNTIME, options)
            % obj = PumpBehaviorGUI(RUNTIME, WaitForBegin=true, DriveTrials=true)
            % Open the window and hold the session at the Begin Experiment
            % button. RunExpt calls this as feval(FUNCS.BehaviorGUI, RUNTIME),
            % so both defaults have to be the ones an operator's session needs.
            arguments
                RUNTIME (1,1)
                options.WaitForBegin (1,1) logical = true
                options.DriveTrials (1,1) logical = true
            end

            obj@gui.BehaviorGUI(RUNTIME, Name = 'Syringe Pump Test Box', ...
                DefaultPosition = [100 100 1120 560]);

            obj.DriveTrials_ = options.DriveTrials;

            % After the base constructor, so the button and its listeners
            % exist to be pressed. Closing the window during the wait deletes
            % obj, which every line below has to tolerate.
            %
            % Never in a review: the wait exists to hold a starting session
            % until the operator is at the box, and there is no session here to
            % hold. Blocking would hang epsych.ReviewSession inside feval, with
            % a half-built window and no way to reach the Begin button.
            if options.WaitForBegin && ~obj.ReviewMode
                obj.waitForBegin();
            end

            if nargout == 0, clear obj; end
        end

        function delete(obj)
            % The base class tears down listeners, registered components and
            % the figure; the rig timer is this class's to stop. A timer left
            % running would keep pulsing a pump whose window is gone.
            try
                if ~isempty(obj.RigTimer_) && isvalid(obj.RigTimer_)
                    stop(obj.RigTimer_);
                    delete(obj.RigTimer_);
                end
            catch ME
                vprintf(2, '%s: rig timer teardown: %s', class(obj), ME.message)
            end
        end

        function tf = get.BeginRequested(obj)
            tf = ~isempty(obj.Gate_) && isvalid(obj.Gate_) && obj.Gate_.Released;
        end

        function beginExperiment(obj)
            % beginExperiment(obj)
            % Release a session waiting in waitForBegin. This is what the
            % Begin Experiment button does; calling it by hand is how a
            % script starts the run without a click.
            if isempty(obj.Gate_) || ~isvalid(obj.Gate_), return; end
            obj.Gate_.release();
        end

        function tf = waitForBegin(obj, timeout)
            % tf = waitForBegin(obj, timeout)
            % Block until the operator presses Begin Experiment, returning
            % whether the session was released. Closing the window is the
            % operator's way of calling the run off, and returns false.
            %  timeout - seconds to wait. Default Inf.
            %
            % Kept as a name of this class's own because run_pump_session and
            % the smoke tests call it; it is gui.BehaviorGUI.waitForSessionGate
            % underneath, which is what any other paradigm should use.
            arguments
                obj
                timeout (1,1) double {mustBePositive} = Inf
            end
            tf = obj.waitForSessionGate(timeout);
        end
    end

    methods (Access = protected)

        function build(obj, fig)
            g = uigridlayout(fig, [2 3]);
            g.ColumnWidth = {320, 260, '1x'};
            g.RowHeight   = {'1x', 170};

            % --- The component under test --------------------------------
            % Options the build method does not state fall back to whatever
            % the operator left behind last session, so only what this
            % paradigm actually cares about is passed. With no pump in the
            % protocol the panel makes an offline interface of its own and
            % offers a port to connect on, so this GUI still opens.
            %
            % The units are stated because this protocol is authored in
            % uL/min (create_pump_protocol) rather than the panel's default
            % mL/min: the panel puts the interface into the units it
            % displays, so leaving it to the default would have the trial
            % table's Rate column and the panel mean different things. The
            % operator can still switch units from the panel's right-click
            % menu, which converts the rate rather than reinterpreting it.
            pnl = uipanel(g, 'Title', 'Reward Pump');
            pnl.Layout.Row = [1 2];
            pnl.Layout.Column = 1;
            obj.Pump = obj.addSyringePump(pnl, Rate = 1000, Diameter = 21.59, ...
                RateUnits = 'UM', VolumeUnits = 'uL');

            % --- Trial controls ------------------------------------------
            % Rate is a trial-table column, so it is re-asserted on every
            % dispatch. autoCommit writes the operator's edit into the trial
            % table as well as the pump (gui.components.Parameter_Control's Runtime
            % option), which is what keeps the next dispatch from undoing it.
            col = obj.controlColumn(g, Title = 'Trial Controls', Row = 1, Column = 2);

            % Nothing is dispensed until this is pressed. The syringe has
            % to be seated and the line purged before the first reward, and
            % none of that is done by the time the window opens — so the
            % first thing in the column is the gate, and the pump panel
            % beside it stays live while the operator primes.
            obj.Gate_ = obj.addSessionGate(col);
            col.RowHeight{1} = 36;

            obj.addControl(col, 'Rate', autoCommit = true, Text = 'Pump Rate (uL/min)');
            obj.addControl(col, 'ITI',  Text = 'Intertrial Interval (s)');
            obj.addUpdateButton(col);

            obj.LastVolumeH_ = uilabel(col, ...
                'Text', 'No trials yet', ...
                'HorizontalAlignment', 'center', ...
                'FontColor', [0.35 0.35 0.35]);

            % Says which half of the trial cycle is running. Without it a
            % correctly-paced session and a stalled one look identical: both
            % are a window with a still pump in front of them.
            obj.StateH_ = uilabel(col, ...
                'Text', 'Waiting for session start...', ...
                'HorizontalAlignment', 'center', ...
                'FontColor', [0.35 0.35 0.35]);

            % --- Upcoming trial ------------------------------------------
            pnl = uipanel(g, 'Title', 'Next Trial');
            pnl.Layout.Row = 2;
            pnl.Layout.Column = 2;
            obj.addNextTrial(pnl, Fields = ["Volume", "Rate"], FontSize = 14);

            % --- What the pump reported back ------------------------------
            % VolumeInfused is Visible + Access='Read', so the runtime's
            % trial-end sweep queries the pump and lands the accumulated
            % volume in DATA. Plotting it is the proof that path works.
            pnl = uipanel(g, 'Title', 'Cumulative Volume Infused');
            pnl.Layout.Row = 1;
            pnl.Layout.Column = 3;
            obj.register(gui.components.ParameterScatter(obj.RUNTIME, pnl, ...
                XParameter = 'Trial Number', YParameter = 'VolumeInfused'));

            pnl = uipanel(g, 'Title', 'Pump Readback');
            pnl.Layout.Row = 2;
            pnl.Layout.Column = 3;
            obj.addMonitor(pnl, {'Volume', 'VolumeInfused', 'VolumeWithdrawn'}, ...
                pollPeriod = 1);

            % --- The clock the trial cycle runs on ------------------------
            % Its own timer rather than the session timer: the session timer
            % is inside ep_TimerFcn_RunTime when it calls this GUI, and a
            % dispense that has to outlast that callback cannot be waited for
            % from within it. fixedSpacing + drop so a slow serial reply
            % delays the next tick instead of queueing more of them.
            % A review has no pump to drive and no trial to hand back, so the
            % cycle clock never starts.
            if obj.ReviewMode
                return
            end

            obj.RigTimer_ = timer( ...
                Name = [obj.PreferenceTag '_rig'], ...
                Period = 0.05, ...
                ExecutionMode = 'fixedSpacing', ...
                BusyMode = 'drop', ...
                TimerFcn = @(~,~) obj.rigTick_(), ...
                ErrorFcn = @(~,evt) vprintf(0, 1, '%s rig timer error: %s', ...
                    class(obj), evt.Data.message));
            start(obj.RigTimer_);
        end

        function onNewTrial(obj, ~, ~)
            % The runtime has dispatched the next condition, so the pump is
            % already loaded with this trial's Volume and Rate. Run its
            % timeline.
            obj.beginTrial_();
        end

        function onNewData(obj, ~, ~)
            % Report the volume this trial actually cost. The pump's
            % accumulators reset on power-up, a diameter change, and at 9999,
            % so the trustworthy quantity is the DIFFERENCE between trials —
            % never the absolute value.
            D = obj.RUNTIME.TRIALS(1).DATA;
            if isempty(D) || ~isfield(D, 'VolumeInfused'), return; end

            infused = D(end).VolumeInfused;
            if ~(isnumeric(infused) && isscalar(infused))
                return  % no volume came back for this trial; leave the label alone
            end

            if isnan(obj.PrevInfused_) || infused < obj.PrevInfused_
                delta = NaN;    % first trial, or the accumulators were zeroed
            else
                delta = infused - obj.PrevInfused_;
            end
            obj.PrevInfused_ = infused;

            if isnan(delta)
                txt = sprintf('Trial %d: %.3f mL total', numel(D), infused);
            else
                txt = sprintf('Trial %d: %.0f uL delivered (%.3f mL total)', ...
                    numel(D), delta * 1000, infused);
            end
            obj.LastVolumeH_.Text = txt;
        end

        function onModeChange(obj, ~, event)
            % Retiring the button belongs to gui.components.SessionGate, which is
            % listening to the same event and was wired first (build runs
            % inside the base constructor, before these hooks are attached),
            % so the gate has already opened by the time this runs. What is
            % left here is the rig.
            if any(event.NewMode == [hw.DeviceState.Record, hw.DeviceState.Preview])
                % Trial 1 was dispatched before this window existed (the
                % TRIALS setter dispatches it from inside ep_TimerFcn_Start),
                % so its NewTrial event was never heard here. Start its
                % timeline now; every later trial arrives through onNewTrial.
                if strcmp(obj.RigState, 'idle')
                    obj.beginTrial_();
                end
            elseif event.NewMode.isIdle()
                obj.stopRig_();
            end
        end

    end

    methods (Access = private)

        % --- The trial cycle -------------------------------------------------
        % The runtime writes the reward size and then waits: it polls
        % x_TrialComplete_1 and does nothing else until it goes high. These
        % four methods are the other half of that contract — pulse the pump,
        % wait out the dispense, wait out the ITI, raise the flag.

        function beginTrial_(obj)
            % Start the dispatched trial: pulse the pump and time the dispense.
            if ~obj.DriveTrials_ || ~obj.rigReady_(), return; end

            % Handing the completion flag back to 0 is this GUI's half of the
            % polling contract: the runtime never clears it, and a flag left
            % high would complete a "trial" on every timer tick.
            obj.P.x_TrialComplete_1.Value = 0;

            [vol, rate] = obj.trialReward_();
            iface = obj.pumpInterface_();

            if isempty(iface) || ~iface.IsConnected
                % A pump left offline for the session (hw.Interface's
                % RunOffline) still gets its trials: the transactions no-op,
                % so the session paces normally with nothing dispensed.
                obj.setState_('dispense', 0);
                return
            end

            vprintf(1, 'Trial %d: dispensing %.3f %s at %.4g %s', ...
                obj.RUNTIME.TRIALS(1).TrialIndex, vol, obj.volumeUnit_(), ...
                rate, obj.rateUnit_())
            iface.trigger('Start');
            obj.LastStatusPoll_ = [];
            obj.setState_('dispense', obj.expectedDispense_(vol, rate));
        end

        function rigTick_(obj)
            % One pass of the trial cycle. Never pauses or drawnows: this
            % runs on a timer alongside the panel's 4 Hz readout and the
            % session timer, and yielding here would let them re-enter the
            % same serial link mid-transaction.
            if ~isvalid(obj), return; end
            try
                switch obj.RigState
                    case 'dispense'
                        if obj.stillDispensing_(), return; end
                        % The reward has been delivered; hold the intertrial
                        % interval the dispatch just drew into ITI (isRandom
                        % redraws it every trial) before ending the trial.
                        iti = obj.itiSeconds_();
                        obj.setState_('iti', iti);
                    case 'iti'
                        if toc(obj.StateClock_) < obj.StateDur_, return; end
                        obj.completeTrial_();
                end
            catch ME
                % An uncaught error in a TimerFcn stops the timer, which
                % would strand the session waiting on a flag nothing will
                % raise. Report and leave the cycle idle instead.
                vprintf(0, 1, ME);
                obj.stopRig_();
            end
        end

        function tf = stillDispensing_(obj)
            % Whether the pump is still pushing. The expected duration comes
            % first because it costs nothing; only after it has elapsed is
            % the pump asked, and then no faster than STATUS_POLL_PERIOD.
            % A pump given a non-zero Volume stops itself, so nothing here
            % ever issues a Stop that would truncate the dispense.
            tf = toc(obj.StateClock_) < obj.StateDur_;
            if tf, return; end

            iface = obj.pumpInterface_();
            if isempty(iface) || ~iface.IsConnected, return; end

            if ~isempty(obj.LastStatusPoll_) && toc(obj.LastStatusPoll_) < obj.STATUS_POLL_PERIOD
                tf = true;      % too soon to ask again; stay in the state
                return
            end
            obj.LastStatusPoll_ = tic;

            % strcmp, not ismember: a pump that misses a query answers with
            % something ismember cannot compare against the cell.
            tf = any(strcmp(iface.get_parameter('Status'), {'Infusing', 'Withdrawing'}));

            % Give up rather than hang the session. Overrunning by this much
            % means the syringe, the Volume or the rate units are wrong —
            % all of which the operator has to see to fix.
            if tf && toc(obj.StateClock_) > 3 * obj.StateDur_ + 2
                vprintf(0, 1, ['Pump still running %.1f s after Start — ' ...
                    'check the syringe and Volume. Ending the trial anyway.'], ...
                    toc(obj.StateClock_))
                tf = false;
            end
        end

        function completeTrial_(obj)
            % Raising the completion flag hands the trial back: the next
            % ep_TimerFcn_RunTime tick collects the Read parameters (the
            % pump's dispensed volumes among them) into DATA, journals them,
            % broadcasts NewData, and dispatches the next reward — which
            % arrives here as onNewTrial.
            obj.setState_('done', 0);
            obj.P.x_TrialComplete_1.Value = 1;
        end

        function stopRig_(obj)
            % The session is over. A trial caught mid-dispense must not be
            % left with the pusher advancing: the runtime has stopped
            % collecting trials, so nothing downstream would ever notice.
            % Only from 'dispense' — a second Stop resets the pump's Pumping
            % Program, and there is no reason to send one to a still pump.
            wasDispensing = strcmp(obj.RigState, 'dispense');
            obj.setState_('idle', 0);
            if ~wasDispensing, return; end

            iface = obj.pumpInterface_();
            if isempty(iface) || ~iface.IsConnected, return; end
            iface.trigger('Stop');
        end

        function setState_(obj, name, durSec)
            obj.RigState = name;
            obj.StateClock_ = tic;
            obj.StateDur_ = durSec;

            if isempty(obj.StateH_) || ~isvalid(obj.StateH_), return; end
            switch name
                case 'dispense', txt = 'Dispensing reward...';
                case 'iti',      txt = sprintf('Intertrial interval (%.1f s)', durSec);
                case 'done',     txt = 'Trial complete';
                otherwise,       txt = 'Idle';
            end
            obj.StateH_.Text = txt;
        end

        % --- What the trial cycle needs to know ------------------------------

        function tf = rigReady_(obj)
            % The cycle can only run against a runtime that actually has this
            % protocol loaded: the pre-flight SelfTest opens behavior GUIs
            % against a synthetic runtime with no parameters at all.
            %
            % A review is the other case where it must not run. The cycle
            % dispenses reward and hands the trial back by raising
            % x_TrialComplete_1, which against a finished session would mean a
            % pump running for trials nobody is present for. The base class
            % cannot decide this for a subclass, so every rig-driving GUI has
            % to say so here. See gui.BehaviorGUI.ReviewMode.
            if obj.ReviewMode
                tf = false;
                return
            end

            tf = isfield(obj.P, 'x_TrialComplete_1') ...
                && ~isempty(obj.RUNTIME.TRIALS) && isstruct(obj.RUNTIME.TRIALS);
        end

        function iface = pumpInterface_(obj)
            % The hw.NE1000 the panel drives, which is the session's pump
            % when the protocol has one (gui.components.SyringePump adopts it) and the
            % panel's own otherwise.
            iface = [];
            if ~isempty(obj.Pump) && isvalid(obj.Pump) && ~isempty(obj.Pump.Interface) ...
                    && isvalid(obj.Pump.Interface)
                iface = obj.Pump.Interface;
            end
        end

        function [vol, rate] = trialReward_(obj)
            % This trial's reward, taken from the trial table rather than
            % read back over RS-232: the dispatch has already written both to
            % the pump, and an operator edit committed with autoCommit lands
            % in the same table.
            T = obj.RUNTIME.TRIALS(1);
            vol  = obj.trialColumn_(T, 'Volume', 0);
            rate = obj.trialColumn_(T, 'Rate', 0);
        end

        function v = trialColumn_(~, T, name, dflt)
            v = dflt;
            if ~isfield(T.writeParamIdx, name), return; end
            raw = T.trials{T.NextTrialID, T.writeParamIdx.(name)};
            if isnumeric(raw) && isscalar(raw) && isfinite(raw), v = double(raw); end
        end

        function s = expectedDispense_(obj, vol, rate)
            % Seconds one Start pulse should take. Volume and Rate are in
            % DIFFERENT units and neither is fixed: the pump reports volumes
            % in uL below a 14 mm syringe and mL at or above, while the rate
            % carries whatever units the interface was put into. Assuming
            % mL and uL/min here is what would make the dispense wait
            % 1000x too short (or long) on a small syringe.
            volUL = vol;
            if ~strcmp(obj.volumeUnit_(), 'uL'), volUL = vol * 1000; end

            iface = obj.pumpInterface_();
            units = 'UM';
            if ~isempty(iface), units = iface.RateUnits; end
            switch units
                case 'UM', rateULperMin = rate;             % uL/min
                case 'MM', rateULperMin = rate * 1000;      % mL/min
                case 'UH', rateULperMin = rate / 60;        % uL/hr
                otherwise, rateULperMin = rate * 1000 / 60; % mL/hr
            end

            s = 60 * volUL / max(rateULperMin, eps);
            if ~isfinite(s) || s < 0, s = 0; end
        end

        function u = volumeUnit_(obj)
            % The pump reports volumes in uL below a 14 mm syringe diameter
            % and in mL at or above it.
            u = 'mL';
            iface = obj.pumpInterface_();
            if ~isempty(iface) && iface.SyringeDiameter > 0 && iface.SyringeDiameter < 14
                u = 'uL';
            end
        end

        function u = rateUnit_(obj)
            iface = obj.pumpInterface_();
            u = 'uL/min';
            if isempty(iface), return; end
            switch iface.RateUnits
                case 'UM', u = 'uL/min';
                case 'MM', u = 'mL/min';
                case 'UH', u = 'uL/hr';
                otherwise, u = 'mL/hr';
            end
        end

        function s = itiSeconds_(obj)
            % The interval the dispatch drew for this trial. Software
            % parameter, so reading it costs nothing.
            s = 2;
            if ~isfield(obj.P, 'ITI'), return; end
            v = obj.P.ITI.Value;
            if isnumeric(v) && isscalar(v) && isfinite(v) && v >= 0, s = double(v); end
        end

    end
end
