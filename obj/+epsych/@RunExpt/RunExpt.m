classdef RunExpt < handle
    % RunExpt Run and manage psychophysics experiments from a session GUI.
    %
    % OBJ = epsych.RunExpt creates or reuses the main RunExpt window used to
    % configure subjects, load saved configurations, and start or stop an
    % experiment session.
    %
    % OBJ = epsych.RunExpt(CONFIGFILE) additionally loads the configuration MAT
    % file specified by CONFIGFILE after the GUI is initialized.
    %
    % The class coordinates three layers of state:
    %   CONFIG  - Per-subject protocol and runtime configuration entries.
    %   FUNCS   - Preference-backed callback names for saving, timers, and GUIs.
    %   RUNTIME - Shared epsych.Runtime state used while the experiment runs.
    %
    % Common interactive tasks include:
    %   LoadConfig / SaveConfig    Load or persist a RunExpt configuration.
    %   AddSubject / RemoveSubject Manage the configured subject list.
    %   ViewTrials / EditProtocol  Inspect or edit a selected protocol.
    %   DefineDataPath             Choose the default folder for saved data.
    %
    % Only one live RunExpt window is kept open at a time. Constructing a new
    % instance returns the existing object when possible and brings its figure
    % to the foreground.
    %
    % See also epsych.Runtime, ep_ExperimentDesign, ep_CompiledProtocolTrials.

    properties
        H
        STATE (1,1) PRGMSTATE = PRGMSTATE.NOCONFIG
        CONFIG (1,1) struct = struct('SUBJECT',[],'PROTOCOL',[],'RUNTIME',[],'protocol_fn',[])
        FUNCS (1,1) struct = struct()
        RUNTIME (1,1) epsych.Runtime = epsych.Runtime
        dfltDataPath (1,1) string = cd
        IsClosing (1,1) logical = false
    end

    methods
        LoadConfig(self, cfn)
        SaveConfig(self)
        ok = LocateProtocol(self, pfn)
        AddSubject(self, S)
        RemoveSubject(self, idx)

        DefineSavingFcn(self, a)
        DefineConfigBrowserRoot(self)
        BrowseConfigs(self)

        DefineAddSubject(self, a)
        DefineBoxFig(self, a)

        function self = RunExpt(ffnConfig)
            % RunExpt Create or reactivate the main experiment control window.
            arguments
                ffnConfig (1,1) string = ""
            end
            global GVerbosity

            if isempty(GVerbosity) || ~isnumeric(GVerbosity)
                GVerbosity = 1;
            end

            f = findall(groot,'Type','figure','-and','Tag','RunExpt');
            existingFigure = [];
            existingInstance = [];
            for i = 1:numel(f)
                if ~isgraphics(f(i)), continue, end

                try
                    candidate = f(i).UserData;
                catch
                    candidate = [];
                end

                if isa(candidate,'epsych.RunExpt') && isvalid(candidate) && ~candidate.IsClosing
                    if isempty(existingInstance)
                        existingFigure = f(i);
                        existingInstance = candidate;
                    else
                        try
                            f(i).UserData = [];
                            f(i).CloseRequestFcn = [];
                            f(i).Tag = '';
                            delete(f(i));
                        catch
                        end
                    end
                else
                    try
                        f(i).UserData = [];
                        f(i).CloseRequestFcn = [];
                        f(i).Tag = '';
                        delete(f(i));
                    catch
                    end
                end
            end

            if ~isempty(existingInstance)
                try
                    existingFigure.Visible = 'on';
                catch
                end
                movegui(existingFigure,'onscreen');
                try
                    uifigure(existingFigure);
                catch
                    try
                        figure(existingFigure);
                    catch
                    end
                end
                self = existingInstance;

                if ffnConfig ~= ""
                    self.LoadConfig(ffnConfig)
                end

                return
            end

            self.buildUI
            self.FUNCS = self.GetDefaultFuncs;
            self.ClearConfig
            self.UpdateGUIstate
            self.dfltDataPath = getpref('RunExpt','DataPath',cd);

            if ffnConfig ~= ""
                self.LoadConfig(ffnConfig)
            end

            if nargout == 0, clear self; end
        end

        function delete(self)
            % delete Close the GUI cleanly when the object is destroyed.
            try
                if isvalid(self) && ~self.IsClosing
                    self.onCloseRequest
                end
            catch
            end
        end


        function ViewTrials(self)
            % ViewTrials Display a preview of trials for the selected subject.
            idx = self.H.subject_list.Selection(1);
            if isempty(idx), return, end

            warning('off','MATLAB:dispatcher:UnresolvedFunctionHandle');
            S = load(self.CONFIG(idx).protocol_fn,'protocol','-mat');
            warning('on','MATLAB:dispatcher:UnresolvedFunctionHandle');

            ep_CompiledProtocolTrials(S.protocol,'trunc',2000);
        end

        function EditProtocol(self)
            % EditProtocol Open the selected protocol in the design editor.
            idx = self.H.subject_list.Selection(1);
            if isempty(idx), return, end

            self.AlwaysOnTop(false);
            ep_ExperimentDesign(char(self.CONFIG(idx).protocol_fn),idx);
        end

        function SortBoxes(self)
            % SortBoxes Reorder subjects by their assigned behavioral box ID.
            if self.STATE >= PRGMSTATE.RUNNING, return, end
            if ~isfield(self.CONFIG,'SUBJECT'), return, end
            ids = arrayfun(@(c) c.SUBJECT.BoxID, self.CONFIG);
            C = self.CONFIG;
            for i = 1:length(ids)
                CS(i) = C(ids(i)); %#ok<AGROW>
            end
            self.CONFIG = CS; %#ok<*PROP>
            self.UpdateSubjectList
        end

        function DefineDataPath(self)
            % DefineDataPath Set the default directory used for saved data.
            ontop = self.AlwaysOnTop(false);
            pth = uigetdir(self.dfltDataPath,'Select Default Data Directory');
            self.AlwaysOnTop(ontop);

            if isequal(pth,0) || strlength(string(pth))==0, return, end
            pth = string(pth);

            self.dfltDataPath = pth;
            setpref('RunExpt','DataPath',pth);

            self.CheckReady
        end

        function LocateBehaviorGUI(self)
            % LocateBehaviorGUI Open the configured per-box behavior GUI.
            if isempty(self.FUNCS.BoxFig), return, end
            feval(self.FUNCS.BoxFig, self.RUNTIME);
        end

        originalState = AlwaysOnTop(self, ontop)

        function version_info(self)
            % version_info Display toolbox metadata in the command window.
            E = EPsychInfo;
            disp(E.meta)
            commandwindow
        end

        verbosity(self)
    end

    methods (Access=private)
        buildUI(self)
        onCloseRequest(self)
        SaveDataCallback(self)
        recent = GetRecentConfigs(self)
        LoadRecentConfig(self, cfn)
        RememberRecentConfig(self, cfn)
        UpdateRecentConfigsMenu(self)
        CheckReady(self)
        UpdateGUIstate(self)
        UpdateSubjectList(self)
        ExptDispatch(self, COMMAND)
        T = CreateTimer(self)
        PsychTimerStart(self)

        [items, fullpaths] = FindConfigFiles(self, root)
        ConfigBrowserLoad(self, fig, lb)
        ConfigBrowserCancel(self, fig)

        function onCommand(self, hObj)
            self.ExptDispatch(string(hObj.Text));
        end

        function PsychTimerRunTime(self)
            if isfield(self.RUNTIME,'HW') && self.RUNTIME.HW.mode == hw.DeviceState.Idle
                self.ExptDispatch("Stop")
                return
            end
            self.RUNTIME = feval(self.FUNCS.TIMERfcn.RunTime, self.RUNTIME);
        end

        function PsychTimerError(self)
            self.STATE = PRGMSTATE.ERROR;
            self.RUNTIME.ERROR = lasterror; %#ok<LERR>
            self.RUNTIME = feval(self.FUNCS.TIMERfcn.Error, self.RUNTIME);
            feval(self.FUNCS.SavingFcn, self.RUNTIME);
            self.UpdateGUIstate
            self.SaveDataCallback
        end

        function PsychTimerStop(self)
            self.STATE = PRGMSTATE.STOP;
            vprintf(3,'PsychTimerStop:Calling timer Stop function: %s',self.FUNCS.TIMERfcn.Stop)
            self.RUNTIME = feval(self.FUNCS.TIMERfcn.Stop, self.RUNTIME);
            vprintf(3,'PsychTimerStop:Calling UpdateGUIstate')
            self.UpdateGUIstate
            vprintf(3,'PsychTimerStop:Calling SaveDataCallback')
            self.SaveDataCallback
        end

        function subject_list_SelectionChanged(self, hObj, evnt)
            disp(self.CONFIG(hObj.Selection(1)).SUBJECT)
        end

        function SetDefaultFuncs(self, F)
            setpref('ep_RunExpt_FUNCS','SavingFcn',    F.SavingFcn)
            setpref('ep_RunExpt_FUNCS','AddSubjectFcn',F.AddSubjectFcn)
            setpref('ep_RunExpt_FUNCS','BoxFig',       F.BoxFig)

            setpref('ep_RunExpt_TIMER','Start',     F.TIMERfcn.Start)
            setpref('ep_RunExpt_TIMER','RunTime',   F.TIMERfcn.RunTime)
            setpref('ep_RunExpt_TIMER','Stop',      F.TIMERfcn.Stop)
            setpref('ep_RunExpt_TIMER','Error',     F.TIMERfcn.Error)
        end

        function F = GetDefaultFuncs(self)
            F.SavingFcn      = getpref('ep_RunExpt_FUNCS','SavingFcn',    'ep_SaveDataFcn');
            F.AddSubjectFcn  = getpref('ep_RunExpt_FUNCS','AddSubjectFcn','ep_AddSubject');
            F.BoxFig         = getpref('ep_RunExpt_FUNCS','BoxFig',       'ep_GenericGUI');

            F.TIMERfcn.Start    = getpref('ep_RunExpt_TIMER','Start',   'ep_TimerFcn_Start');
            F.TIMERfcn.RunTime  = getpref('ep_RunExpt_TIMER','RunTime', 'ep_TimerFcn_RunTime');
            F.TIMERfcn.Stop     = getpref('ep_RunExpt_TIMER','Stop',    'ep_TimerFcn_Stop');
            F.TIMERfcn.Error    = getpref('ep_RunExpt_TIMER','Error',   'ep_TimerFcn_Error');
        end

        function ClearConfig(self)
            self.CONFIG = struct('SUBJECT',[],'PROTOCOL',[],'RUNTIME',[],'protocol_fn',[]);
            if self.STATE >= PRGMSTATE.RUNNING, return, end
            self.STATE = PRGMSTATE.NOCONFIG;
            if isfield(self.H,'subject_list') && isgraphics(self.H.subject_list)
                set(self.H.subject_list,'Data',[])
            end
            self.CheckReady
        end

        function ConfigBrowserRestoreOnTop(self, ontop)
            if ~isfield(self.H,'figure1') || ~isgraphics(self.H.figure1), return, end
            if ~isfield(self.H,'always_on_top') || ~isgraphics(self.H.always_on_top), return, end
            self.AlwaysOnTop(ontop)
        end
    end

    methods (Static)
        ffn = defaultFilename(pth,name)
    end
end
