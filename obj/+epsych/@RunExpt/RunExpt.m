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
        H                                                                                        % Handles to UI components and figures
        STATE (1,1) PRGMSTATE = PRGMSTATE.NOCONFIG                                              % Current experiment program state
        CONFIG (1,1) struct = struct('SUBJECT',[],'PROTOCOL',[],'RUNTIME',[],'protocol_fn',[])  % Per-subject configuration array; each element holds SUBJECT, PROTOCOL, RUNTIME, and protocol_fn
        FUNCS (1,1) struct = struct()                                                            % Preference-backed callback function names for saving, timers, and GUI
        RUNTIME (1,1) epsych.Runtime = epsych.Runtime                                           % Shared runtime state passed to all callbacks during the session
        dfltDataPath (1,1) string = cd                                                          % Default directory for saving experiment data
        IsClosing (1,1) logical = false                                                         % True while the close sequence is in progress; prevents re-entrant callbacks
    end

    methods
        LoadConfig(self, cfn)           % Load configuration from MAT file cfn
        SaveConfig(self)                % Persist current configuration to file
        ok = LocateProtocol(self, pfn)  % Validate and register protocol file pfn; ok is true on success
        AddSubject(self, S)             % Append subject struct S to CONFIG
        RemoveSubject(self, idx)        % Remove subject at index idx from CONFIG

        DefineSavingFcn(self, a)        % Set the data-saving callback function name
        DefineConfigBrowserRoot(self)   % Set the root folder used by the config browser
        BrowseConfigs(self)             % Open the config browser dialog

        DefineAddSubject(self, a)       % Set the add-subject callback function name
        DefineBoxFig(self, a)           % Set the behavioral box figure callback function name

        function self = RunExpt(ffnConfig)
            % self = RunExpt()
            % self = RunExpt(ffnConfig)
            % Create or reactivate the main experiment control window.
            % Returns the existing instance when a RunExpt figure is already open.
            %  ffnConfig - (optional) path to a configuration MAT file to load
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
            % delete(self)
            % Close the GUI cleanly when the object is destroyed.
            try
                if isvalid(self) && ~self.IsClosing
                    self.onCloseRequest
                end
            catch
            end
        end


        function ViewTrials(self)
            % obj.ViewTrials
            % Display a preview of compiled trials for the selected subject.
            idx = self.H.subject_list.Selection(1);
            if isempty(idx), return, end

            warning('off','MATLAB:dispatcher:UnresolvedFunctionHandle');
            S = load(self.CONFIG(idx).protocol_fn,'protocol','-mat');
            warning('on','MATLAB:dispatcher:UnresolvedFunctionHandle');

            ep_CompiledProtocolTrials(S.protocol,'trunc',2000);
        end

        function EditProtocol(self)
            % obj.EditProtocol
            % Open the selected subject's protocol in the experiment design editor.
            idx = self.H.subject_list.Selection(1);
            if isempty(idx), return, end

            self.AlwaysOnTop(false);
            ep_ExperimentDesign(char(self.CONFIG(idx).protocol_fn),idx);
        end

        function SortBoxes(self)
            % obj.SortBoxes
            % Reorder subjects in CONFIG by their assigned behavioral box ID.
            if self.STATE >= PRGMSTATE.RUNNING, return, end
            if ~isfield(self.CONFIG,'SUBJECT'), return, end
            ids = arrayfun(@(c) c.SUBJECT.BoxID, self.CONFIG);
            C = self.CONFIG;
            for i = 1:length(ids)
                CS(i) = C(ids(i));
            end
            self.CONFIG = CS;
            self.UpdateSubjectList
        end

        function DefineDataPath(self)
            % obj.DefineDataPath
            % Prompt for and persist the default data-saving directory.
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
            % obj.LocateBehaviorGUI
            % Launch the per-box behavior GUI specified in FUNCS.BoxFig.
            if isempty(self.FUNCS.BoxFig), return, end
            feval(self.FUNCS.BoxFig, self.RUNTIME);
        end

        originalState = AlwaysOnTop(self, ontop)  % Set always-on-top state of main figure; returns previous state

        function version_info(self)
            % obj.version_info
            % Display toolbox version metadata in the command window.
            E = EPsychInfo;
            disp(E.meta)
            commandwindow
        end

        function AssignRuntimeToCommandWindow(self)
            % obj.AssignRuntimeToCommandWindow
            % Export the RUNTIME object to the base workspace as 'RUNTIME'.
            assignin('base','RUNTIME',self.RUNTIME);
            vprintf(0,'Assigned `RunExpt.RUNTIME` to workspace variable `RUNTIME`.')
            commandwindow
        end

        verbosity(self, varargin)  % Set or query the global output verbosity level
    end

    methods (Access=private)
        buildUI(self)                                      % Build main figure and all UI components
        onFigureKeyPress(self, evt)                        % Handle key-press events on the main figure
        onCloseRequest(self)                               % Stop experiment if running and destroy the figure
        SaveDataCallback(self)                             % Invoke the configured data-saving callback
        recent = GetRecentConfigs(self)                    % Return cell array of recently opened config file paths
        LoadRecentConfig(self, cfn)                        % Load config at path cfn and update recents list
        RememberRecentConfig(self, cfn)                    % Add cfn to the persistent recent config registry
        UpdateRecentConfigsMenu(self)                      % Rebuild the recent-configs submenu items
        CheckReady(self)                                   % Evaluate whether all conditions to run are met and update STATE
        UpdateGUIstate(self)                               % Refresh all UI control states to match current STATE
        UpdateSubjectList(self)                            % Repopulate the subject list with current CONFIG entries
        ExptDispatch(self, COMMAND)                        % Dispatch a named command (Start/Stop/Pause) to the experiment
        T = CreateTimer(self)                              % Create and configure the psychophysics trial timer object
        PsychTimerStart(self)                              % Initialize runtime state and start the trial timer

        [items, fullpaths] = FindConfigFiles(self, root)   % Recursively find config MAT files under root directory
        ConfigBrowserLoad(self, fig, lb)                   % Load config selected in list box lb and close fig
        ConfigBrowserCancel(self, fig)                     % Close config browser figure without loading

        function onCommand(self, hObj)
            % Adapts menu item callbacks; forwards the item's text label to ExptDispatch.
            self.ExptDispatch(string(hObj.Text));
        end

        function PsychTimerRunTime(self)
            % Timer runtime callback; stops the experiment automatically if hardware enters idle state.
            if isfield(self.RUNTIME,'HW') && self.RUNTIME.HW.mode == hw.DeviceState.Idle
                self.ExptDispatch("Stop")
                return
            end
            self.RUNTIME = feval(self.FUNCS.TIMERfcn.RunTime, self.RUNTIME);
        end

        function PsychTimerError(self)
            % Timer error callback; records the last error, invokes the error handler, saves data, and updates GUI state.
            self.STATE = PRGMSTATE.ERROR;
            self.RUNTIME.ERROR = lasterror;
            self.RUNTIME = feval(self.FUNCS.TIMERfcn.Error, self.RUNTIME);
            feval(self.FUNCS.SavingFcn, self.RUNTIME);
            self.UpdateGUIstate
            self.SaveDataCallback
        end

        function PsychTimerStop(self)
            % Timer stop callback; invokes the stop handler, updates GUI state, and saves data.
            self.STATE = PRGMSTATE.STOP;
            vprintf(3,'PsychTimerStop:Calling timer Stop function: %s',self.FUNCS.TIMERfcn.Stop)
            self.RUNTIME = feval(self.FUNCS.TIMERfcn.Stop, self.RUNTIME);
            vprintf(3,'PsychTimerStop:Calling UpdateGUIstate')
            self.UpdateGUIstate
            vprintf(3,'PsychTimerStop:Calling SaveDataCallback')
            self.SaveDataCallback
        end

        function subject_list_SelectionChanged(self, hObj, evnt)
            % Displays subject info in the command window when the list selection changes.
            disp(self.CONFIG(hObj.Selection(1)).SUBJECT)
        end

        function SetDefaultFuncs(self, F)
            % SetDefaultFuncs(self, F)
            % Persist all callback function names from struct F to MATLAB preferences.
            setpref('ep_RunExpt_FUNCS','SavingFcn',    F.SavingFcn)
            setpref('ep_RunExpt_FUNCS','AddSubjectFcn',F.AddSubjectFcn)
            setpref('ep_RunExpt_FUNCS','BoxFig',       F.BoxFig)

            setpref('ep_RunExpt_TIMER','Start',     F.TIMERfcn.Start)
            setpref('ep_RunExpt_TIMER','RunTime',   F.TIMERfcn.RunTime)
            setpref('ep_RunExpt_TIMER','Stop',      F.TIMERfcn.Stop)
            setpref('ep_RunExpt_TIMER','Error',     F.TIMERfcn.Error)
        end

        function F = GetDefaultFuncs(self)
            % F = GetDefaultFuncs(self)
            % Load all callback function names from MATLAB preferences into struct F.
            F.SavingFcn      = getpref('ep_RunExpt_FUNCS','SavingFcn',    'ep_SaveDataFcn');
            F.AddSubjectFcn  = getpref('ep_RunExpt_FUNCS','AddSubjectFcn','ep_AddSubject');
            F.BoxFig         = getpref('ep_RunExpt_FUNCS','BoxFig',       'ep_GenericGUI');

            F.TIMERfcn.Start    = getpref('ep_RunExpt_TIMER','Start',   'ep_TimerFcn_Start');
            F.TIMERfcn.RunTime  = getpref('ep_RunExpt_TIMER','RunTime', 'ep_TimerFcn_RunTime');
            F.TIMERfcn.Stop     = getpref('ep_RunExpt_TIMER','Stop',    'ep_TimerFcn_Stop');
            F.TIMERfcn.Error    = getpref('ep_RunExpt_TIMER','Error',   'ep_TimerFcn_Error');
        end

        function ClearConfig(self)
            % ClearConfig(self)
            % Reset CONFIG to empty defaults and update program state if not running.
            self.CONFIG = struct('SUBJECT',[],'PROTOCOL',[],'RUNTIME',[],'protocol_fn',[]);
            if self.STATE >= PRGMSTATE.RUNNING, return, end
            self.STATE = PRGMSTATE.NOCONFIG;
            if isfield(self.H,'subject_list') && isgraphics(self.H.subject_list)
                set(self.H.subject_list,'Data',[])
            end
            self.CheckReady
        end

        function ConfigBrowserRestoreOnTop(self, ontop)
            % ConfigBrowserRestoreOnTop(self, ontop)
            % Restore the always-on-top state of the main figure after a config browser closes.
            if ~isfield(self.H,'figure1') || ~isgraphics(self.H.figure1), return, end
            if ~isfield(self.H,'always_on_top') || ~isgraphics(self.H.always_on_top), return, end
            self.AlwaysOnTop(ontop)
        end
    end

    methods (Static)
        ffn = defaultFilename(pth,name)
    end
end
