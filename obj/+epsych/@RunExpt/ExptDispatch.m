function ExptDispatch(self, COMMAND)
% ExptDispatch — Core state dispatcher for run/preview/stop.
% Inputs
%   COMMAND (string) — "Run"|"Record"|"Preview"|"Stop".
% Behavior
%   Prepares RUNTIME, loads protocols, initializes hardware,
%   configures/starts the PsychTimer, and manages Stop/cleanup.
arguments
    self
    COMMAND {mustBeTextScalar}
end

COMMAND = string(COMMAND);
switch lower(COMMAND)
    case {"run","record"}, COMMAND = "Record";
    case "preview",        COMMAND = "Preview";
end

switch COMMAND
    case {"Record","Preview"}
        drawnow

        % Set process priority to high for this MATLAB instance only
        [~,~] = dos(sprintf('wmic process where processid="%d" CALL setpriority "high priority"', feature('getpid')));

        vprintf(0,'%s',repmat('~',1,50))

        if COMMAND == "Preview"
            self.setStatus('Preparing preview (test run; no data will be saved)...')
        else
            self.setStatus('Preparing session...')
        end

        self.RUNTIME = epsych.Runtime; % reset RUNTIME
        self.RUNTIME.isTest = COMMAND == "Preview";

        % Each subject's parameter defaults go onto its protocol before it is
        % validated and compiled, so the trial table -- and the first trial --
        % carry them. Read from the roster now rather than at commit, so an
        % edit made since the subject was added counts.
        defaultsChanged = self.applyParameterDefaults_();

        % Validate embedded protocols
        for i = 1:length(self.CONFIG)
            assert(isa(self.CONFIG(i).PROTOCOL, 'epsych.Protocol') && isvalid(self.CONFIG(i).PROTOCOL), ...
                'epsych:RunExpt:MissingProtocol', ...
                'CONFIG(%d) does not contain a valid epsych.Protocol object. Add subjects with a protocol before starting.', i);

            report = self.CONFIG(i).PROTOCOL.validate();
            if ~isempty(report)
                errs = report([report.severity] == 2);
                if ~isempty(errs)
                    msgs = strjoin(arrayfun(@(r) sprintf('[%s] %s', r.field, r.message), errs, 'UniformOutput', false), newline);
                    error('epsych:RunExpt:ProtocolValidationFailed', ...
                        'Protocol for subject "%s" has validation errors:\n%s', ...
                        self.CONFIG(i).SUBJECT.Name, msgs);
                end
            end

            % needsCompile compares the file's save time with the last
            % compile, so it cannot see Values changed in memory; a subject
            % whose defaults changed anything is compiled regardless.
            if defaultsChanged(i) || self.CONFIG(i).PROTOCOL.needsCompile
                vprintf(0, 'Compiling protocol for subject "%s"...', self.CONFIG(i).SUBJECT.Name);
                self.setStatus(sprintf('Compiling protocol for subject "%s"...', ...
                    self.CONFIG(i).SUBJECT.Name))
                self.CONFIG(i).PROTOCOL.compile();
            end

            pfn = string(self.CONFIG(i).protocol_fn);
            if strlength(pfn) > 0 && isfile(pfn)
                [pn, fn] = fileparts(pfn);
                vprintf(0, ['%2d. ''%s''\tProtocol: ', ...
                    '<a href="matlab: epsych.ProtocolDesigner.openFromFile(''%s'');">%s</a>' ...
                    '(<a href="matlab: !explorer %s">%s</a>)'], ...
                    self.CONFIG(i).SUBJECT.BoxID, self.CONFIG(i).SUBJECT.Name, pfn, fn, pn, pn)
            else
                vprintf(0, '%2d. ''%s''\tProtocol: <embedded>', ...
                    self.CONFIG(i).SUBJECT.BoxID, self.CONFIG(i).SUBJECT.Name)
            end
        end


        % connect hardware interfaces
        self.setStatus('Connecting hardware interfaces...')
        try
            % Get hardware interfaces from loaded protocol
            % If protocol was designed with Software only, create minimal hardware
            protocol_interfaces = self.CONFIG(1).PROTOCOL.Interfaces;

            % Phase saves serialize this protocol (writeParametersProtocol).
            % Interfaces come from subject 1's protocol, so phases snapshot
            % that protocol as well.
            self.RUNTIME.Protocol = self.CONFIG(1).PROTOCOL;
            % The file it came from, for bringing phases up to its version
            % (Runtime.updatePhase): the design lives in the file, the live
            % object also carries this session's edits.
            % char() first: an embedded protocol's protocol_fn is [], and
            % string([]) is 1x0, which the scalar property refuses.
            self.RUNTIME.ProtocolFile = string(char(self.CONFIG(1).protocol_fn));

            % Seed Intan interfaces from prefs before connecting: the settings
            % file loads inside setup_interface, which the assignment below
            % triggers.
            self.configureIntanRecorder_(protocol_interfaces);

            % Connect here, not through the setter below, so a failure the
            % operator can fix (a pump switched off, a COM port that moved)
            % can be put to them in a dialog instead of ending the command.
            % The setter then passes over what is already connected.
            self.connectInterfaces_(protocol_interfaces);

            self.RUNTIME.Interfaces = protocol_interfaces;


        catch me
            % Cancelling at that dialog is an answer, not a fault: the generic
            % "check the connections" advice below would only be noise.
            if string(me.identifier) == "epsych:RunExpt:HardwareConnectionCancelled"
                rethrow(me)
            end
            vprintf(0,1,me.message);
            self.setStatus('Hardware initialization failed.', ...
                'check the connections and configuration, then try again.')
            error('epsych:RunExpt:HardwareInitializationFailed', ...
                'Failed to initialize hardware interface. Check connection and configuration, then try again');
        end

        % copy default data path to RUNTIME for use in timer functions and trial selectors
        self.RUNTIME.DefaultDataPath = self.DefaultDataPath;

        % Reserve each subject's data filename here rather than in the Start
        % timer function: ep_TimerFcn_Start stamps it onto each subject's
        % TRIALS, and the video recording PsychTimerStart launches is named
        % after subject 1's copy, so both need it before the timer starts.
        self.RUNTIME.SessionDataFilename = arrayfun(@(c) string(epsych.RunExpt.defaultFilename( ...
            fullfile(self.DefaultDataPath, c.SUBJECT.Name), c.SUBJECT.Name)), self.CONFIG);

        % One identity per subject per run, minted with the filename and for
        % the same reason: ep_TimerFcn_Start captures it into the snapshot, so
        % the recovery seed and the saved file both carry it.
        self.RUNTIME.SessionUID = arrayfun(@(~) epsych.newUUID(), 1:numel(self.CONFIG));

        % make temporary directory for storing data during runtime in case of a computer crash
        E_ = EPsychInfo;
        if strlength(self.RUNTIME.TempDataDir) == 0 || ~isfolder(self.RUNTIME.TempDataDir)
            self.RUNTIME.TempDataDir = fullfile(fileparts(E_.root), 'DATA');
        end
        if ~isfolder(self.RUNTIME.TempDataDir), mkdir(self.RUNTIME.TempDataDir); end

        self.RUNTIME.EVENTS = epsych.EventHub;
        self.H.modeIndicator.attachRuntime(self.RUNTIME);

        self.RUNTIME.TIMER = self.CreateTimer;

        % Whether hardware going Idle stops a multi-interface session is the
        % rig's choice (see RunExpt.StopOnIdleHardware). Read behind ispref:
        % getpref with a default would create the preference.
        if ispref('EPsych', 'StopOnIdleHardware')
            v = getpref('EPsych', 'StopOnIdleHardware');
            if isscalar(v) && (islogical(v) || isnumeric(v))
                self.StopOnIdleHardware = logical(v);
            end
        end
        self.IdleCheckTic_ = [];

        % Displays may draw after the next trial has started instead of
        % before it (epsych.EventHub.defer). A behavior GUI asks for that
        % itself (gui.BehaviorGUI.deferDisplayWork); this preference asks
        % for it on every session of the rig, whatever the GUI. The hub is
        % new each Run, so nothing carries over from the last one.
        if ispref('EPsych', 'DeferDisplays')
            v = getpref('EPsych', 'DeferDisplays');
            if isscalar(v) && (islogical(v) || isnumeric(v)) && logical(v)
                self.RUNTIME.EVENTS.DeferralEnabled = true;
            end
        end

        % Leaving out a dispatch write the device was just read back holding
        % is the rig's choice as well (hw.Interface.SkipUnchangedWrites, and
        % why it is off unless asked for). A preference that exists is
        % applied either way, so removing the true is not needed to get the
        % writes back; one that does not exist leaves each interface as its
        % protocol or a script set it.
        if ispref('EPsych', 'SkipUnchangedWrites')
            v = getpref('EPsych', 'SkipUnchangedWrites');
            if isscalar(v) && (islogical(v) || isnumeric(v))
                ifaces = self.RUNTIME.Interfaces;
                for k = 1:numel(ifaces)
                    ifaces(k).SkipUnchangedWrites = logical(v);
                end
                if logical(v)
                    vprintf(1, 'Unchanged parameter writes are left out of trial dispatch (preference EPsych/SkipUnchangedWrites)')
                end
            end
        end

        % Trial-loop timing is recorded only when asked for (preference
        % EPsych/TickStats); see epsych.TickStats. Reported at Stop.
        if epsych.TickStats.enabledByPref()
            self.RUNTIME.TickStats = epsych.TickStats(Period = self.RUNTIME.TIMER.Period);
            vprintf(1, 'Trial-loop timing is on (preference EPsych/TickStats)')
        end

        % Return each interface's per-session device state to its start-of-run
        % condition. Interfaces stay connected between runs, so a rerun of the
        % same subject would otherwise inherit the previous run's counters
        % (issue #19). hw.TDT_RPcox reloads its circuits here; nothing can
        % observe the unloaded window because the timer has not started.
        self.setStatus('Resetting hardware...')
        arrayfun(@(p) p.resetSession(self.RUNTIME), self.RUNTIME.Interfaces);

        % Let each interface stage backend-side recording (e.g. Intan RHX
        % filename/settings) while the hardware is still stopped; RHX ignores
        % filename.* once the board is running, so this must precede the mode
        % write below.
        arrayfun(@(p) p.prepareRecording(self.RUNTIME), self.RUNTIME.Interfaces);

        vprintf(0,'Initialization complete. Starting experiment...')
        self.setStatus('Initialization complete. Starting...')
        set(self.RUNTIME.Interfaces, 'mode', hw.DeviceState(COMMAND));

        start(self.RUNTIME.TIMER)

        drawnow

    case "Pause"

        self.RUNTIME.EVENTS.notify('ModeChange',epsych.eventModeChange(hw.DeviceState.Pause));
        % STATE stays RUNNING through a pause, so this message is not
        % displaced by a state message until the session stops.
        self.setStatus('Pause broadcast to all listeners.','press Stop to end the session.')

    case "Stop"
        self.STATE = PRGMSTATE.STOP;
        set(self.H.figure1,'pointer','watch')
        self.setStatus('Stopping session...')

        self.RUNTIME.EVENTS.notify('ModeChange',epsych.eventModeChange(hw.DeviceState.Stop));

        vprintf(3,'ExptDispatch: Stopping BoxTimer')
        t = timerfindall('Name','BoxTimer');
        if ~isempty(t), stop(t); delete(t); end

        vprintf(3,'ExptDispatch: Stopping PsychTimer')
        t = timerfindall('Name','PsychTimer');
        if ~isempty(t), stop(t); delete(t); end

        % Normally a no-op: PsychTimerStop (the PsychTimer's StopFcn, triggered
        % synchronously by stop(t) above) already stopped the recording. This
        % covers the edge case where no PsychTimer existed to fire it.
        self.StopVideoRecording_;

        set(self.H.figure1,'pointer','arrow')
        vprintf(0,'Experiment stopped at %s',datetime("now",Format='dd-MMM-yyyy HH:mm'))

        % Data is saved by PsychTimerStop (the PsychTimer's StopFcn),
        % triggered synchronously by stop(t) above.

end

self.UpdateGUIstate
