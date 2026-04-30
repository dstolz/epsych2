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

        self.RUNTIME.NSubjects = length(self.CONFIG);


        % connect hardware interfaces
        try
            % Get hardware interfaces from loaded protocol
            % If protocol was designed with Software only, create minimal hardware
            protocol_interfaces = self.CONFIG(1).PROTOCOL.Interfaces;
            
            
            for i = 1:length(protocol_interfaces)
                vprintf(0,'Connecting to hardware interface: %s', class(hw_interfaces(i)))
                
                if ~protocol_interfaces(i).IsConnected
                    protocol_interfaces(i).connect();
                    assert(protocol_interfaces(i).IsConnected, ...
                        'epsych:RunExpt:HardwareConnectionFailed', ...
                        'Hardware interface "%s" failed to connect. Check hardware status before starting.', ...
                        class(protocol_interfaces(i)));
                end
            end

            self.RUNTIME.Interfaces = protocol_interfaces;


        catch me
            vprintf(0,1,me);
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

        self.RUNTIME.TIMER = self.CreateTimer;

        vprintf(0,'Initialization complete. Starting experiment...')
        set(self.RUNTIME.Interfaces,'mode',hw.DeviceState(COMMAND));

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

        set(self.H.figure1,'pointer','arrow')
        vprintf(0,'Experiment stopped at %s',datetime("now",Format='dd-MMM-yyyy HH:mm'))

        % Auto-save data on stop so users don't lose organized results.
        self.SaveDataCallback

end

self.UpdateGUIstate
