classdef RunExpt < handle
    % RunExpt — Run and manage psychophysics experiments with a UIFigure-based GUI.
    %
    % Description
    %   Provides subject/configuration management, protocol loading, TDT hardware
    %   initialization (Synapse or RPvds), a timer-driven runtime loop, data
    %   saving hooks, and optional behavior-performance GUI integration. The UI
    %   is built with uifigure/uigridlayout and exposes core controls (Run,
    %   Preview, Pause, Stop) plus utilities for editing protocols and saving.
    %
    % Key Features
    %   • Maintains experiment state via PRGMSTATE
    %   • Loads/saves .config files containing subjects, protocols, and callbacks
    %   • Selects hardware driver (hw.TDT_Synapse or hw.TDT_RPcox) from context
    %   • Uses TIMERfcn callbacks for Start/RunTime/Stop/Error
    %   • Delegates saving, subject creation, and GUI creation to user-defined functions
    %
    % Properties (brief)
    %   H            — UI handle struct
    %   STATE        — PRGMSTATE enum (lifecycle state)
    %   CONFIG       — Per-subject config array (SUBJECT/PROTOCOL/RUNTIME/protocol_fn)
    %   FUNCS        — Function handles/names for Saving/AddSubject/BoxFig/TIMERfcn
    %   RUNTIME      — Runtime state container shared with callbacks
    %   GVerbosity   — Verbosity level for vprintf()
    %   dfltDataPath — Default data directory for saving
    %
    % Daniel.Stolzberg@gmail.com 2014–2025

    properties
        H % struct of UI handles
        STATE (1,1) PRGMSTATE = PRGMSTATE.NOCONFIG % current program state
        CONFIG (1,1) struct = struct('SUBJECT',[],'PROTOCOL',[],'RUNTIME',[],'protocol_fn',[]) % array of subject configs
        FUNCS (1,1) struct = struct() % function handles/names for callbacks
        RUNTIME (1,1) epsych.Runtime = epsych.Runtime
        GVerbosity (1,1) double = 1 % verbosity level for vprintf

        dfltDataPath (1,1) string = cd % default data path for saving
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

        function self = ep_RunExpt2()

            f = findobj('tag','ep_RunExpt2');
            if ~isempty(f)
                figure(f); movegui(f,'onscreen');
                self = f.UserData;
                return
            end

            self.buildUI
            self.FUNCS = self.GetDefaultFuncs;
            self.ClearConfig
            self.UpdateGUIstate
            self.dfltDataPath = getpref('RunExpt','DataPath',cd);

            if nargout == 0, clear self; end
        end

        function delete(self)
            % delete — Ensure resources are released when object is cleared.
            arguments
                self (1,1) ep_RunExpt2
            end
            try
                if isvalid(self)
                    self.onCloseRequest
                end
            catch
            end
        end

        function Run(self)
            % Run — Convenience wrapper to start experiment (Record mode).
            arguments
                self (1,1) ep_RunExpt2
            end
            self.ExptDispatch("Run")
        end

        function Record(self)
            % Record — Start experiment in acquisition mode.
            arguments
                self (1,1) ep_RunExpt2
            end
            self.ExptDispatch("Record")
        end

        function Preview(self)
            % Preview — Start non-recording preview session.
            arguments
                self (1,1) ep_RunExpt2
            end
            self.ExptDispatch("Preview")
        end

        function Pause(self)
            % Pause — Placeholder for future pause handling.
            arguments
                self (1,1) ep_RunExpt2
            end
        end

        function Stop(self)
            % Stop — Halt the running experiment and timers.
            arguments
                self (1,1) ep_RunExpt2
            end
            self.ExptDispatch("Stop")
        end

        function SaveData(self)
            % SaveData — Trigger save using the configured SavingFcn.
            arguments
                self (1,1) ep_RunExpt2
            end
            self.SaveDataCallback
        end

        function ViewTrials(self)
            % ViewTrials — Display compiled trial definitions for selection.
            arguments
                self (1,1) ep_RunExpt2
            end
            idx = self.H.subject_list.Selection(1);
            if isempty(idx), return, end

            warning('off','MATLAB:dispatcher:UnresolvedFunctionHandle');
            S = load(self.CONFIG(idx).protocol_fn,'protocol','-mat');
            warning('on','MATLAB:dispatcher:UnresolvedFunctionHandle');

            ep_CompiledProtocolTrials(S.protocol,'trunc',2000);
        end

        function EditProtocol(self)
            % EditProtocol — Launch protocol editor for selected subject.
            arguments
                self (1,1) ep_RunExpt2
            end
            idx = self.H.subject_list.Selection(1);
            if isempty(idx), return, end

            self.AlwaysOnTop(false);
            ep_ExperimentDesign(char(self.CONFIG(idx).protocol_fn),idx);
        end

        function SortBoxes(self)
            % SortBoxes — Reorder CONFIG by SUBJECT.BoxID.
            arguments
                self (1,1) ep_RunExpt2
            end
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
            % DefineDataPath — Configure the default data-saving directory.
            arguments
                self (1,1) ep_RunExpt2
            end
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
            % LocateBehaviorGUI — Launch the configured behavior GUI.
            arguments
                self (1,1) ep_RunExpt2
            end
            if isempty(self.FUNCS.BoxFig), return, end
            feval(self.FUNCS.BoxFig, self.RUNTIME);
        end

        originalState = AlwaysOnTop(self, ontop)

        function version_info(self)
            % version_info — Display EPsych metadata in the command window.
            arguments
                self (1,1) ep_RunExpt2 %#ok<INUSA>
            end
            E = EPsychInfo;
            disp(E.meta)
            commandwindow
        end

        verbosity(self)
    end % methods

    methods (Access=private)
        buildUI(self)
        onCloseRequest(self)
        SaveDataCallback(self)
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
            % onCommand — Route button clicks to the dispatcher.
            arguments
                self (1,1) ep_RunExpt2
                hObj (1,1)
            end
            self.ExptDispatch(string(hObj.Text));
        end

        function PsychTimerRunTime(self)
            % PsychTimerRunTime — Per-period runtime callback.
            arguments
                self (1,1) ep_RunExpt2
            end
            if isfield(self.RUNTIME,'HW') && self.RUNTIME.HW.mode == hw.DeviceState.Idle
                self.ExptDispatch("Stop")
                return
            end
            self.RUNTIME = feval(self.FUNCS.TIMERfcn.RunTime, self.RUNTIME);
        end

        function PsychTimerError(self)
            % PsychTimerError — Error handler for the runtime loop.
            arguments
                self (1,1) ep_RunExpt2
            end
            self.STATE = PRGMSTATE.ERROR;
            self.RUNTIME.ERROR = lasterror; %#ok<LERR>
            self.RUNTIME = feval(self.FUNCS.TIMERfcn.Error, self.RUNTIME);
            feval(self.FUNCS.SavingFcn, self.RUNTIME);
            self.UpdateGUIstate
            self.SaveDataCallback
        end

        function PsychTimerStop(self)
            % PsychTimerStop — Clean shutdown after the runtime loop ends.
            arguments
                self (1,1) ep_RunExpt2
            end
            self.STATE = PRGMSTATE.STOP;
            vprintf(3,'PsychTimerStop:Calling timer Stop function: %s',self.FUNCS.TIMERfcn.Stop)
            self.RUNTIME = feval(self.FUNCS.TIMERfcn.Stop, self.RUNTIME);
            vprintf(3,'PsychTimerStop:Calling UpdateGUIstate')
            self.UpdateGUIstate
            vprintf(3,'PsychTimerStop:Calling SaveDataCallback')
            self.SaveDataCallback
        end


        function subject_list_SelectionChanged(self, hObj, evnt)
            % subject_list_SelectionChanged — Display Subject Info
            arguments
                self (1,1) ep_RunExpt2
                hObj (1,1)
                evnt %#ok<INUSA>
            end
            disp(self.CONFIG(hObj.Selection(1)).SUBJECT)
        end

        function SetDefaultFuncs(self, F)
            % SetDefaultFuncs — Persist FUNCS selections to preferences.
            arguments
                self (1,1) ep_RunExpt2
                F (1,1) struct
            end
            setpref('ep_RunExpt_FUNCS','SavingFcn',    F.SavingFcn)
            setpref('ep_RunExpt_FUNCS','AddSubjectFcn',F.AddSubjectFcn)
            setpref('ep_RunExpt_FUNCS','BoxFig',       F.BoxFig)

            setpref('ep_RunExpt_TIMER','Start',     F.TIMERfcn.Start)
            setpref('ep_RunExpt_TIMER','RunTime',   F.TIMERfcn.RunTime)
            setpref('ep_RunExpt_TIMER','Stop',      F.TIMERfcn.Stop)
            setpref('ep_RunExpt_TIMER','Error',     F.TIMERfcn.Error)
        end

        function F = GetDefaultFuncs(self) %#ok<MANU>
            % GetDefaultFuncs — Load FUNCS selections from preferences.
            arguments
                self (1,1) ep_RunExpt2 %#ok<INUSA>
            end
            F.SavingFcn      = getpref('ep_RunExpt_FUNCS','SavingFcn',    'ep_SaveDataFcn');
            F.AddSubjectFcn  = getpref('ep_RunExpt_FUNCS','AddSubjectFcn','ep_AddSubject');
            F.BoxFig         = getpref('ep_RunExpt_FUNCS','BoxFig',       'ep_GenericGUI');

            F.TIMERfcn.Start    = getpref('ep_RunExpt_TIMER','Start',   'ep_TimerFcn_Start');
            F.TIMERfcn.RunTime  = getpref('ep_RunExpt_TIMER','RunTime', 'ep_TimerFcn_RunTime');
            F.TIMERfcn.Stop     = getpref('ep_RunExpt_TIMER','Stop',    'ep_TimerFcn_Stop');
            F.TIMERfcn.Error    = getpref('ep_RunExpt_TIMER','Error',   'ep_TimerFcn_Error');
        end

        function ClearConfig(self)
            % ClearConfig — Reset CONFIG and GUI to an unconfigured state.
            arguments
                self (1,1) ep_RunExpt2
            end
            self.CONFIG = struct('SUBJECT',[],'PROTOCOL',[],'RUNTIME',[],'protocol_fn',[]);
            if self.STATE >= PRGMSTATE.RUNNING, return, end
            self.STATE = PRGMSTATE.NOCONFIG;
            if isfield(self.H,'subject_list') && isgraphics(self.H.subject_list)
                set(self.H.subject_list,'Data',[])
            end
            self.CheckReady
        end


        function ConfigBrowserRestoreOnTop(self, ontop)
            arguments
                self (1,1) ep_RunExpt2
                ontop (1,1) logical
            end
            if ~isfield(self.H,'figure1') || ~isgraphics(self.H.figure1), return, end
            if ~isfield(self.H,'always_on_top') || ~isgraphics(self.H.always_on_top), return, end
            self.AlwaysOnTop(ontop)
        end
    end % methods (Access=private)

    methods (Static)
        ffn = defaultFilename(pth,name)
    end % methods (Static)
end
