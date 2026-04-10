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
    % Documentation: documentation/overviews/RunExpt_GUI_Overview.md
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
                            epsych.RunExpt.saveFigurePosition(f(i).Position);
                            f(i).UserData = [];
                            f(i).CloseRequestFcn = [];
                            f(i).Tag = '';
                            delete(f(i));
                        catch
                        end
                    end
                else
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

        originalState = AlwaysOnTop(self, ontop)  % Set always-on-top state of main figure; returns previous state

        function version_info(self)
            % obj.version_info
            % Display toolbox version metadata in a dedicated dialog window.
            fig = findall(groot,'Type','figure','-and','Tag','RunExptVersionInfo');
            if ~isempty(fig) && isgraphics(fig(1))
                fig = fig(1);
                fig.Visible = 'on';
                movegui(fig,'onscreen');
                return
            end

            E = EPsychInfo;
            checksumText = self.formatVersionChecksum(E.chksum);
            commitText = self.formatVersionTimestamp(E.commitTimestamp);

            fig = uifigure('Name','EPsych Version Info', ...
                'Tag','RunExptVersionInfo', ...
                'Position',[100 100 560 520], ...
                'Resize','off', ...
                'Color',[0.97 0.98 1.00]);
            movegui(fig,'center');

            rootGrid = uigridlayout(fig,[3 1]);
            rootGrid.RowHeight = {92,'1x',44};
            rootGrid.ColumnWidth = {'1x'};
            rootGrid.RowSpacing = 12;
            rootGrid.Padding = [18 18 18 18];
            rootGrid.BackgroundColor = fig.Color;

            headerPanel = uipanel(rootGrid,'BorderType','none', ...
                'BackgroundColor',[0.13 0.25 0.47]);
            headerPanel.Layout.Row = 1;

            headerGrid = uigridlayout(headerPanel,[2 1]);
            headerGrid.RowHeight = {'fit','fit'};
            headerGrid.ColumnWidth = {'1x'};
            headerGrid.RowSpacing = 4;
            headerGrid.Padding = [16 14 16 14];
            headerGrid.BackgroundColor = headerPanel.BackgroundColor;

            titleLink = uihyperlink(headerGrid, ...
                'Text','EPsych', ...
                'URL',E.RepositoryURL);
            titleLink.FontSize = 24;
            titleLink.FontWeight = 'bold';
            titleLink.FontColor = [1 1 1];
            uilabel(headerGrid, ...
                'Text',sprintf('Version %s   Data %s',E.Version,E.DataVersion), ...
                'FontSize',13, ...
                'FontColor',[0.89 0.93 1.00]);

            cardPanel = uipanel(rootGrid,'BorderType','none', ...
                'BackgroundColor',[1 1 1], ...
                'Scrollable','on');
            cardPanel.Layout.Row = 2;

            cardGrid = uigridlayout(cardPanel,[9 2]);
            cardGrid.ColumnWidth = {140,'1x'};
            cardGrid.RowHeight = {'fit','fit','fit','fit','fit','fit','fit','fit','fit'};
            cardGrid.RowSpacing = 8;
            cardGrid.ColumnSpacing = 14;
            cardGrid.Padding = [16 16 16 12];
            cardGrid.BackgroundColor = cardPanel.BackgroundColor;

            self.addVersionInfoRow(cardGrid,1,'Author',E.Author);
            self.addVersionInfoLinkRow(cardGrid,2,'Email',E.AuthorEmail,['mailto:' E.AuthorEmail]);
            self.addVersionInfoLinkRow(cardGrid,3,'License',E.License,E.LicenseURL);
            self.addVersionInfoRow(cardGrid,4,'Copyright',E.Copyright);
            self.addVersionInfoRow(cardGrid,5,'Latest Commit',commitText);
            self.addVersionInfoRow(cardGrid,6,'Checksum',checksumText);
            self.addVersionInfoLinkRow(cardGrid,7,'Repository', ...
                'GitHub Repository',E.RepositoryURL);
            self.addVersionInfoLinkRow(cardGrid,8,'History', ...
                'Commit History Overview',E.CommitHistoryURL);
            self.addVersionInfoLinkRow(cardGrid,9,'Wiki', ...
                'Repository Wiki',E.WikiURL);

            footerGrid = uigridlayout(rootGrid,[1 2]);
            footerGrid.Layout.Row = 3;
            footerGrid.ColumnWidth = {'1x',90};
            footerGrid.RowHeight = {'1x'};
            footerGrid.Padding = [0 0 0 0];
            footerGrid.BackgroundColor = fig.Color;

            uilabel(footerGrid, ...
                'Text','Links open in your default browser.', ...
                'FontAngle','italic', ...
                'FontColor',[0.35 0.39 0.46]);

            uibutton(footerGrid,'push', ...
                'Text','Close', ...
                'ButtonPushedFcn', @(~,~) delete(fig));
        end

        function AssignRuntimeToCommandWindow(self)
            % obj.AssignRuntimeToCommandWindow
            % Export the RUNTIME object to the base workspace as 'RUNTIME'.
            assignin('base','RUNTIME',self.RUNTIME);
            vprintf(0,'Assigned `RunExpt.RUNTIME` to workspace variable `RUNTIME`.')
            commandwindow
        end

        OpenCurrentErrorLog(self)      % Open today's EPsych error log in the OS-associated text editor

        verbosity(self, varargin)  % Set or query the global output verbosity level
    end

    methods (Access=private)
        buildUI(self)                                      % Build main figure and all UI components
        onFigureKeyPress(self, evt)                        % Handle key-press events on the main figure
        onCloseRequest(self)                               % Stop experiment if running and destroy the figure
        SaveDataCallback(self)                             % Invoke the configured data-saving callback
        recent = GetRecentConfigs(self)                    % Return config paths loaded within the past seven days
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

        function commitText = formatVersionTimestamp(~, commitTimestamp)
            % commitText = formatVersionTimestamp(self, commitTimestamp)
            % Format the latest commit timestamp for display in the version info dialog.
            if isdatetime(commitTimestamp)
                if isnat(commitTimestamp)
                    commitText = 'Unavailable';
                else
                    commitText = datestr(commitTimestamp,'ddd, mmm dd, yyyy HH:MM PM');
                end
                return
            end

            if ischar(commitTimestamp) || isstring(commitTimestamp)
                commitText = char(string(commitTimestamp));
                return
            end

            commitText = 'Unavailable';
        end
    end

    methods (Static)
        position = getSavedFigurePosition(defaultPosition)
        saveFigurePosition(position)
        ffn = defaultFilename(pth,name)
    end
end

