function buildUI(self)
% buildUI — Create UIFigure, menus, layouts, and controls.
% Behavior
%   Assembles the main grid, subject table, bottom control bar, and
%   right-side utilities using uigridlayout and uibutton components.

pos = getpref('EPsych','RunExpt_GUI',[100 100 700 300]);

f = uifigure('Name',sprintf('EPsych %s',EPsychInfo.Version), ...
    'Tag','RunExpt', ...
    'Position',pos, ...
    'CloseRequestFcn', @(~,~) self.onCloseRequest);

f.UserData = self;

self.H.figure_epsych = f;


movegui(f,'onscreen');

% Menus
mFile = uimenu(f,'Label','File');
uimenu(mFile,'Label','Load Config...','MenuSelectedFcn', @(~,~) self.LoadConfig)
uimenu(mFile,'Label','Save Config...','MenuSelectedFcn', @(~,~) self.SaveConfig)
uimenu(mFile,'Label','Exit','Separator','on','MenuSelectedFcn', @(~,~) self.onCloseRequest)

mCustom = uimenu(f,'Label','Customize');
uimenu(mCustom,'Label','Define Saving Function...','MenuSelectedFcn', @(~,~) self.DefineSavingFcn)
uimenu(mCustom,'Label','Define Save path...','MenuSelectedFcn', @(~,~) self.DefineDataPath)
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
    'ColumnEditable',[false false false], ...
    'ColumnWidth',{50,200,300}, ...
    'CellSelectionCallback', @(h,ev) self.subject_list_SelectionChanged(h,ev));
self.H.subject_list.Layout.Row = 1;
self.H.subject_list.Layout.Column = 1;
% In UIFIGURE, use SelectionChangedFcn

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
gRight.RowHeight = {'fit','fit','fit','fit','fit'};
gRight.RowSpacing = 8; gRight.Padding = [0 0 0 0];

self.H.save_data = uibutton(gRight,'push','Text','Save Data', ...
    'Tag','save_data', 'ButtonPushedFcn', @(~,~) self.SaveData);

self.H.setup_add_subject = uibutton(gRight,'push','Text','Add Subject', ...
    'Tag','setup_add_subject','ButtonPushedFcn', @(~,~) self.AddSubject);

self.H.setup_remove_subject = uibutton(gRight,'push','Text','Remove Subject', ...
    'Tag','setup_remove_subject','ButtonPushedFcn', @(~,~) self.RemoveSubject);

self.H.setup_edit_protocol = uibutton(gRight,'push','Text','Edit Protocol', ...
    'Tag','edit_protocol','ButtonPushedFcn', @(~,~) self.EditProtocol);

self.H.setup_view_trials = uibutton(gRight,'push','Text','View Trials', ...
    'Tag','view_trials','ButtonPushedFcn', @(~,~) self.ViewTrials);
end
