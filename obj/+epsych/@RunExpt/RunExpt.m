classdef RunExpt < handle
    % Run and manage experiment sessions from the main RunExpt GUI.
    %
    % Constructing epsych.RunExpt creates or reuses the session window, loads
    % configuration files when requested, and coordinates CONFIG, FUNCS, and
    % RUNTIME state for the active run.
    %
    % Important properties:
    %   CONFIG   - Per-subject protocol and runtime configuration entries.
    %   FUNCS    - Callback names for saving, timers, and auxiliary GUIs.
    %   RUNTIME  - Shared epsych.Runtime state for the active session.
    %
    % Documentation: documentation/overviews/RunExpt_GUI_Overview.md
    % See also: epsych.Runtime, ep_ExperimentDesign, ep_CompiledProtocolTrials.

    properties
        H                                                                                        % Handles to UI components and figures
        STATE (1,1) PRGMSTATE = PRGMSTATE.NOCONFIG                                              % Current experiment program state
        % One element per subject. Declared (1,:) rather than (1,1) because
        % AddSubject appends via CONFIG(numel+1); a scalar constraint here made
        % every multi-subject session fail with "Value must be a scalar".
        CONFIG (1,:) struct = struct('SUBJECT',[],'PROTOCOL',[],'RUNTIME',[],'protocol_fn',[])  % Per-subject configuration array; each element holds SUBJECT, PROTOCOL, RUNTIME, and protocol_fn
        FUNCS (1,1) struct = struct()                                                            % Preference-backed callback function names for saving, timers, and GUI
        RUNTIME (1,1) epsych.Runtime = epsych.Runtime                                           % Shared runtime state passed to all callbacks during the session
        dfltDataPath (1,1) string = cd                                                          % Default directory for saving experiment data
        IsClosing (1,1) logical = false                                                         % True while the close sequence is in progress; prevents re-entrant callbacks
        CurrentConfigFile (1,1) string = ""                                                     % Path of the most recently loaded/saved configuration file
    end

    properties (Access = private)
        VlcRecorder_ = []          % Lazily-created hw.VlcRecorder backing the webcam setup dialog
        VlcRecorderSetupGUI_ = []  % Currently-open gui.VlcRecorderSetup instance, if any
        VideoRecordingActive_ (1,1) logical = false  % True only while a run-owned VLC recording is in progress
        VideoLiveViewActive_ (1,1) logical = false   % True only while a display-only (non-recording) VLC view is open
        % Last STATE announced on the status bar, so a repeated UpdateGUIstate
        % refresh does not overwrite the more specific message an action posted.
        LastStatusState_ (1,1) PRGMSTATE = PRGMSTATE.NOCONFIG
        StatusStateReported_ (1,1) logical = false   % False until the first state message is posted
    end

    methods
        LoadConfig(self, cfn)           % Load configuration from MAT file cfn
        RefreshConfig(self)             % Reload the currently loaded configuration file from disk
        SaveConfig(self)                % Persist current configuration to file
        ok = LocateProtocol(self, pfn)  % Validate and register protocol file pfn; ok is true on success
        AddSubject(self, S)             % Append subject struct S to CONFIG
        RemoveSubject(self, idx)        % Remove subject at index idx from CONFIG

        DefineSavingFcn(self, a)        % Set the data-saving callback function name
        DefineConfigBrowserRoot(self)   % Set the root folder used by the config browser
        BrowseConfigs(self)             % Open the config browser dialog

        DefineAddSubject(self, a)       % Set the add-subject callback function name
        DefineBoxFig(self, a)           % Set the behavioral box figure callback function name
        DefineTimerPeriod(self)         % Set the PsychTimer period (0.001–1 s)
        DefineLogPath(self)             % Set the directory +eplog writes daily error logs to

        OpenCustomizeDialog(self)       % Open unified Customize Settings dialog for all Define* settings
        OpenSelfTest(self)              % Open the pre-flight self-test window

        % Public because it is a pure UI refresh with no invariant to protect,
        % and epsych.SelfTest drives it to verify the control-enable contract.
        UpdateGUIstate(self)            % Refresh all UI control states to match current STATE

        ToggleVideoLiveView(self)       % Show/hide the webcam stream without recording it

        % Public so custom box GUIs, save functions, and trial selectors can
        % report their own progress in the session window.
        setStatus(self, message, nextStep)  % Post a message to the status bar

        function self = RunExpt(ffnConfig, opts)
            % self = RunExpt()
            % self = RunExpt(ffnConfig)
            % self = RunExpt(ffnConfig, Name=Value)
            % Create or reactivate the main experiment control window.
            %
            % Parameters:
            %	ffnConfig	- Configuration MAT file to load after the GUI is created.
            %	Name-Value options:
            %		Verbosity           - Override global verbosity level (nonnegative integer).
            %		ReuseExisting       - Reuse an active RunExpt instance when available.
            %		CleanupStaleFigures - Remove duplicate/stale RunExpt figures during startup.
            %		BringToFront        - Bring reused RunExpt figure to the foreground.
            %		Run                 - Start the experiment immediately after loading config (requires ffnConfig).
            %
            % Returns:
            %	self	- Existing or newly created RunExpt instance.
            arguments
                ffnConfig (1,1) string = ""
                opts.Verbosity = []
                opts.ReuseExisting (1,1) logical = true
                opts.CleanupStaleFigures (1,1) logical = true
                opts.BringToFront (1,1) logical = true
                opts.Run (1,1) logical = false
            end
            global GVerbosity

            if ~isempty(opts.Verbosity)
                validateattributes(opts.Verbosity, {'numeric'}, {'scalar','integer','nonnegative','finite'});
                GVerbosity = double(opts.Verbosity);
            elseif isempty(GVerbosity) || ~isnumeric(GVerbosity)
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
                    if opts.ReuseExisting && isempty(existingInstance)
                        existingFigure = f(i);
                        existingInstance = candidate;
                    elseif opts.CleanupStaleFigures
                        try
                            epsych.RunExpt.saveFigurePosition(f(i).Position);
                            f(i).UserData = [];
                            f(i).CloseRequestFcn = [];
                            f(i).Tag = '';
                            delete(f(i));
                        catch
                        end
                    end
                elseif opts.CleanupStaleFigures
                    try
                        epsych.RunExpt.saveFigurePosition(f(i).Position);
                        f(i).UserData = [];
                        f(i).CloseRequestFcn = [];
                        f(i).Tag = '';
                        delete(f(i));
                    catch
                    end
                end
            end

            if ~isempty(existingInstance)
                if opts.BringToFront
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
                end
                self = existingInstance;

                if ffnConfig ~= ""
                    self.LoadConfig(ffnConfig)
                    if opts.Run && self.STATE >= PRGMSTATE.CONFIGLOADED
                        self.ExptDispatch("Run")
                    end
                end

                return
            end

            self.buildUI
            self.FUNCS = self.GetDefaultFuncs;
            self.ClearConfig
            self.UpdateGUIstate
            self.dfltDataPath = getpref('RunExpt','DataPath',cd);
            self.promptForDataPath_

            if ffnConfig ~= ""
                self.LoadConfig(ffnConfig)
                if opts.Run && self.STATE >= PRGMSTATE.CONFIGLOADED
                    self.ExptDispatch("Run")
                end
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


        ViewTrials(self)  % Display a preview of compiled trials for the selected subject

        function EditProtocol(self)
            % obj.EditProtocol
            % Open the selected subject's protocol in ProtocolDesigner.
            selection = self.H.subject_list.Selection;
            if isempty(selection), return, end

            idx = selection(1);
            protocolFile = string(self.CONFIG(idx).protocol_fn);
            if strlength(protocolFile) == 0 || ~isfile(protocolFile)
                errordlg(sprintf('The protocol file "%s" could not be found.', protocolFile), ...
                    'EPsych', 'modal');
                return
            end

            self.AlwaysOnTop(false);
            epsych.ProtocolDesigner.openFromFile(protocolFile);
        end

        function UpdateProtocol(self)
            % obj.UpdateProtocol
            % Reload the selected subject's protocol from its file on disk so
            % the session uses the latest saved version of that protocol.
            if self.STATE >= PRGMSTATE.RUNNING, return, end

            selection = self.H.subject_list.Selection;
            if isempty(selection)
                uialert(self.H.figure1,'Select a subject first.','EPsych','Icon','info');
                return
            end
            idx = selection(1);

            protocolFile = char(self.CONFIG(idx).protocol_fn);
            if isempty(protocolFile) || ~isfile(protocolFile)
                uialert(self.H.figure1, ...
                    sprintf('The protocol file "%s" could not be found.',protocolFile), ...
                    'EPsych','Icon','error');
                return
            end

            oldVersion = '';
            proto = self.CONFIG(idx).PROTOCOL;
            if isa(proto,'epsych.Protocol') && isvalid(proto)
                oldVersion = char(proto.meta.protocolVersion);
            end

            warning('off','MATLAB:dispatcher:UnresolvedFunctionHandle');
            try
                newProtocol = epsych.Protocol.load(protocolFile);
            catch ME
                warning('on','MATLAB:dispatcher:UnresolvedFunctionHandle');
                vprintf(0,1,ME);
                uialert(self.H.figure1, ...
                    sprintf('Failed to load protocol "%s".',protocolFile),'EPsych','Icon','error');
                return
            end
            warning('on','MATLAB:dispatcher:UnresolvedFunctionHandle');

            self.CONFIG(idx).PROTOCOL = newProtocol;

            name       = self.CONFIG(idx).SUBJECT.Name;
            newVersion = char(newProtocol.meta.protocolVersion);
            self.reportProtocolValidation(newProtocol, name);

            if strcmp(oldVersion, newVersion)
                vprintf(1,'Reloaded protocol for subject "%s" (version %s; already latest).',name,newVersion);
                uialert(self.H.figure1, ...
                    sprintf('Subject "%s" is already using the latest protocol version (%s).',name,newVersion), ...
                    'EPsych','Icon','info');
            else
                vprintf(1,'Updated protocol for subject "%s": %s -> %s.',name,oldVersion,newVersion);
                uialert(self.H.figure1, ...
                    sprintf('Updated protocol for subject "%s" to version %s.',name,newVersion), ...
                    'EPsych','Icon','success');
            end

            self.UpdateSubjectList
            self.CheckReady
        end

        function ChangeProtocolFile(self)
            % obj.ChangeProtocolFile
            % Assign a different protocol file to the selected subject.
            if self.STATE >= PRGMSTATE.RUNNING, return, end

            selection = self.H.subject_list.Selection;
            if isempty(selection)
                uialert(self.H.figure1,'Select a subject first.','EPsych','Icon','info');
                return
            end
            idx = selection(1);

            pn = getpref('ep_RunExpt_Setup','PDir',cd);
            if ~exist(pn,'dir'), pn = cd; end

            ontop = self.AlwaysOnTop(false);
            [fn,pn] = uigetfile({'*.eprot;*.prot','Protocol Files (*.eprot, *.prot)'; ...
                '*.*','All Files (*.*)'},'Locate Protocol',pn);
            self.AlwaysOnTop(ontop);
            if isequal(fn,0), return, end
            setpref('ep_RunExpt_Setup','PDir',pn)
            pfn = fullfile(pn,fn);

            warning('off','MATLAB:dispatcher:UnresolvedFunctionHandle');
            try
                newProtocol = epsych.Protocol.load(pfn);
            catch ME
                warning('on','MATLAB:dispatcher:UnresolvedFunctionHandle');
                vprintf(0,1,ME);
                uialert(self.H.figure1, ...
                    sprintf('Failed to load protocol "%s".',pfn),'EPsych','Icon','error');
                return
            end
            warning('on','MATLAB:dispatcher:UnresolvedFunctionHandle');

            self.CONFIG(idx).protocol_fn = pfn;
            self.CONFIG(idx).PROTOCOL    = newProtocol;

            name = self.CONFIG(idx).SUBJECT.Name;
            self.reportProtocolValidation(newProtocol, name);
            vprintf(1,'Assigned protocol "%s" to subject "%s".',fn,name);

            self.UpdateSubjectList
            self.CheckReady
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

        LaunchUtility(self, target)      % Open a standalone tool from the Utilities menu

        function LaunchCommutatorGUI(self)
            % obj.LaunchCommutatorGUI
            % Launch the Commutator GUI
            comPort = getpref('ep_RunExpt_Commutator','Port',"COM6");
            try
                peripherals.NanoMotorControlGUI(Port=comPort);
            catch me
                vprintf(0,1,me)
                a = repmat('*',1,50);
                vprintf(0,1,'%s\nFailed to launch Commutator GUI: %s\n%s',a,comPort,a)
            end
        end

        function OpenVlcRecorderSetup(self)
            % obj.OpenVlcRecorderSetup
            % Open the webcam recorder configuration dialog (gui.VlcRecorderSetup),
            % seeded from the 'ep_RunExpt_Video' preference group so values applied
            % in a previous session round-trip.
            if ~isempty(self.VlcRecorderSetupGUI_) && isvalid(self.VlcRecorderSetupGUI_)
                try
                    figure(self.VlcRecorderSetupGUI_.Parent);
                catch
                end
                return
            end

            % The dialog stops the recorder and opens the camera itself, which
            % would tear down a live view behind the UI's back.
            self.StopVideoLiveView_;

            rec = self.getVlcRecorder_();

            try
                self.VlcRecorderSetupGUI_ = rec.setupGUI();
            catch ME
                vprintf(0,1,ME)
            end
        end

        originalState = AlwaysOnTop(self, ontop)  % Set always-on-top state of main figure; returns previous state

        version_info(self)  % Display toolbox version metadata in a dedicated dialog window

        function AssignRuntimeToCommandWindow(self)
            % obj.AssignRuntimeToCommandWindow
            % Export the RUNTIME object to the base workspace as 'RUNTIME'.
            assignin('base','RUNTIME',self.RUNTIME);
            vprintf(0,'Assigned `RunExpt.RUNTIME` to workspace variable `RUNTIME`.')
            commandwindow
        end

        OpenCurrentErrorLog(self, useExternalViewer)  % Open today's EPsych error log outside the MATLAB editor

        verbosity(self, varargin)  % Set or query the global output verbosity level

        requestRecompile(self, subjectIdx)  % Request a safe-boundary Protocol recompile for subject subjectIdx
    end

    methods (Access=private)
        buildUI(self)                                      % Build main figure and all UI components
        onFigureKeyPress(self, evt)                        % Handle key-press events on the main figure
        onCloseRequest(self)                               % Stop experiment if running and destroy the figure
        SaveDataCallback(self)                             % Invoke the configured data-saving callback
        recent = GetRecentConfigs(self)                    % Return config paths loaded within the past seven days
        LoadRecentConfig(self, cfn)                        % Load config at path cfn and update recents list
        RememberRecentConfig(self, cfn)                    % Add cfn to the persistent recent config registry
        recent = GetRecentFuncs(self, prefKey)             % Return the MRU function-name list for a Customize dialog field
        RememberRecentFunc(self, prefKey, name)            % Record an accepted function name in a Customize dialog field's MRU list
        UpdateRecentConfigsMenu(self)                      % Rebuild the recent-configs submenu items
        ClearRecentConfigs(self)                           % Empty the persistent recent config registry
        CheckReady(self)                                   % Evaluate whether all conditions to run are met and update STATE
        UpdateSubjectList(self)                            % Repopulate the subject list and flag subjects with an outdated protocol version
        ExptDispatch(self, COMMAND)                        % Dispatch a named command (Start/Stop/Pause) to the experiment
        T = CreateTimer(self)                              % Create and configure the psychophysics trial timer object
        PsychTimerStart(self)                              % Initialize runtime state and start the trial timer

        [items, fullpaths] = FindConfigFiles(self, root)   % Recursively find config MAT files under root directory
        ConfigBrowserLoad(self, fig, lb)                   % Load config selected in list box lb and close fig
        ConfigBrowserCancel(self, fig)                     % Close config browser figure without loading

        rec = getVlcRecorder_(self)                        % Lazily create/return the shared, preference-seeded hw.VlcRecorder
        configureIntanRecorder_(self, interfaces)          % Seed hw.Intan_RHX interfaces from the ep_RunExpt_Intan pref group before they connect
        StartVideoRecording_(self)                          % Begin the per-run webcam recording when the checkbox/preference is enabled
        StopVideoRecording_(self)                           % Stop the active per-run webcam recording, if any
        StopVideoLiveView_(self)                            % Close the display-only webcam view, if any
        UpdateVideoLiveViewUI_(self)                        % Sync the live-view menu item and bottom-bar banner with VideoLiveViewActive_
        promptForDataPath_(self)                            % Ask for the default data directory when the DataPath preference was never set

        function onCommand(self, hObj)
            % Adapts menu item callbacks; forwards the item's text label to ExptDispatch.
            hCtrl = findobj(self.H.figure1, '-regexp', 'tag', '^ctrl')';
            set(hCtrl, 'Enable', 'off');
            drawnow
            previousState = self.STATE;
            commandText = string(hObj.Text);
            try
                self.ExptDispatch(commandText);
            catch ME
                % Restore a usable UI state when command dispatch fails.
                self.StopVideoRecording_;
                if isfield(self.H,'figure1') && isgraphics(self.H.figure1)
                    set(self.H.figure1,'pointer','arrow');
                end
                if previousState < PRGMSTATE.RUNNING
                    self.STATE = previousState;
                else
                    self.STATE = PRGMSTATE.ERROR;
                end
                self.UpdateGUIstate;
                vprintf(0,1,ME);
                self.setStatus(sprintf('%s failed: %s',commandText,ME.message), ...
                    'see Help > Open Current Error Log.');
            end
        end

        function PsychTimerRunTime(self)
            % Timer runtime callback; stops the experiment automatically if hardware enters idle state.
            if any(get(self.RUNTIME.Interfaces,'mode') == hw.DeviceState.Idle)
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
            self.UpdateGUIstate
            self.SaveDataCallback
        end

        function PsychTimerStop(self)
            % Timer stop callback; invokes the stop handler, updates GUI state, and saves data.
            self.STATE = PRGMSTATE.STOP;
            % Stop video before the save handler so recordings never run through a save dialog;
            % this is the single choke point for user Stop, auto-stop, and post-error StopFcn.
            self.StopVideoRecording_;
            vprintf(3,'PsychTimerStop:Calling timer Stop function: %s',self.FUNCS.TIMERfcn.Stop)
            self.RUNTIME = feval(self.FUNCS.TIMERfcn.Stop, self.RUNTIME);
            vprintf(3,'PsychTimerStop:Calling UpdateGUIstate')
            self.UpdateGUIstate
            vprintf(3,'PsychTimerStop:Calling SaveDataCallback')
            self.SaveDataCallback
        end

        subject_list_SelectionChanged(self, hObj, evt)  % Prints subject and protocol info to the command window when selection changes

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
            setpref('ep_RunExpt_TIMER','Period',    F.TimerPeriod)
        end

        function F = GetDefaultFuncs(self)
            % F = GetDefaultFuncs(self)
            % Load all callback function names from MATLAB preferences into struct F.
            % Stored values that are no longer resolvable are silently reset to the
            % current built-in defaults.
            DFLT_ADD_SUBJECT = 'epsych.DefaultSubject.open';
            stored = getpref('ep_RunExpt_FUNCS','AddSubjectFcn', DFLT_ADD_SUBJECT);
            % Validate: accept the built-in static method or any function on the path
            if strcmp(stored, DFLT_ADD_SUBJECT)
                F.AddSubjectFcn = stored;
            elseif ~isempty(which(stored))
                F.AddSubjectFcn = stored;
            else
                vprintf(1, 'Stored AddSubjectFcn ''%s'' not found; resetting to default.\n', stored);
                F.AddSubjectFcn = DFLT_ADD_SUBJECT;
                setpref('ep_RunExpt_FUNCS', 'AddSubjectFcn', DFLT_ADD_SUBJECT);
            end

            F.SavingFcn      = getpref('ep_RunExpt_FUNCS','SavingFcn',    'ep_SaveDataFcn');
            F.BoxFig         = getpref('ep_RunExpt_FUNCS','BoxFig',       'ep_GenericGUI');

            F.TIMERfcn.Start    = getpref('ep_RunExpt_TIMER','Start',   'ep_TimerFcn_Start');
            F.TIMERfcn.RunTime  = getpref('ep_RunExpt_TIMER','RunTime', 'ep_TimerFcn_RunTime');
            F.TIMERfcn.Stop     = getpref('ep_RunExpt_TIMER','Stop',    'ep_TimerFcn_Stop');
            F.TIMERfcn.Error    = getpref('ep_RunExpt_TIMER','Error',   'ep_TimerFcn_Error');
            F.TimerPeriod       = getpref('ep_RunExpt_TIMER','Period',   0.01);
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

        function reportProtocolValidation(~, protocol, subjectName)
            % reportProtocolValidation(self, protocol, subjectName)
            % Log protocol validation errors so the user can review before running.
            report = protocol.validate();
            errs = report([report.severity] == 2);
            if ~isempty(errs)
                vprintf(0,1,'Protocol for subject "%s" has %d validation error(s). Review before starting.', ...
                    subjectName, numel(errs));
            end
        end

        function ConfigBrowserRestoreOnTop(self, ontop)
            % ConfigBrowserRestoreOnTop(self, ontop)
            % Restore the always-on-top state of the main figure after a config browser closes.
            if ~isfield(self.H,'figure1') || ~isgraphics(self.H.figure1), return, end
            if ~isfield(self.H,'always_on_top') || ~isgraphics(self.H.always_on_top), return, end
            self.AlwaysOnTop(ontop);
        end

        function addVersionInfoRow(~, parent, rowIdx, labelText, valueText)
            % addVersionInfoRow(self, parent, rowIdx, labelText, valueText)
            % Create a label/value row in the version info dialog.
            lbl = uilabel(parent,'Text',[labelText ':']);
            lbl.Layout.Row = rowIdx;
            lbl.Layout.Column = 1;
            lbl.FontWeight = 'bold';
            lbl.FontColor = [0.21 0.25 0.31];

            value = uilabel(parent,'Text',string(valueText));
            value.Layout.Row = rowIdx;
            value.Layout.Column = 2;
            value.WordWrap = 'on';
            value.FontColor = [0.16 0.18 0.23];
        end

        function addVersionInfoLinkRow(~, parent, rowIdx, labelText, linkText, url)
            % addVersionInfoLinkRow(self, parent, rowIdx, labelText, linkText, url)
            % Create a label/hyperlink row in the version info dialog.
            lbl = uilabel(parent,'Text',[labelText ':']);
            lbl.Layout.Row = rowIdx;
            lbl.Layout.Column = 1;
            lbl.FontWeight = 'bold';
            lbl.FontColor = [0.21 0.25 0.31];

            link = uihyperlink(parent,'Text',string(linkText),'URL',char(url));
            link.Layout.Row = rowIdx;
            link.Layout.Column = 2;
            link.FontColor = [0.00 0.35 0.72];
        end

        function checksumText = formatVersionChecksum(~, checksum)
            % checksumText = formatVersionChecksum(self, checksum)
            % Normalize the git checksum display for the version info dialog.
            if ischar(checksum) || (isstring(checksum) && strlength(checksum) > 0)
                checksumText = char(string(checksum));
                return
            end

            checksumText = 'Unavailable';
        end

        commitText = formatVersionTimestamp(self, commitTimestamp)  % Format the latest commit timestamp for display in the version info dialog
    end

    methods (Static)
        position = getSavedFigurePosition(defaultPosition)
        saveFigurePosition(position)
        ffn = defaultFilename(pth,name)
        ffn = videoRecordingFilename(rootDir, dataFilename)  % Build the .ts recording path under rootDir that pairs by name with a behavioral data file

        function app = defaultLogViewer()
            % app = epsych.RunExpt.defaultLogViewer()
            % The plain-text application to hand the error log to when the
            % operator asks for it outside MATLAB.
            %
            % MATLAB installs itself as the handler for .txt on many machines,
            % which is exactly what "open this outside the editor" is trying to
            % escape, so the fallback names a text viewer rather than relying
            % on the file association.
            if ispc
                app = 'notepad.exe';
            elseif ismac
                app = 'TextEdit';
            else
                app = 'xdg-open';
            end
        end
    end
end

