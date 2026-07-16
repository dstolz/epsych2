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
self.H.figureBaseName    = string(figureName);  % restored when leaving Preview mode
self.H.figureDefaultColor = f.Color;             % restored when leaving Preview mode
movegui(f,'onscreen');

% Menus
mConfig = uimenu(f,'Label','Config');
self.H.mnu_browse_config = uimenu(mConfig,'Label','Browse &Configs...', ...
    'Tag','setup_mnu_browse_config','MenuSelectedFcn', @(~,~) self.BrowseConfigs,'Accelerator','C');
self.H.mnu_load_config = uimenu(mConfig,'Label','&Load Config...', ...
    'Tag','setup_mnu_load_config','MenuSelectedFcn', @(~,~) self.LoadConfig,'Accelerator','L');
self.H.mnu_refresh_config = uimenu(mConfig,'Label','&Refresh Config', ...
    'Tag','setup_mnu_refresh_config','MenuSelectedFcn', @(~,~) self.RefreshConfig,'Accelerator','R');
self.H.mnu_save_config = uimenu(mConfig,'Label','&Save Config...', ...
    'Tag','setup_mnu_save_config','MenuSelectedFcn', @(~,~) self.SaveConfig,'Accelerator','S');
self.H.mnu_config = mConfig;

mCustom = uimenu(f,'Label','Customize');
uimenu(mCustom,'Label','Customize...','MenuSelectedFcn', @(~,~) self.OpenCustomizeDialog,'Accelerator','U')

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

self.H.mnu_vlc_setup = uimenu(mView,'Label','Webcam Recorder Setup...','Enable','on', ...
    'Accelerator','W', ...
    'MenuSelectedFcn', @(~,~) self.OpenVlcRecorderSetup);

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
    'FontSize',18, ...
    'Tooltip','Right-click a subject to edit, update, or change its protocol file');
self.H.subject_list.Layout.Row = 1;
self.H.subject_list.Layout.Column = 1;
self.H.subject_list.SelectionChangedFcn = @(h,ev) self.subject_list_SelectionChanged(h,ev);

% Right-click context menu for per-subject protocol actions
cmProtocol = uicontextmenu(f);
uimenu(cmProtocol,'Text','Edit Protocol...','MenuSelectedFcn', @(~,~) self.EditProtocol);
uimenu(cmProtocol,'Text','Update to Latest Version','MenuSelectedFcn', @(~,~) self.UpdateProtocol);
uimenu(cmProtocol,'Text','Change Protocol File...','MenuSelectedFcn', @(~,~) self.ChangeProtocolFile);
self.H.subject_list.ContextMenu = cmProtocol;

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

% ---------- Mode indicator in bottom-right cell ----------
gLamp = uigridlayout(g,[1 1]);
gLamp.Layout.Row = 2; gLamp.Layout.Column = 2;
gLamp.RowHeight = {'1x'};
gLamp.ColumnWidth = {'1x'};
gLamp.Padding = [0 0 0 0];

self.H.modeIndicator = gui.ModeIndicator(gLamp);
