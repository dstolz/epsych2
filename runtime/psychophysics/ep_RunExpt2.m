classdef ep_RunExpt2 < handle
    % ep_RunExpt2 — Run and manage psychophysics experiments with a UIFigure-based GUI.
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
    %   STATE — PRGMSTATE enum (lifecycle state)
    %   CONFIG       — Per-subject config array (SUBJECT/PROTOCOL/RUNTIME/protocol_fn)
    %   FUNCS        — Function handles/names for Saving/AddSubject/BoxFig/TIMERfcn
    %   RUNTIME      — Runtime state container shared with callbacks
    %   GVerbosity   — Verbosity level for vprintf()
    %
    % Notes
    %   External utilities are expected on-path: EPsychInfo, vprintf, figAlwaysOnTop,
    %   epsych.Helper, ep_CompiledProtocolTrials, ep_ExperimentDesign, and
    %   functions referenced by FUNCS.* and hw.* classes.
    %
    % Daniel.Stolzberg@gmail.com 2014–2025

    properties
        H % struct of UI handles
        STATE (1,1) PRGMSTATE = PRGMSTATE.NOCONFIG
        CONFIG (1,1)  struct = struct('SUBJECT',[],'PROTOCOL',[],'RUNTIME',[],'protocol_fn',[])
        FUNCS (1,1) struct
        RUNTIME (1,1) struct = struct()
        GVerbosity (1,1) double = 1

        dfltDataPath (1,1) string = cd
    end

    methods
        function self = ep_RunExpt2()
            % Constructor — Build UI, initialize callbacks, and clear config.
            %   Initializes the UIFigure, loads default function preferences,
            %   resets CONFIG, and updates the GUI to reflect readiness.

            % check if an instance of the gui already exists
            f = findobj('tag','ep_RunExpt2');
            if ~isempty(f)
                figure(f);
                movegui(f,'onscreen');
                self = f.UserData;
                return
            end


            self.buildUI
            self.FUNCS = self.GetDefaultFuncs;
            self.ClearConfig
            self.UpdateGUIstate

            self.dfltDataPath = getpref('ep_RunExpt','DataPath',cd);

            if nargout == 0, clear self; end
        end

        function delete(self)
            % Destructor — Ensures orderly shutdown and onClose handling.
            %   Invokes onCloseRequest if still valid to stop timers and
            %   release UI resources.
            try
                if isvalid(self)
                    self.onCloseRequest
                end
            catch
            end
        end

        function Run(self)
            % Run — Convenience wrapper to start experiment (Record mode).
            %   For legacy compatibility; forwards to ExptDispatch("Run").
            self.ExptDispatch("Run")
        end

        function Record(self)
            % Record — Start experiment in acquisition mode.
            %   Forwards to ExptDispatch("Record").
            self.ExptDispatch("Record")
        end

        function Preview(self)
            % Preview — Start non-recording preview session.
            %   Forwards to ExptDispatch("Preview").
            self.ExptDispatch("Preview")
        end

        function Pause(self)
            % Pause — Placeholder for future pause handling.
            %   Reserved for implementing a paused runtime state.
        end

        function Stop(self)
            % Stop — Halt the running experiment and timers.
            %   Forwards to ExptDispatch("Stop").
            self.ExptDispatch("Stop")
        end

        function SaveData(self)
            % SaveData — Trigger save using the configured SavingFcn.
            %   Calls SaveDataCallback to serialize RUNTIME via FUNCS.SavingFcn.
            self.SaveDataCallback
        end

        function LoadConfig(self, cfn)
            % LoadConfig — Load a .config file and apply stored functions.
            % Inputs
            %   cfn (string) — Optional config filepath; prompts if empty.
            % Behavior
            %   Loads CONFIG and FUNCS from file (if present), updates subject
            %   list, and sets STATE to READY when requirements are met.
            arguments
                self
                cfn string = ""
            end
            if self.STATE >= PRGMSTATE.RUNNING, return, end

            if strlength(cfn) == 0
                pn = getpref('ep_RunExpt_Setup','CDir',cd);
                [fn,pn] = uigetfile('*.config','Open Configuration File',pn);
                if isequal(fn,0), return, end
                setpref('ep_RunExpt_Setup','CDir',pn);
                cfn = fullfile(pn,fn);
            end

            if ~exist(cfn,'file')
                warndlg(sprintf('The file "%s" does not exist.',cfn),'RunExpt','modal')
                return
            end

            fprintf('Loading configuration file: ''%s''\n',cfn)
            warning('off','MATLAB:dispatcher:UnresolvedFunctionHandle');
            S = load(cfn,'-mat');
            warning('on','MATLAB:dispatcher:UnresolvedFunctionHandle');

            if ~isfield(S,'config')
                errordlg('Invalid Configuration file','PsychConfig','modal')
                return
            end

            self.ClearConfig
            self.CONFIG = S.config;

            if isfield(S,'funcs')
                self.FUNCS = S.funcs;
                self.SetDefaultFuncs(self.FUNCS)
            else
                self.FUNCS = self.GetDefaultFuncs;
            end

            self.UpdateSubjectList
            self.CheckReady
        end

        function SaveConfig(self)
            % SaveConfig — Persist CONFIG, FUNCS, and meta to a .config file.
            % Behavior
            %   Prompts for a destination, serializes current config/functions
            %   together with EPsychInfo meta for reproducibility.
            if self.STATE == PRGMSTATE.NOCONFIG
                warndlg('Please first add a subject.','Save Configuration','modal')
                return
            end

            pn = getpref('ep_RunExpt_Setup','CDir',cd);
            [fn,pn] = uiputfile('*.config','Save Current Configuration',pn);
            if isequal(fn,0)
                vprintf(1,'Configuration not saved.\n')
                return
            end

            config = self.CONFIG; %#ok<NASGU>
            funcs  = self.FUNCS;  %#ok<NASGU>

            E = EPsychInfo;
            meta = E.meta; %#ok<NASGU>

            save(fullfile(pn,fn),'config','funcs','meta','-mat')
            setpref('ep_RunExpt_Setup','CDir',pn)
            vprintf(0,'Configuration saved as: ''%s''\n',fullfile(pn,fn))
        end

        function ok = LocateProtocol(self, pfn)
            % LocateProtocol — Set or add the protocol file for a subject.
            % Inputs
            %   pfn (string) — Optional protocol filepath; prompts if empty.
            % Output
            %   ok (logical) — True when a valid protocol file is assigned.
            arguments
                self
                pfn string = ""
            end
            ok = false;
            if self.STATE >= PRGMSTATE.RUNNING, return, end

            if strlength(pfn) == 0
                pn = getpref('ep_RunExpt_Setup','PDir',cd);
                if ~exist(pn,'dir'), pn = cd; end
                [fn,pn] = uigetfile('*.prot','Locate Protocol',pn);
                if isequal(fn,0), return, end
                setpref('ep_RunExpt_Setup','PDir',pn);
                pfn = fullfile(pn,fn);
            end

            if ~exist(pfn,'file')
                warndlg(sprintf('The file "%s" does not exist.',pfn),'Psych Config','modal')
                return
            end

            if isempty(self.CONFIG) || isempty(self.CONFIG(1).PROTOCOL)
                self.CONFIG(1).protocol_fn = pfn;
            else
                self.CONFIG(end+1).protocol_fn = pfn;
            end
            ok = true;
        end

        function AddSubject(self, S)
            % AddSubject — Create a new subject entry and assign a protocol.
            % Inputs
            %   S (struct) — Optional pre-filled subject fields; dialog if empty.
            % Behavior
            %   Invokes FUNCS.AddSubjectFcn(S, boxids), enforces unique names,
            %   prompts for a protocol file, appends to CONFIG, and updates UI.
            arguments
                self
                S struct = struct()
            end
            if self.STATE >= PRGMSTATE.RUNNING, return, end

            boxids = 1:16;
            curboxids = [];
            curnames = {[]};
            if ~isempty(self.CONFIG) && ~isempty(self.CONFIG(1).SUBJECT)
                curboxids = arrayfun(@(c) c.SUBJECT.BoxID, self.CONFIG);
                curnames = arrayfun(@(c) c.SUBJECT.Name, self.CONFIG, 'uni', 0);
                boxids = setdiff(boxids,curboxids);
            end

            if ~isfield(self.FUNCS,'AddSubjectFcn') || isempty(self.FUNCS.AddSubjectFcn)
                self.FUNCS.AddSubjectFcn = getpref('ep_RunExpt','CONFIG_AddSubjectFcn','ep_AddSubject');
            end

            ontop = self.AlwaysOnTop(false);
            S = feval(self.FUNCS.AddSubjectFcn,S,boxids);
            self.AlwaysOnTop(ontop);

            if isempty(S) || ~isfield(S,'Name') || strlength(string(S.Name))==0, return, end

            if ~isempty(curnames{1}) && ismember(S.Name, curnames)
                warndlg(sprintf('The subject name "%s" is already in use.',S.Name),'Add Subject','modal')
                return
            end

            pn = getpref('ep_RunExpt_Setup','PDir',cd);
            if ~exist(pn,'dir'), pn = cd; end
            [fn,pn] = uigetfile('*.prot','Locate Protocol',pn);
            if isequal(fn,0), return, end
            setpref('ep_RunExpt_Setup','PDir',pn)
            pfn = fullfile(pn,fn);

            if ~exist(pfn,'file')
                warndlg(sprintf('The file "%s" does not exist.',pfn),'Psych Config','modal')
                return
            end

            if ~isfield(self.CONFIG, 'protocol_fn') || isempty(self.CONFIG(1).protocol_fn)
                self.CONFIG(1).protocol_fn = pfn;
            else
                self.CONFIG(end+1).protocol_fn = pfn;
            end

            self.CONFIG(end).SUBJECT = S;
            self.UpdateSubjectList
            self.CheckReady
        end

        function RemoveSubject(self, idx)
            % RemoveSubject — Delete a subject from CONFIG.
            % Inputs
            %   idx (double) — Optional row index; uses selected table row if NaN.
            % Behavior
            %   Removes the specified subject (or clears CONFIG if singleton)
            %   then updates the table and readiness state.
            arguments
                self
                idx double = NaN
            end
            if self.STATE >= PRGMSTATE.RUNNING, return, end

            if isnan(idx)
                idx = self.H.subject_list.Selection(1);
            end
            if isempty(idx) || isempty(self.CONFIG), return, end

            if isscalar(self.CONFIG)
                self.ClearConfig
            else
                self.CONFIG(idx) = [];
            end

            self.UpdateSubjectList
            self.CheckReady
        end

        function ViewTrials(self)
            % ViewTrials — Display compiled trial definitions for selection.
            % Behavior
            %   Loads the selected subject's protocol and shows trial summary
            %   using ep_CompiledProtocolTrials (truncated for readability).
            idx = self.H.subject_list.Selection(1);
            if isempty(idx), return, end

            warning('off','MATLAB:dispatcher:UnresolvedFunctionHandle');
            S = load(self.CONFIG(idx).protocol_fn,'protocol','-mat');
            warning('on','MATLAB:dispatcher:UnresolvedFunctionHandle');

            ep_CompiledProtocolTrials(S.protocol,'trunc',2000);
        end

        function EditProtocol(self)
            % EditProtocol — Launch protocol editor for selected subject.
            % Behavior
            %   Opens ep_ExperimentDesign with the selected protocol path/index.
            idx = self.H.subject_list.Selection(1);
            if isempty(idx), return, end

            self.AlwaysOnTop(false);
            ep_ExperimentDesign(char(self.CONFIG(idx).protocol_fn),idx);
        end

        function SortBoxes(self)
            % SortBoxes — Reorder CONFIG by SUBJECT.BoxID.
            % Behavior
            %   Rebuilds CONFIG so array order matches assigned BoxID values.
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

        function DefineSavingFcn(self, a)
            % DefineSavingFcn — Configure the data-saving function.
            % Inputs
            %   a — Function name/handle or 'default'; prompts if empty.
            % Requirements
            %   The function must accept one input (RUNTIME) and return no outputs.
            arguments
                self
                a = []
            end
            if self.STATE >= PRGMSTATE.RUNNING, return, end

            if ~isempty(a) && ischar(a) && strcmp(a,'default')
                a = 'ep_SaveDataFcn';
            elseif isempty(a) || ~isfield(self.FUNCS,'SavingFcn')
                if ~isfield(self.FUNCS,'SavingFcn') || isempty(self.FUNCS.SavingFcn)
                    self.FUNCS.SavingFcn = 'ep_SaveDataFcn';
                end
                ontop = self.AlwaysOnTop(false);
                a = inputdlg('Data Saving Function','Saving Function',1,{self.FUNCS.SavingFcn});
                self.AlwaysOnTop(ontop);
                a = char(a);
                if isempty(a), return, end
            end

            if isa(a,'function_handle'), a = func2str(a); end
            b = which(a);
            if isempty(b)
                ontop = self.AlwaysOnTop(false);
                errordlg(sprintf('The function ''%s'' was not found on the current path.',a),'Saving Function','modal')
                self.AlwaysOnTop(ontop);
                return
            end

            if nargin(a) ~= 1 || nargout(a) ~= 0
                ontop = self.AlwaysOnTop(false);
                errordlg('The Saving Data function must take 1 input and return 0 outputs.','Saving Function','modal')
                self.AlwaysOnTop(ontop);
                return
            end

            vprintf(0,'Saving Data function:\t%s\t(%s)\n',a,b)
            self.FUNCS.SavingFcn = a;
            self.CheckReady
        end

        function SetDataPath(self)
            % SetDataPath — Configure the default data-saving directory.
            ontop = self.AlwaysOnTop(false);
            pth = uigetdir(self.dfltDataPath,'Select Default Data Directory');
            self.AlwaysOnTop(ontop);

            if isequal(pth,0) || strlength(string(pth))==0, return, end

            pth = string(pth);

            self.dfltDataPath = pth;
            setpref('ep_RunExpt','DataPath',pth);

            self.CheckReady
        end


        function DefineAddSubject(self, a)
            % DefineAddSubject — Configure the subject creation function.
            % Inputs
            %   a — Function name/handle or 'default'; prompts if empty.
            % Expected Signature
            %   S = AddSubjectFcn(S, boxids)
            arguments
                self
                a = []
            end
            if self.STATE >= PRGMSTATE.RUNNING, return, end
            if ~isempty(a) && ischar(a) && strcmp(a,'default')
                a = 'ep_AddSubject';
            elseif isempty(a) || ~isfield(self.FUNCS,'AddSubjectFcn')
                if ~isfield(self.FUNCS,'AddSubjectFcn') || isempty(self.FUNCS.AddSubjectFcn)
                    self.FUNCS.AddSubjectFcn = 'ep_AddSubject';
                end
                ontop = self.AlwaysOnTop;
                self.AlwaysOnTop(false)
                if isa(self.FUNCS.AddSubjectFcn,'function_handle'), self.FUNCS.AddSubjectFcn = func2str(self.FUNCS.AddSubjectFcn); end
                a = inputdlg('Add Subject Fcn','Specify Custom Add Subject:',1,{self.FUNCS.AddSubjectFcn});
                self.AlwaysOnTop(ontop)
                a = char(a);
                if isempty(a), return, end
            end

            if isa(a,'function_handle'), a = func2str(a); end
            b = which(a);
            if isempty(b)
                ontop = self.AlwaysOnTop;
                self.AlwaysOnTop(false)
                errordlg(sprintf('The function ''%s'' was not found on the current path.',a),'Define Function','modal')
                self.AlwaysOnTop(ontop)
                return
            end

            fprintf('AddSubject function:\t%s\t(%s)\n',a,b)
            self.FUNCS.AddSubjectFcn = a;
            self.CheckReady
        end

        function DefineBoxFig(self, a)
            % DefineBoxFig — Configure the per-box behavior GUI function.
            % Inputs
            %   a — Function name/handle or 'default'; prompts if empty; empty to disable.
            % Expected Signature
            %   BoxFig(RUNTIME)
            arguments
                self
                a = []
            end
            if self.STATE >= PRGMSTATE.RUNNING, return, end

            if ~isempty(a) && ischar(a) && strcmp(a,'default')
                a = 'ep_GenericGUI';
            elseif isempty(a) || ~isfield(self.FUNCS,'BoxFig')
                if ~isfield(self.FUNCS,'BoxFig') || isempty(self.FUNCS.BoxFig)
                    self.FUNCS.BoxFig = 'ep_GenericGUI';
                end
                ontop = self.AlwaysOnTop;
                self.AlwaysOnTop(false);
                if isa(self.FUNCS.BoxFig,'function_handle'), self.FUNCS.BoxFig = func2str(self.FUNCS.BoxFig); end
                a = inputdlg('GUI Figure','Specify Custom GUI Figure:',1,{self.FUNCS.BoxFig});
                self.AlwaysOnTop(ontop);
                if isempty(a), return, end
                a = char(a);
            end

            if isempty(a)
                vprintf(0,'No GUI Figure specified. This is OK, but no figure will be called on start.')
                self.FUNCS.BoxFig = [];
                self.CheckReady
                return
            end

            if isa(a,'function_handle'), a = func2str(a); end
            b = which(a);
            if isempty(b)
                ontop = self.AlwaysOnTop;
                self.AlwaysOnTop(false)
                errordlg(sprintf('The figure ''%s'' was not found on the current path.',a),'Define Function','modal')
                self.AlwaysOnTop(ontop)
                return
            end

            vprintf(0,'GUI Figure:\t%s\t(%s)\n',a,b)
            self.FUNCS.BoxFig = a;
            self.CheckReady
        end

        function LocateBehaviorGUI(self)
            % LocateBehaviorGUI — Launch the configured behavior GUI.
            % Behavior
            %   Calls FUNCS.BoxFig(RUNTIME) if BoxFig is configured.
            if isempty(self.FUNCS.BoxFig), return, end
            feval(self.FUNCS.BoxFig, self.RUNTIME);
        end

        function originalState = AlwaysOnTop(self, ontop)
            % AlwaysOnTop — Toggle the main window "always on top" setting.
            % Inputs
            %   ontop (logical) — Optional; when omitted, flips current state.
            if nargin<2
                s = get(self.H.always_on_top,'Checked');
                ontop = strcmp(s,'off');
            end

            originalState = ontop;

            if ontop
                set(self.H.always_on_top,'Checked','on');
                set(self.H.figure1,'WindowStyle','alwaysontop');
            else
                set(self.H.always_on_top,'Checked','off');
                set(self.H.figure1,'WindowStyle','normal');
            end

            if nargout == 0, clear ontop; end

        end

        function version_info(~)
            % version_info — Display EPsych metadata in the command window.
            % Behavior
            %   Prints EPsychInfo.meta and returns focus to the command window.
            E = EPsychInfo;
            disp(E.meta)
            commandwindow
        end

        function verbosity(self)
            % verbosity — Set the global verbosity level via dialog.
            % Behavior
            %   Presents a list dialog and updates GVerbosity accordingly.
            options = {'0. No extraneous text'
                '1. Additional info'
                '2. Detailed info'
                '3. Highly detailed info'
                '4. Ludicrously detailed info'};
            [indx, tf] = listdlg('ListString', options, 'SelectionMode','single', ...
                'PromptString','Select the level of detail:', 'Name','Detail Level Selection', ...
                'InitialValue',self.GVerbosity+1, 'ListSize',[300,150]);
            if ~tf, return, end
            self.GVerbosity = indx-1;
            vprintf(1,'Verbosity set to %s',options{self.GVerbosity+1})
        end
    end % methods

    methods (Access=private)
        function buildUI(self)
            % buildUI — Create UIFigure, menus, layouts, and controls.
            % Behavior
            %   Assembles the main grid, subject table, bottom control bar, and
            %   right-side utilities using uigridlayout and uibutton components.

            f = uifigure('Name','EPsych','Tag','ep_RunExpt2', ...
                'Position',[100 100 700 300], ...
                'CloseRequestFcn', @(~,~) self.onCloseRequest);

            f.UserData = self;

            self.H.figure1 = f;
            

            movegui(f,'onscreen');

            % Menus
            mFile = uimenu(f,'Label','File');
            uimenu(mFile,'Label','Load Config...','MenuSelectedFcn', @(~,~) self.LoadConfig)
            uimenu(mFile,'Label','Save Config...','MenuSelectedFcn', @(~,~) self.SaveConfig)
            uimenu(mFile,'Label','Exit','Separator','on','MenuSelectedFcn', @(~,~) self.onCloseRequest)

            mCustom = uimenu(f,'Label','Customize');
            uimenu(mCustom,'Label','Define Saving Function...','MenuSelectedFcn', @(~,~) self.DefineSavingFcn)
            uimenu(mCustom,'Label','Define Save path...','MenuSelectedFcn', @(~,~) self.SetDataPath)
            uimenu(mCustom,'Label','Define Box GUI Function...','MenuSelectedFcn', @(~,~) self.DefineBoxFig)

            mView = uimenu(f,'Label','View');
            self.H.always_on_top = uimenu(mView,'Label','Always On Top','Checked','off', ...
                'MenuSelectedFcn', @(~,~) self.AlwaysOnTop);

            mHelp = uimenu(f,'Label','Help');
            uimenu(mHelp,'Label','Version Info','MenuSelectedFcn', @(~,~) self.version_info)
            uimenu(mHelp,'Label','Verbosity...','MenuSelectedFcn', @(~,~) self.verbosity)

            self.H.mnu_LaunchGUI = uimenu(mView,'Label','Launch Behavior GUI','Enable','off', ...
                'MenuSelectedFcn', @(~,~) self.LocateBehaviorGUI);

            
            g = uigridlayout(f,[2 2]);
            g.RowHeight   = {'1x',40};
            g.ColumnWidth = {'1x',100};
            g.RowSpacing = 8; g.ColumnSpacing = 8; g.Padding = [8 8 8 8];

            % ---------- Subject table (left, top) ----------
            self.H.subject_list = uitable(g, ...
                'Tag','subject_list', ...
                'Data',{}, ...
                'ColumnName',{'BoxID','Name','Protocol'}, ...
                'ColumnEditable',[false false false]);
            self.H.subject_list.Layout.Row = 1;
            self.H.subject_list.Layout.Column = 1;
            % In UIFIGURE, use SelectionChangedFcn
            self.H.subject_list.SelectionChangedFcn = @(h,ev) self.subject_list_SelectionChanged(h,ev);

            % ---------- Bottom control bar (Run/Preview/Pause/Stop) ----------
            gBottom = uigridlayout(g,[1 4]);
            gBottom.Layout.Row = 2; gBottom.Layout.Column = 1;
            gBottom.ColumnWidth = {'1x','1x','1x','1x'}; gBottom.RowHeight = {'1x'};
            gBottom.RowSpacing = 0; gBottom.ColumnSpacing = 8; gBottom.Padding = [0 0 0 0];

            self.H.ctrl_run = uibutton(gBottom,'push','Text','Run', ...
                'Tag','ctrl_run','FontWeight','bold','FontSize',18, ...
                'BackgroundColor',[0.20 0.75 0.20], 'FontColor','w', ...
                'ButtonPushedFcn', @(h,~) self.onCommand(h));

            self.H.ctrl_preview = uibutton(gBottom,'push','Text','Preview', ...
                'Tag','ctrl_preview','FontWeight','bold','FontSize',18, ...
                'BackgroundColor',[0.20 0.50 0.90], 'FontColor','w', ...
                'ButtonPushedFcn', @(h,~) self.onCommand(h));

            self.H.ctrl_pauseall = uibutton(gBottom,'push','Text','Pause', ...
                'Tag','ctrl_pauseall','FontWeight','bold','FontSize',18, ...
                'BackgroundColor',[1.00 0.80 0.20], 'FontColor','w', ...
                'ButtonPushedFcn', @(h,~) self.onCommand(h));

            self.H.ctrl_halt = uibutton(gBottom,'push','Text','Stop', ...
                'Tag','ctrl_halt','FontWeight','bold','FontSize',18, ...
                'BackgroundColor',[0.85 0.25 0.25], 'FontColor','w', ...
                'ButtonPushedFcn', @(h,~) self.onCommand(h));

            % ---------- Right-side vertical buttons (stacked) ----------
            gRight = uigridlayout(g,[4 1]);
            gRight.Layout.Row = 1; gRight.Layout.Column = 2;
            gRight.RowHeight = {'fit','fit','fit','fit'};
            gRight.RowSpacing = 8; gRight.Padding = [0 0 0 0];

            self.H.save_data = uibutton(gRight,'push','Text','Save Data', ...
                'Tag','save_data', 'ButtonPushedFcn', @(~,~) self.SaveData);

            self.H.setup_remove_subject = uibutton(gRight,'push','Text','Remove Subject', ...
                'Tag','setup_remove_subject','ButtonPushedFcn', @(~,~) self.RemoveSubject);

            self.H.edit_protocol = uibutton(gRight,'push','Text','Edit Protocol', ...
                'Tag','edit_protocol','ButtonPushedFcn', @(~,~) self.EditProtocol);

            self.H.view_trials = uibutton(gRight,'push','Text','View Trials', ...
                'Tag','view_trials','ButtonPushedFcn', @(~,~) self.ViewTrials);
        end

        function onCloseRequest(self)
            % onCloseRequest — Graceful shutdown of running experiment and UI.
            % Behavior
            %   Warns if running, stops/deletes timers, resets functions to
            %   preferences, and deletes the main figure.
            if self.STATE == PRGMSTATE.RUNNING
                b = questdlg('Experiment is currently running. Closing will stop the experiment.', ...
                    'Experiment','Close Experiment','Cancel','Cancel');
                if strcmp(b,'Cancel'), return, end

                if isfield(self.RUNTIME,'TIMER') && isvalid(timerfind('Name','PsychTimer'))
                    stop(self.RUNTIME.TIMER)
                    delete(self.RUNTIME.TIMER)
                end
            end

            self.SetDefaultFuncs(self.FUNCS)
            try
                delete(self.H.figure1)
            catch
            end
        end

        function onCommand(self, hObj)
            % onCommand — Route button clicks to the dispatcher.
            % Inputs
            %   hObj — The source button; its Text determines the command.
            % For uibuttons, use Text instead of String
            self.ExptDispatch(string(hObj.Text));
        end

        function ExptDispatch(self, COMMAND)
            % ExptDispatch — Core state dispatcher for run/preview/stop.
            % Inputs
            %   COMMAND (string) — "Run"|"Record"|"Preview"|"Stop".
            % Behavior
            %   Prepares RUNTIME, loads protocols, initializes hardware,
            %   configures/starts the PsychTimer, and manages Stop/cleanup.
            if COMMAND == "Run", COMMAND = "Record"; end

            switch COMMAND
                case {"Run","Record","Preview"}
                    drawnow

                    [~,~] = dos('wmic process where name="MATLAB.exe" CALL setpriority "high priority"');

                    fprintf('\n%s\n',repmat('~',1,50))

                    self.RUNTIME = struct();

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
                        
                        % Initialize default data filename
                        sn = self.RUNTIME.TRIALS.Subject.Name;
                        pth = fullfile(self.dfltDataPath,sn);
                        self.RUNTIME.TRIALS(i).DataFilename = ep_RunExpt2.defaultFilename(pth,sn);
                    end

                    self.RUNTIME.HELPER = epsych.Helper;

                    self.RUNTIME.TIMER = self.CreateTimer;

                    self.RUNTIME.HW.mode = hw.DeviceState(COMMAND);
                    vprintf(0,'System set to ''%s''',COMMAND)
                    pause(1)

                    start(self.RUNTIME.TIMER)

                    RUNTIME.HELPER.notify('ModeChange',epsych.ModeChangeEvent(hw.DeviceState.Record));

                    drawnow

                case 'Pause'
                    
                    RUNTIME.HELPER.notify('ModeChange',epsych.ModeChangeEvent(hw.DeviceState.Pause));


                case 'Stop'
                    self.STATE = PRGMSTATE.STOP;
                    set(self.H.figure1,'pointer','watch')

                    RUNTIME.HELPER.notify('ModeChange',epsych.ModeChangeEvent(hw.DeviceState.Stop));


                    vprintf(3,'ExptDispatch: Stopping BoxTimer')
                    t = timerfind('Name','BoxTimer');
                    if ~isempty(t), stop(t); delete(t); end

                    vprintf(3,'ExptDispatch: Stopping PsychTimer')
                    t = timerfind('Name','PsychTimer');
                    if ~isempty(t), stop(t); delete(t); end

                    vprintf(0,'Experiment stopped at %s',datetime("now",Format='dd-MMM-yyyy HH:mm'))

                    
            end

            self.UpdateGUIstate
        end

        function T = CreateTimer(self)
            % CreateTimer — Build (or rebuild) the main PsychTimer.
            % Output
            %   T — MATLAB timer object configured for the runtime loop.
            T = timerfind('Name','PsychTimer');
            if ~isempty(T)
                stop(T)
                delete(T)
            end

            T = timer('BusyMode','drop', ...
                'ExecutionMode','fixedSpacing', ...
                'Name','PsychTimer', ...
                'Period',0.01, ...
                'StartFcn',@(~,~) self.PsychTimerStart, ...
                'TimerFcn',@(~,~) self.PsychTimerRunTime, ...
                'ErrorFcn',@(~,~) self.PsychTimerError, ...
                'StopFcn', @(~,~) self.PsychTimerStop, ...
                'TasksToExecute',inf);
        end

        function PsychTimerStart(self)
            % PsychTimerStart — Initialize runtime and optional performance GUI.
            % Behavior
            %   Updates state, calls TIMERfcn.Start, records StartTime, and
            %   attempts to launch BoxFig if configured.
            self.STATE = PRGMSTATE.RUNNING;
            self.UpdateGUIstate

            self.RUNTIME = feval(self.FUNCS.TIMERfcn.Start, self.RUNTIME, self.CONFIG);
            self.RUNTIME.StartTime = datetime('now');
            vprintf(0,'Experiment started at %s',self.RUNTIME.StartTime)

            if isempty(self.FUNCS.BoxFig)
                vprintf(2,'No Behavior Performance GUI specified')
            else
                try
                    feval(self.FUNCS.BoxFig, self.RUNTIME);
                    set(self.H.mnu_LaunchGUI,'Enable','on')
                catch me
                    s = self.FUNCS.BoxFig;
                    if ~ischar(s), s = func2str(s); end
                    vprintf(0,1,me)
                    a = repmat('*',1,50);
                    set(self.H.mnu_LaunchGUI,'Enable','off')
                    vprintf(0,1,'%s\nFailed to launch behavior performance GUI: %s\n%s',a,s,a)
                end
            end
        end

        function PsychTimerRunTime(self)
            % PsychTimerRunTime — Per-period runtime callback.
            % Behavior
            %   Stops when hardware returns Idle; otherwise delegates loop
            %   work to TIMERfcn.RunTime(RUNTIME).
            if isfield(self.RUNTIME,'HW') && self.RUNTIME.HW.mode == hw.DeviceState.Idle
                self.ExptDispatch("Stop")
                return
            end
            self.RUNTIME = feval(self.FUNCS.TIMERfcn.RunTime, self.RUNTIME);
        end

        function PsychTimerError(self)
            % PsychTimerError — Error handler for the runtime loop.
            % Behavior
            %   Records last error, calls TIMERfcn.Error, saves data, and
            %   updates GUI state to reflect the error condition.
            self.STATE = PRGMSTATE.ERROR;
            self.RUNTIME.ERROR = lasterror; %#ok<LERR>
            self.RUNTIME = feval(self.FUNCS.TIMERfcn.Error, self.RUNTIME);
            feval(self.FUNCS.SavingFcn, self.RUNTIME);
            self.UpdateGUIstate
            self.SaveDataCallback
        end

        function PsychTimerStop(self)
            % PsychTimerStop — Clean shutdown after the runtime loop ends.
            % Behavior
            %   Calls TIMERfcn.Stop, refreshes GUI, and triggers save logic.
            self.STATE = PRGMSTATE.STOP;
            vprintf(3,'PsychTimerStop:Calling timer Stop function: %s',self.FUNCS.TIMERfcn.Stop)
            self.RUNTIME = feval(self.FUNCS.TIMERfcn.Stop, self.RUNTIME);
            vprintf(3,'PsychTimerStop:Calling UpdateGUIstate')
            self.UpdateGUIstate
            vprintf(3,'PsychTimerStop:Calling SaveDataCallback')
            self.SaveDataCallback
        end

        function SaveDataCallback(self)
            % SaveDataCallback — Invoke SavingFcn with UI-safe control state.
            % Behavior
            %   Disables controls during save, calls FUNCS.SavingFcn(RUNTIME),
            %   and restores GUI state per STATE.
            oldstate = self.STATE;
            % Temporarily disable controls during save without changing state enum
            try
                hCtrl = findobj(self.H.figure1,'-regexp','tag','^ctrl')';
                set([hCtrl self.H.save_data],'Enable','off')
            catch
            end

            vprintf(3,'SaveDataCallback: Saving via %s',self.FUNCS.SavingFcn)
            try
                vprintf(1,'Calling Saving Function: %s',self.FUNCS.SavingFcn)
                feval(self.FUNCS.SavingFcn, self.RUNTIME);
            catch me
                vprintf(0,1,me)
            end

            % Restore UI based on current state
            self.UpdateGUIstate
            
            self.STATE = oldstate;
            vprintf(3,'SaveDataCallback: Calling UpdateGUIstate')
            self.UpdateGUIstate
        end

        function CheckReady(self)
            % CheckReady — Evaluate readiness based on subjects and functions.
            % Behavior
            %   Sets STATE to CONFIGLOADED when both subjects and
            %   required functions are defined; otherwise to NOCONFIG.
            if self.STATE >= PRGMSTATE.RUNNING, return, end

            Subjects = ~isempty(self.CONFIG) && numel(self.CONFIG) > 0 && isfield(self.CONFIG,'SUBJECT') && ~isempty(self.CONFIG(1).SUBJECT);
            Functions = ~isempty(self.FUNCS) && ~any([isempty(self.FUNCS.SavingFcn); ...
                isempty(self.FUNCS.AddSubjectFcn); structfun(@isempty,self.FUNCS.TIMERfcn)]);

            isready = Subjects & Functions;
            if isready
                self.STATE = PRGMSTATE.CONFIGLOADED;
            else
                self.STATE = PRGMSTATE.NOCONFIG;
            end

            self.UpdateGUIstate
        end

        function UpdateGUIstate(self)
            % UpdateGUIstate — Enable/disable controls based on STATE.
            % Behavior
            %   Centralizes UI state transitions for all major states.
            

            hCtrl = findobj(self.H.figure1,'-regexp','tag','^ctrl')';
            set([hCtrl self.H.save_data],'Enable','off')

            hSetup = findobj(self.H.figure1,'-regexp','tag','^setup')';

            switch self.STATE
                case PRGMSTATE.NOCONFIG

                case PRGMSTATE.CONFIGLOADED
                    self.STATE = PRGMSTATE.READY;
                    set(self.H.view_trials,'Enable','on');
                    self.UpdateGUIstate

                case PRGMSTATE.READY
                    set([self.H.ctrl_run self.H.ctrl_preview hSetup']','Enable','on')

                case PRGMSTATE.RUNNING
                    set([self.H.ctrl_pauseall self.H.ctrl_halt],'Enable','on')
                    set(hSetup,'Enable','off')

                case PRGMSTATE.POSTRUN

                case PRGMSTATE.STOP
                    set([self.H.save_data self.H.ctrl_run self.H.ctrl_preview hSetup']','Enable','on')

                case PRGMSTATE.ERROR
                    set([self.H.save_data self.H.ctrl_run self.H.ctrl_preview hSetup']','Enable','on')
            end
        end

        function UpdateSubjectList(self)
            % UpdateSubjectList — Populate the subject uitable and controls.
            % Behavior
            %   Reflects CONFIG contents in the table and toggles action buttons.
            if self.STATE >= PRGMSTATE.RUNNING, return, end

            if isempty(self.CONFIG) || isempty(self.CONFIG(1).SUBJECT)
                set(self.H.subject_list,'data',[])
                set([self.H.setup_remove_subject self.H.view_trials],'Enable','off')
                return
            end

            for i = 1:length(self.CONFIG)
                data(i,1) = {self.CONFIG(i).SUBJECT.BoxID}; %#ok<AGROW>
                data(i,2) = {self.CONFIG(i).SUBJECT.Name};  %#ok<AGROW>
                [~,fn,~] = fileparts(self.CONFIG(i).protocol_fn);
                data(i,3) = {char(fn)}; %#ok<AGROW>
            end
            set(self.H.subject_list,'Data',data)

            if size(data,1) == 0
                set([self.H.setup_remove_subject self.H.view_trials],'Enable','off')
            else
                set([self.H.setup_remove_subject self.H.edit_protocol self.H.view_trials],'Enable','on')
            end
        end

        function subject_list_SelectionChanged(self, hObj, evnt)
            % subject_list_SelectionChanged — Display Subject Info
            disp(self.CONFIG(hObj.Selection(1)).SUBJECT)
        end

        function SetDefaultFuncs(self, F)
            % SetDefaultFuncs — Persist FUNCS selections to preferences.
            % Inputs
            %   F — Struct containing function names/handles for callbacks.
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
            % Output
            %   F — Struct of function names resolved from stored prefs.
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
            % Behavior
            %   Clears subjects/protocols, sets STATE to NOCONFIG, and
            %   empties the subject list if present.
            self.CONFIG = struct('SUBJECT',[],'PROTOCOL',[],'RUNTIME',[],'protocol_fn',[]);
            if self.STATE >= PRGMSTATE.RUNNING, return, end
            self.STATE = PRGMSTATE.NOCONFIG;
            if isfield(self.H,'subject_list') && isgraphics(self.H.subject_list)
                set(self.H.subject_list,'Data',[])
            end
            self.CheckReady
        end
    end %  methods (Access=private)



    methods (Static)
        function ffn = defaultFilename(pth,name)
            td = datetime('today');
            td.Format ="dd-MMM-uuuu";
            fn = sprintf('%s_%s.mat',name,td);

            ffn = fullfile(pth,fn);

            % avoid overwriting existing files
            % append _A, _B, etc.
            letters = char(65:90);
            k = 1;
            while isfile(ffn)
                fn = sprintf('%s_%s_%s.mat',name,td,letters(k));
                ffn = fullfile(pth,fn);
                k = k + 1;
            end
        end
    end % methods (Static)
end
