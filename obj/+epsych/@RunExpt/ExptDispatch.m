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
if COMMAND == "Run", COMMAND = "Record"; end

switch lower(COMMAND)
    case {"run","record","preview"}
        drawnow

        % Set process priority to high
        [~,~] = dos('wmic process where name="MATLAB.exe" CALL setpriority "high priority"');

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

            if self.CONFIG(i).PROTOCOL.COMPILED.ntrials == 0
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

        % TO DO: CREATE BETTER SYSTEM FOR MANAGING MULTIPLE HARDWARE INTERFACES
        [~,result] = system('tasklist/FI "imagename eq Synapse.exe"');
        x = strfind(result,'No tasks are running');
        self.RUNTIME.usingSynapse = isempty(x);

        try
            if self.RUNTIME.usingSynapse
                vprintf(0,'Experiment will be run with Synapse')
                self.RUNTIME.HW = hw.TDT_Synapse();
            else
                % Get hardware interfaces from loaded protocol
                % If protocol was designed with Software only, create minimal hardware
                protocol_interfaces = self.CONFIG.PROTOCOL.Interfaces;
                
                % Filter out Software interfaces and find hardware interfaces
                hw_interfaces = [];
                for iface_idx = 1:length(protocol_interfaces)
                    iface = protocol_interfaces(iface_idx);
                    if ~strcmp(char(iface.Type), 'Software')
                        hw_interfaces = [hw_interfaces, iface];  %#ok<AGROW>
                    end
                end
                
                if isempty(hw_interfaces)
                    % Create minimal TDT_RPcox with Software fallback
                    vprintf(1,'No hardware interfaces found in protocol; creating TDT_RPcox placeholder');
                    self.RUNTIME.HW = hw.Software();
                else
                    % Use first hardware interface (or could select based on ConnectionType)
                    self.RUNTIME.HW = hw_interfaces(1);
                    if isprop(self.RUNTIME.HW, 'IsConnected') && ~self.RUNTIME.HW.IsConnected
                        if ismethod(self.RUNTIME.HW, 'connect')
                            self.RUNTIME.HW.connect();
                        end
                        assert(self.RUNTIME.HW.IsConnected, ...
                            'epsych:RunExpt:HardwareConnectionFailed', ...
                            'Hardware interface "%s" failed to connect. Check hardware status before starting.', ...
                            class(self.RUNTIME.HW));
                    end
                end
            end
        catch me
            drawnow
            rethrow(me)
        end

        self.RUNTIME.dfltDataPath = self.dfltDataPath;

        self.RUNTIME.HELPER = epsych.Helper;

        self.RUNTIME.TIMER = self.CreateTimer;

        self.RUNTIME.HW.mode = hw.DeviceState(COMMAND);
        vprintf(0,'System set to ''%s''',COMMAND)
        pause(1)

        start(self.RUNTIME.TIMER)

        self.RUNTIME.HELPER.notify('ModeChange',epsych.eventModeChange(hw.DeviceState.Record));

        drawnow

    case "pause"

        self.RUNTIME.HELPER.notify('ModeChange',epsych.eventModeChange(hw.DeviceState.Pause));

    case "stop"
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

end

self.UpdateGUIstate
