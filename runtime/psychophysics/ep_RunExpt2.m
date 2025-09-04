classdef ep_RunExpt2 < handle
    % ep_RunExpt2
    %
    % Run Psychophysics experiment
    %
    % Usage:
    %   app = ep_RunExpt2;
    %   % Interact via UI or call methods:
    %   % app.LoadConfig(); app.Run(); app.Stop(); app.SaveData();
    %
    % Daniel.Stolzberg@gmail.com 2014–2025

    properties
        H % struct of UI handles
        PRGMSTATE string = "NOCONFIG"
        STATEID double = 0
        CONFIG struct = struct('SUBJECT',[],'PROTOCOL',[],'RUNTIME',[],'protocol_fn',[])
        FUNCS struct
        RUNTIME struct = struct()
        GVerbosity double = 1
    end

    methods
        function self = ep_RunExpt2()
            self.buildUI
            self.FUNCS = self.GetDefaultFuncs;
            self.ClearConfig
            self.UpdateGUIstate
        end

        function delete(self)
            try
                if isvalid(self)
                    self.onCloseRequest
                end
            catch
            end
        end

        function Run(self)
            self.ExptDispatch("Run")
        end

        function Record(self)
            self.ExptDispatch("Record")
        end

        function Preview(self)
            self.ExptDispatch("Preview")
        end

        function Pause(self)
            % Placeholder for future pause handling
        end

        function Stop(self)
            self.ExptDispatch("Stop")
        end

        function SaveData(self)
            self.SaveDataCallback
        end

        function LoadConfig(self, cfn)
            arguments
                self
                cfn string = ""
            end
            if self.STATEID >= 4, return, end

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
            if self.STATEID == 0
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
            arguments
                self
                pfn string = ""
            end
            ok = false;
            if self.STATEID >= 4, return, end

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
            arguments
                self
                S struct = struct()
            end
            if self.STATEID >= 4, return, end

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
            arguments
                self
                idx double = NaN
            end
            if self.STATEID >= 4, return, end

            if isnan(idx)
                idx = self.H.subject_list.UserData;
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
            idx = self.H.subject_list.UserData;
            if isempty(idx), return, end

            warning('off','MATLAB:dispatcher:UnresolvedFunctionHandle');
            S = load(self.CONFIG(idx).protocol_fn,'protocol','-mat');
            warning('on','MATLAB:dispatcher:UnresolvedFunctionHandle');

            ep_CompiledProtocolTrials(S.protocol,'trunc',2000);
        end

        function EditProtocol(self)
            idx = self.H.subject_list.UserData;
            if isempty(idx), return, end

            self.AlwaysOnTop(false);
            ep_ExperimentDesign(char(self.CONFIG(idx).protocol_fn),idx);
        end

        function SortBoxes(self)
            if self.STATEID >= 4, return, end
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
            arguments
                self
                a = []
            end
            if self.STATEID >= 4, return, end

            if ~isempty(a) && ischar(a) && strcmp(a,'default')
                a = 'ep_SaveDataFcn';
            elseif isempty(a) || ~isfield(self.FUNCS,'SavingFcn')
                if ~isfield(self.FUNCS,'SavingFcn') || isempty(self.FUNCS.SavingFcn)
                    self.FUNCS.SavingFcn = 'ep_SaveDataFcn';
                end
                ontop = self.AlwaysOnTop;
                self.AlwaysOnTop(false)
                a = inputdlg('Data Saving Function','Saving Function',1,{self.FUNCS.SavingFcn});
                self.AlwaysOnTop(ontop)
                a = char(a);
                if isempty(a), return, end
            end

            if isa(a,'function_handle'), a = func2str(a); end
            b = which(a);
            if isempty(b)
                ontop = self.AlwaysOnTop;
                self.AlwaysOnTop(false)
                errordlg(sprintf('The function ''%s'' was not found on the current path.',a),'Saving Function','modal')
                self.AlwaysOnTop(ontop)
                return
            end

            if nargin(a) ~= 1 || nargout(a) ~= 0
                ontop = self.AlwaysOnTop;
                self.AlwaysOnTop(false)
                errordlg('The Saving Data function must have 2 inputs and 0 outputs.','Saving Function','modal')
                self.AlwaysOnTop(ontop)
                return
            end

            fprintf('Saving Data function:\t%s\t(%s)\n',a,b)
            self.FUNCS.SavingFcn = a;
            self.CheckReady
        end

        function DefineAddSubject(self, a)
            arguments
                self
                a = []
            end
            if self.STATEID >= 4, return, end
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
            arguments
                self
                a = []
            end
            if self.STATEID >= 4, return, end

            if ~isempty(a) && ischar(a) && strcmp(a,'default')
                a = 'ep_GenericGUI';
            elseif isempty(a) || ~isfield(self.FUNCS,'BoxFig')
                if ~isfield(self.FUNCS,'BoxFig') || isempty(self.FUNCS.BoxFig)
                    self.FUNCS.BoxFig = 'ep_GenericGUI';
                end
                ontop = self.AlwaysOnTop;
                self.AlwaysOnTop(false)
                if isa(self.FUNCS.BoxFig,'function_handle'), self.FUNCS.BoxFig = func2str(self.FUNCS.BoxFig); end
                a = inputdlg('GUI Figure','Specify Custom GUI Figure:',1,{self.FUNCS.BoxFig});
                self.AlwaysOnTop(ontop)
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
            if isempty(self.FUNCS.BoxFig), return, end
            feval(self.FUNCS.BoxFig, self.RUNTIME);
        end

        function AlwaysOnTop(self, ontop)
            if nargout==0 && nargin==1
                ontop = getpref('ep_RunExpt','AlwaysOnTop',false);
            elseif nargin<2
                s = get(self.H.always_on_top,'Checked');
                ontop = strcmp(s,'off');
            end

            if ontop
                set(self.H.always_on_top,'Checked','on');
            else
                set(self.H.always_on_top,'Checked','off');
            end

            set(self.H.figure1,'WindowStyle','normal')
            FigOnTop(self.H.figure1, ontop)
            setpref('ep_RunExpt','AlwaysOnTop',ontop)
        end

        function version_info(~)
            E = EPsychInfo;
            disp(E.meta)
            commandwindow
        end

        function verbosity(self)
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
    end

    methods (Access=private)
        function buildUI(self)
            f = figure('Name','ep_RunExpt','NumberTitle','off','Tag','figure1', ...
                'MenuBar','none','ToolBar','none','Units','normalized','Position',[.2 .2 .6 .6], ...
                'CloseRequestFcn', @(~,~) self.onCloseRequest);
            self.H.figure1 = f;

            mFile = uimenu(f,'Label','File');
            uimenu(mFile,'Label','Load Config...','Callback', @(~,~) self.LoadConfig)
            uimenu(mFile,'Label','Save Config...','Callback', @(~,~) self.SaveConfig)
            uimenu(mFile,'Label','Exit','Separator','on','Callback', @(~,~) self.onCloseRequest)

            mView = uimenu(f,'Label','View');
            self.H.always_on_top = uimenu(mView,'Label','Always On Top','Checked','off', ...
                'Callback', @(~,~) self.AlwaysOnTop);

            mHelp = uimenu(f,'Label','Help');
            uimenu(mHelp,'Label','Version Info','Callback', @(~,~) self.version_info)
            uimenu(mHelp,'Label','Verbosity...','Callback', @(~,~) self.verbosity)

            self.H.mnu_LaunchGUI = uimenu(mView,'Label','Launch Behavior GUI','Enable','off', ...
                'Callback', @(~,~) self.LocateBehaviorGUI);

            % -------- Layout parameters --------
            pad      = .01;   % general padding
            rightW   = .18;   % width of the right-side vertical button column
            bottomH  = .08;   % height of the bottom control bar

            % Compute regions
            tableX = pad;
            tableY = pad + bottomH + pad;                  % leave room for bottom buttons
            tableW = 1 - rightW - 3*pad;                   % leave room for right column
            tableH = 1 - (tableY + pad);                   % up to top padding

            % -------- Subject table (left) --------
            self.H.subject_list = uitable(f,'Tag','subject_list','Units','normalized', ...
                'Position',[tableX tableY tableW tableH], 'Data',{}, ...
                'ColumnName',{'BoxID','Name','Protocol'}, 'ColumnEditable',[false false false], ...
                'CellSelectionCallback', @(h,ev) self.subject_list_CellSelectionCallback(h,ev));

            % -------- Bottom control buttons (Run/Preview/Pause/Stop) --------
            bbW = (tableW - 3*pad)/4;  % four buttons with pad spacing between
            bbH = bottomH;
            bbY = pad;

            self.H.ctrl_run = uicontrol(f,'Style','pushbutton','String','Run', ...
                'Units','normalized','Position',[tableX, bbY, bbW, bbH], ...
                'Tag','ctrl_run','FontWeight','bold', ...
                'BackgroundColor',[0.20 0.75 0.20], 'ForegroundColor',[0 0 0], ...
                'Callback', @(h,~) self.onCommand(h));

            self.H.ctrl_preview = uicontrol(f,'Style','pushbutton','String','Preview', ...
                'Units','normalized','Position',[tableX + (bbW+pad), bbY, bbW, bbH], ...
                'Tag','ctrl_preview','FontWeight','bold', ...
                'BackgroundColor',[0.20 0.50 0.90], 'ForegroundColor',[0 0 0], ...
                'Callback', @(h,~) self.onCommand(h));

            self.H.ctrl_pauseall = uicontrol(f,'Style','pushbutton','String','Pause', ...
                'Units','normalized','Position',[tableX + 2*(bbW+pad), bbY, bbW, bbH], ...
                'Tag','ctrl_pauseall','FontWeight','bold', ...
                'BackgroundColor',[1.00 0.80 0.20], 'ForegroundColor',[0 0 0], ...
                'Callback', @(h,~) self.onCommand(h));

            self.H.ctrl_halt = uicontrol(f,'Style','pushbutton','String','Stop', ...
                'Units','normalized','Position',[tableX + 3*(bbW+pad), bbY, bbW, bbH], ...
                'Tag','ctrl_halt','FontWeight','bold', ...
                'BackgroundColor',[0.85 0.25 0.25], 'ForegroundColor',[1 1 1], ...
                'Callback', @(h,~) self.onCommand(h));

            % -------- Right-side vertical buttons --------
            sideX   = tableX + tableW + pad;
            sideW   = rightW;
            sideH   = .08;    % height of each right-side button
            yTop    = 1 - pad - sideH;

            self.H.save_data = uicontrol(f,'Style','pushbutton','String','Save Data', ...
                'Units','normalized','Position',[sideX yTop sideW sideH], ...
                'Tag','save_data','Callback', @(varargin) []);

            self.H.setup_remove_subject = uicontrol(f,'Style','pushbutton','String','Remove Subject', ...
                'Units','normalized','Position',[sideX yTop-(sideH+pad) sideW sideH], ...
                'Tag','setup_remove_subject','Callback', @(~,~) self.RemoveSubject);

            self.H.edit_protocol = uicontrol(f,'Style','pushbutton','String','Edit Protocol', ...
                'Units','normalized','Position',[sideX yTop-2*(sideH+pad) sideW sideH], ...
                'Tag','edit_protocol','Callback', @(~,~) self.EditProtocol);

            self.H.view_trials = uicontrol(f,'Style','pushbutton','String','View Trials', ...
                'Units','normalized','Position',[sideX yTop-3*(sideH+pad) sideW sideH], ...
                'Tag','view_trials','Callback', @(~,~) self.ViewTrials);
        end

        function onCloseRequest(self)
            if strcmp(self.PRGMSTATE,'RUNNING')
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
            self.ExptDispatch(string(get(hObj,'String')))
        end

        function ExptDispatch(self, COMMAND)
            if COMMAND == "Run", COMMAND = "Record"; end

            switch COMMAND
                case {"Run","Record","Preview"}
                    set(self.H.figure1,'pointer','watch'); drawnow

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
                        set(self.H.figure1,'pointer','arrow'); drawnow
                        rethrow(me)
                    end

                    for i = 1:length(self.CONFIG)
                        self.RUNTIME.TRIALS(i).protocol_fn = self.CONFIG(i).protocol_fn; %#ok<AGROW>
                        modnames = fieldnames(self.CONFIG(i).PROTOCOL.MODULES);
                        for j = 1:length(modnames)
                            self.RUNTIME.TRIALS(i).MODULES.(modnames{j}) = j;
                        end
                    end

                    self.RUNTIME.HELPER = epsych.Helper;

                    self.RUNTIME.TIMER = self.CreateTimer;

                    self.RUNTIME.HW.mode = hw.DeviceState(COMMAND);
                    vprintf(0,'System set to ''%s''',COMMAND)
                    pause(1)

                    start(self.RUNTIME.TIMER)

                    set(self.H.figure1,'pointer','arrow'); drawnow

                case 'Pause'
                    % reserved for future pause

                case 'Stop'
                    self.PRGMSTATE = "STOP";
                    set(self.H.figure1,'pointer','watch')

                    vprintf(3,'ExptDispatch: Stopping BoxTimer')
                    t = timerfind('Name','BoxTimer');
                    if ~isempty(t), stop(t); delete(t); end

                    vprintf(3,'ExptDispatch: Stopping PsychTimer')
                    t = timerfind('Name','PsychTimer');
                    if ~isempty(t), stop(t); delete(t); end

                    vprintf(0,'Experiment stopped at %s',datetime("now",Format='dd-MMM-yyyy HH:mm'))

                    set(self.H.figure1,'pointer','arrow')
            end

            self.UpdateGUIstate
        end

        function T = CreateTimer(self)
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
            self.PRGMSTATE = "RUNNING";
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
            if isfield(self.RUNTIME,'HW') && self.RUNTIME.HW.mode == hw.DeviceState.Idle
                self.ExptDispatch("Stop")
                return
            end
            self.RUNTIME = feval(self.FUNCS.TIMERfcn.RunTime, self.RUNTIME);
        end

        function PsychTimerError(self)
            self.PRGMSTATE = "ERROR";
            self.RUNTIME.ERROR = lasterror; %#ok<LERR>
            self.RUNTIME = feval(self.FUNCS.TIMERfcn.Error, self.RUNTIME);
            feval(self.FUNCS.SavingFcn, self.RUNTIME);
            self.UpdateGUIstate
            self.SaveDataCallback
        end

        function PsychTimerStop(self)
            self.PRGMSTATE = "STOP";
            vprintf(3,'PsychTimerStop:Calling timer Stop function: %s',self.FUNCS.TIMERfcn.Stop)
            self.RUNTIME = feval(self.FUNCS.TIMERfcn.Stop, self.RUNTIME);
            vprintf(3,'PsychTimerStop:Calling UpdateGUIstate')
            self.UpdateGUIstate
            vprintf(3,'PsychTimerStop:Calling SaveDataCallback')
            self.SaveDataCallback
        end

        function SaveDataCallback(self)
            oldstate = self.PRGMSTATE;
            self.PRGMSTATE = "";
            vprintf(3,'SaveDataCallback: Calling UpdateGUIstate')
            self.UpdateGUIstate

            try
                vprintf(1,'Calling Saving Function: %s',self.FUNCS.SavingFcn)
                feval(self.FUNCS.SavingFcn, self.RUNTIME);
            catch me
                vprintf(-1,me)
            end

            self.PRGMSTATE = oldstate;
            vprintf(3,'SaveDataCallback: Calling UpdateGUIstate')
            self.UpdateGUIstate
        end

        function CheckReady(self)
            if self.STATEID >= 4, return, end

            Subjects = ~isempty(self.CONFIG) && numel(self.CONFIG) > 0 && isfield(self.CONFIG,'SUBJECT') && ~isempty(self.CONFIG(1).SUBJECT);
            Functions = ~isempty(self.FUNCS) && ~any([isempty(self.FUNCS.SavingFcn); ...
                isempty(self.FUNCS.AddSubjectFcn); structfun(@isempty,self.FUNCS.TIMERfcn)]);

            isready = Subjects & Functions;
            if isready
                self.PRGMSTATE = "CONFIGLOADED";
            else
                self.PRGMSTATE = "NOCONFIG";
            end

            self.UpdateGUIstate
        end

        function UpdateGUIstate(self)
            if strlength(self.PRGMSTATE)==0, self.PRGMSTATE = "NOCONFIG"; end

            hCtrl = findobj(self.H.figure1,'-regexp','tag','^ctrl')';
            set([hCtrl self.H.save_data],'Enable','off')

            hSetup = findobj(self.H.figure1,'-regexp','tag','^setup')';

            switch self.PRGMSTATE
                case "NOCONFIG"
                    self.STATEID = 0;

                case "CONFIGLOADED"
                    self.PRGMSTATE = "READY";
                    self.STATEID = 1;
                    set(self.H.view_trials,'Enable','on');
                    self.UpdateGUIstate

                case "READY"
                    self.STATEID = 3;
                    set([self.H.ctrl_run self.H.ctrl_preview hSetup'],'Enable','on')

                case "RUNNING"
                    self.STATEID = 4;
                    set([self.H.ctrl_pauseall self.H.ctrl_halt],'Enable','on')
                    set(hSetup,'Enable','off')

                case "POSTRUN"
                    self.STATEID = 5;

                case "STOP"
                    self.STATEID = 2;
                    set([self.H.save_data self.H.ctrl_run self.H.ctrl_preview hSetup'],'Enable','on')

                case "ERROR"
                    self.STATEID = -1;
                    set([self.H.save_data self.H.ctrl_run self.H.ctrl_preview hSetup'],'Enable','on')
            end
        end

        function UpdateSubjectList(self)
            if self.STATEID >= 4, return, end

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

        function subject_list_CellSelectionCallback(self, hObj, evnt)
            idx = evnt.Indices;
            if isempty(idx)
                set(hObj,'UserData',[])
            else
                disp(self.CONFIG(idx(1)).SUBJECT)
                set(hObj,'UserData',idx(1))
            end
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

        function F = GetDefaultFuncs(self) %#ok<MANU>
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
            if self.STATEID >= 4, return, end
            self.PRGMSTATE = "NOCONFIG";
            if isfield(self.H,'subject_list') && isgraphics(self.H.subject_list)
                set(self.H.subject_list,'Data',[])
            end
            self.CheckReady
        end
    end
end
