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

        self.RUNTIME = epsych.Runtime; % reset RUNTIME
        self.RUNTIME.isTest = COMMAND == "Preview";

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

            if self.CONFIG(i).PROTOCOL.needsCompile
                vprintf(0, 'Compiling protocol for subject "%s"...', self.CONFIG(i).SUBJECT.Name);
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
        try
            % Get hardware interfaces from loaded protocol
            % If protocol was designed with Software only, create minimal hardware
            protocol_interfaces = self.CONFIG(1).PROTOCOL.Interfaces;

            % triggers attempt to connect interfaces
            self.RUNTIME.Interfaces = protocol_interfaces;


        catch me
            vprintf(0,1,me.message);
            error('epsych:RunExpt:HardwareInitializationFailed', ...
                'Failed to initialize hardware interface. Check connection and configuration, then try again');
        end

        % copy default data path to RUNTIME for use in timer functions and trial selectors
        self.RUNTIME.dfltDataPath = self.dfltDataPath;

        % make temporary directory for storing data during runtime in case of a computer crash
        E_ = EPsychInfo;
        if strlength(self.RUNTIME.TempDataDir) == 0 || ~isfolder(self.RUNTIME.TempDataDir)
            self.RUNTIME.TempDataDir = fullfile(fileparts(E_.root), 'DATA');
        end
        if ~isfolder(self.RUNTIME.TempDataDir), mkdir(self.RUNTIME.TempDataDir); end

        self.RUNTIME.HELPER = epsych.Helper;
        self.H.modeIndicator.attachRuntime(self.RUNTIME);

        self.RUNTIME.TIMER = self.CreateTimer;

        % Start video before hardware enters run mode: VLC launch blocks ~1 s,
        % which must not land inside the trial loop, and the recording should
        % cover the run from the first trial. Preview never records.
        if COMMAND == "Record"
            self.StartVideoRecording_
        end

        vprintf(0,'Initialization complete. Starting experiment...')
        set(self.RUNTIME.Interfaces, 'mode', hw.DeviceState(COMMAND));

        start(self.RUNTIME.TIMER)

        drawnow

    case "Pause"

        self.RUNTIME.HELPER.notify('ModeChange',epsych.eventModeChange(hw.DeviceState.Pause));

    case "Stop"
        self.STATE = PRGMSTATE.STOP;
        set(self.H.figure1,'pointer','watch')

        self.RUNTIME.HELPER.notify('ModeChange',epsych.eventModeChange(hw.DeviceState.Stop));

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
