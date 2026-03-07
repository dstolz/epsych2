function ExptDispatch(self, COMMAND)
% ExptDispatch — Core state dispatcher for run/preview/stop.
% Inputs
%   COMMAND (string) — "Run"|"Record"|"Preview"|"Stop".
% Behavior
%   Prepares RUNTIME, loads protocols, initializes hardware,
%   configures/starts the PsychTimer, and manages Stop/cleanup.
arguments
    self (1,1) ep_RunExpt2
    COMMAND {mustBeTextScalar}
end

COMMAND = string(COMMAND);
if COMMAND == "Run", COMMAND = "Record"; end

switch lower(COMMAND)
    case {"run","record","preview"}
        drawnow

        [~,~] = dos('wmic process where name="MATLAB.exe" CALL setpriority "high priority"');

        vprintf(0,'\n%s\n',repmat('~',1,50))

        self.RUNTIME = epsych.Runtime; % reset RUNTIME

        % Load protocols
        for i = 1:length(self.CONFIG)
            warning('off','MATLAB:dispatcher:UnresolvedFunctionHandle');
            S = load(self.CONFIG(i).protocol_fn,'protocol','-mat');
            warning('on','MATLAB:dispatcher:UnresolvedFunctionHandle');

            self.CONFIG(i).PROTOCOL = S.protocol;

            [pn,fn] = fileparts(self.CONFIG(i).protocol_fn);
            vprintf(0,['%2d. ''%s''\tProtocol: ', ...
                '<a href="matlab: ep_ExperimentDesign(''%s'');">%s</a>' ...
                '(<a href="matlab: !explorer %s">%s</a>)'], ...
                self.CONFIG(i).SUBJECT.BoxID,self.CONFIG(i).SUBJECT.Name, ...
                self.CONFIG(i).protocol_fn,fn,pn,pn)

            if isempty(self.CONFIG(i).PROTOCOL.OPTIONS.trialfunc) ...
                    || strcmp(self.CONFIG(i).PROTOCOL.OPTIONS.trialfunc,'< default >')
                self.CONFIG(i).PROTOCOL.OPTIONS.trialfunc = @DefaultTrialSelectFcn;
            end
        end

        self.RUNTIME.NSubjects = length(self.CONFIG);

        [~,result] = system('tasklist/FI "imagename eq Synapse.exe"');
        x = strfind(result,'No tasks are running');
        self.RUNTIME.usingSynapse = isempty(x);

        try
            if self.RUNTIME.usingSynapse
                vprintf(0,'Experiment will be run with Synapse')
                self.RUNTIME.HW = hw.TDT_Synapse();
            else
                M = self.CONFIG.PROTOCOL.MODULES;
                moduleAlias = fieldnames(M);
                rpvdsFile = structfun(@(a) cellstr(a.RPfile),M,'uni',1);
                moduleType = repmat({'RZ6'},size(rpvdsFile));
                self.RUNTIME.HW = hw.TDT_RPcox(rpvdsFile,moduleType,moduleAlias);
            end
        catch me
            drawnow
            rethrow(me)
        end

        for i = 1:length(self.CONFIG)
            self.RUNTIME.TRIALS(i).protocol_fn = self.CONFIG(i).protocol_fn; %#ok<AGROW>
            modnames = fieldnames(self.CONFIG(i).PROTOCOL.MODULES);
            for j = 1:length(modnames)
                self.RUNTIME.TRIALS(i).MODULES.(modnames{j}) = j;
            end
        end

        self.RUNTIME.dfltDataPath = self.dfltDataPath;

        self.RUNTIME.HELPER = epsych.Helper;

        self.RUNTIME.TIMER = self.CreateTimer;

        self.RUNTIME.HW.mode = hw.DeviceState(COMMAND);
        vprintf(0,'System set to ''%s''',COMMAND)
        pause(1)

        start(self.RUNTIME.TIMER)

        self.RUNTIME.HELPER.notify('ModeChange',epsych.ModeChangeEvent(hw.DeviceState.Record));

        drawnow

    case "pause"

        self.RUNTIME.HELPER.notify('ModeChange',epsych.ModeChangeEvent(hw.DeviceState.Pause));

    case "stop"
        self.STATE = PRGMSTATE.STOP;
        set(self.H.figure1,'pointer','watch')

        self.RUNTIME.HELPER.notify('ModeChange',epsych.ModeChangeEvent(hw.DeviceState.Stop));

        vprintf(3,'ExptDispatch: Stopping BoxTimer')
        t = timerfind('Name','BoxTimer');
        if ~isempty(t), stop(t); delete(t); end

        vprintf(3,'ExptDispatch: Stopping PsychTimer')
        t = timerfind('Name','PsychTimer');
        if ~isempty(t), stop(t); delete(t); end

        vprintf(0,'Experiment stopped at %s',datetime("now",Format='dd-MMM-yyyy HH:mm'))

end

self.UpdateGUIstate
