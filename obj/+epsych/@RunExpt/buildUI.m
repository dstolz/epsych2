function buildUI(self)
% buildUI — Create UIFigure, menus, layouts, and controls.
% Behavior
%   Assembles the main grid, subject table, bottom control bar, and
%   right-side utilities using uigridlayout and uibutton components.
% Documentation: documentation/layouts/RunExpt_layout.md

fpos = epsych.RunExpt.getSavedFigurePosition([100 100 800 400]);
info = EPsychInfo();
figureName = 'EPsych';
if ~isempty(info.latestTag)
    figureName = sprintf('EPsych %s',info.latestTag);
end

f = uifigure('Name',figureName,'Tag','RunExpt', ...
    'Position',fpos, ...
    'WindowKeyPressFcn', @(~,evt) self.onFigureKeyPress(evt), ...
    'CloseRequestFcn', @(~,~) self.onCloseRequest);

f.UserData = self;
self.H.figure1 = f;
movegui(f,'onscreen');

% Menus
mConfig = uimenu(f,'Label','Config');
uimenu(mConfig,'Label','Browse &Configs...','MenuSelectedFcn', @(~,~) self.BrowseConfigs,'Accelerator','C')
uimenu(mConfig,'Label','&Load Config...','MenuSelectedFcn', @(~,~) self.LoadConfig,'Accelerator','L')
uimenu(mConfig,'Label','&Save Config...','MenuSelectedFcn', @(~,~) self.SaveConfig,'Accelerator','S')
self.H.mnu_recent_configs = uimenu(mConfig,'Label','Recent configs ...','Separator','on');

mCustom = uimenu(f,'Label','Customize');
uimenu(mCustom,'Label','Define Saving Function...','MenuSelectedFcn', @(~,~) self.DefineSavingFcn,'Accelerator','S')
uimenu(mCustom,'Label','Define Save path...','MenuSelectedFcn', @(~,~) self.DefineDataPath,'Accelerator','P')
uimenu(mCustom,'Label','Define Config Browser Root...','MenuSelectedFcn', @(~,~) self.DefineConfigBrowserRoot,'Accelerator','R')
uimenu(mCustom,'Label','Define Box GUI Function...','MenuSelectedFcn', @(~,~) self.DefineBoxFig,'Accelerator','B')
uimenu(mCustom,'Label','Define Add Subject Function...','MenuSelectedFcn', @(~,~) self.DefineAddSubject,'Accelerator','A')
uimenu(mCustom,'Label','Timer Period...','Separator','on','MenuSelectedFcn', @(~,~) self.DefineTimerPeriod,'Accelerator','T')

mView = uimenu(f,'Label','View');
self.H.always_on_top = uimenu(mView,'Label','Always On Top','Checked','off', ...
    'Accelerator','T', ...
    'MenuSelectedFcn', @(~,~) self.AlwaysOnTop);

mHelp = uimenu(f,'Label','Help');
uimenu(mHelp,'Label','Version Info','MenuSelectedFcn', @(~,~) self.version_info,'Accelerator','I')
self.H.mnu_open_error_log = uimenu(mHelp,'Label','Open Current Error Log', ...
    'MenuSelectedFcn', @(~,~) self.OpenCurrentErrorLog);
self.H.mnu_assign_runtime = uimenu(mHelp,'Label','Assign RUNTIME to Command Window', ...
    'Enable','off', ...
    'MenuSelectedFcn', @(~,~) self.AssignRuntimeToCommandWindow);
uimenu(mHelp,'Label','Verbosity...','MenuSelectedFcn', @(~,~) self.verbosity,'Accelerator','V')
uimenu(mHelp,'Label','GitHub Repository','Separator','on', ...
    'MenuSelectedFcn', @(~,~) web(EPsychInfo.RepositoryURL,'-browser'))
uimenu(mHelp,'Label','Documentation','MenuSelectedFcn', ...
    @(~,~) web(EPsychInfo.DocumentationURL,'-browser'))
uimenu(mHelp,'Label','Commit History Overview','MenuSelectedFcn', ...
    @(~,~) web(EPsychInfo.CommitHistoryURL,'-browser'))

self.H.mnu_CommutatorGUI = uimenu(mView,'Label','Commutator GUI','Enable','on', ...
    'Accelerator','G', ...
    'MenuSelectedFcn', @(~,~) self.LaunchCommutatorGUI);

self.UpdateRecentConfigsMenu

% Layout

g = uigridlayout(f,[2 2]);
g.RowHeight   = {'1x',40};
g.ColumnWidth = {'1x',100};
g.RowSpacing = 8; g.ColumnSpacing = 8; g.Padding = [8 8 8 8];

% ---------- Subject table (left, top) ----------
self.H.subject_list = uitable(g, ...
    'Tag','subject_list', ...
    'Data',{}, ...
    'ColumnName',{'BoxID','Name','Protocol','Version'}, ...
    'ColumnEditable',[false false false false], ...
    'ColumnWidth',{60,200,280,100}, ...
    'RowStriping','on', ...
    'FontSize',18);
self.H.subject_list.Layout.Row = 1;
self.H.subject_list.Layout.Column = 1;
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
gRight = uigridlayout(g,[5 1]);
gRight.Layout.Row = 1; gRight.Layout.Column = 2;
gRight.RowHeight = {'fit','fit','fit','fit','1x'};
gRight.RowSpacing = 8; gRight.Padding = [0 0 0 0];

self.H.add_subject = uibutton(gRight,'push','Text','Add Subject', ...
    'Tag','add_subject','ButtonPushedFcn', @(~,~) self.AddSubject);

self.H.setup_remove_subject = uibutton(gRight,'push','Text','Remove Subject', ...
    'Tag','setup_remove_subject','ButtonPushedFcn', @(~,~) self.RemoveSubject);

self.H.edit_protocol = uibutton(gRight,'push','Text','Edit Protocol', ...
    'Tag','edit_protocol','ButtonPushedFcn', @(~,~) self.EditProtocol);

self.H.view_trials = uibutton(gRight,'push','Text','View Trials', ...
    'Tag','view_trials','ButtonPushedFcn', @(~,~) self.ViewTrials);

self.H.save_data = uibutton(gRight,'push','Text','Save Data', ...
    'Tag','save_data', 'ButtonPushedFcn', @(~,~) self.SaveDataCallback);
