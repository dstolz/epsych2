function buildUI(self)
% buildUI — Create UIFigure, menus, layouts, and controls.
% Behavior
%   Assembles the main grid, loaded-config header, subject table, toolbar,
%   and bottom control bar using uigridlayout and uibutton components.
% Documentation: documentation/overviews/RunExpt_GUI_Overview.md

fpos = epsych.RunExpt.getSavedFigurePosition([100 100 800 400]);
info = EPsychInfo();
figureName = 'EPsych';
if ~isempty(info.latestTag)
    figureName = sprintf('EPsych %s',info.latestTag);
end
% Name the worktree in the title bar: with two checkouts open it is otherwise
% impossible to tell which code a running session came from.
if ~isempty(info.worktree)
    figureName = sprintf('%s [%s]',figureName,info.worktree);
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

% ---------- Toolbar ----------
% One-click access to the Config menu actions, subject management and data
% saving, the Customize dialog, the Protocol Designer, the two webcam
% controls, Always On Top, and the online wiki. The webcam tools replace
% the former bottom-bar "Live View" button and "Record video" checkbox;
% Add Subject, Remove Subject, and Save Data replace the former right-side
% button stack. Config and webcam tools carry the same 'setup' tag prefix
% as their menu items, so UpdateGUIstate disables them while a session is
% RUNNING; Customize, Protocol Designer, and the wiki stay available in
% every state, as their menu items do. Icons are drawn in localToolbarIcon
% below, so the toolbar ships no image files.
tb = uitoolbar(f);
self.H.toolbar = tb;

self.H.tb_browse_config = uipushtool(tb, ...
    'Tag','setup_tb_browse_config', ...
    'Icon',localToolbarIcon("browse"), ...
    'Tooltip','Browse Configs (Ctrl+C)', ...
    'ClickedCallback', @(~,~) self.BrowseConfigs);

self.H.tb_load_config = uipushtool(tb, ...
    'Tag','setup_tb_load_config', ...
    'Icon',localToolbarIcon("load"), ...
    'Tooltip','Load Config... (Ctrl+L)', ...
    'ClickedCallback', @(~,~) self.LoadConfig);

self.H.tb_refresh_config = uipushtool(tb, ...
    'Tag','setup_tb_refresh_config', ...
    'Icon',localToolbarIcon("refresh"), ...
    'Tooltip','Refresh Config: reload the current config file from disk (Ctrl+R)', ...
    'ClickedCallback', @(~,~) self.RefreshConfig);

self.H.tb_save_config = uipushtool(tb, ...
    'Tag','setup_tb_save_config', ...
    'Icon',localToolbarIcon("save"), ...
    'Tooltip','Save Config... (Ctrl+S)', ...
    'ClickedCallback', @(~,~) self.SaveConfig);

% Subject management and post-run data saving, formerly the right-side
% button stack. Handle names and tags are unchanged from the buttons they
% replace: UpdateGUIstate, UpdateSubjectList, and SaveDataCallback drive
% Enable through these handles, and epsych.SelfTest checks them by name.
%
% This button now opens the Subjects & Projects manager rather than the
% one-at-a-time Add Subject dialog, which is reached from inside it. The
% handle name and tag are deliberately unchanged: epsych.SelfTest check I1
% requires 'add_subject' to exist and be live, and it carries no 'setup'
% prefix so UpdateGUIstate leaves it enabled in every state -- the manager is
% readable mid-run, and it is the commit action inside it that refuses.
self.H.add_subject = uipushtool(tb, ...
    'Tag','add_subject', ...
    'Icon',localToolbarIcon("subjects"), ...
    'Separator','on', ...
    'Tooltip','Subjects & Projects... (Ctrl+B)', ...
    'ClickedCallback', @(~,~) self.OpenSubjectManager);

self.H.setup_remove_subject = uipushtool(tb, ...
    'Tag','setup_remove_subject', ...
    'Icon',localToolbarIcon("removesubject"), ...
    'Tooltip','Remove the selected subject', ...
    'ClickedCallback', @(~,~) self.RemoveSubject);

self.H.save_data = uipushtool(tb, ...
    'Tag','save_data', ...
    'Icon',localToolbarIcon("savedata"), ...
    'Separator','on', ...
    'Tooltip','Save each subject''s behavioral data (available after Stop, or on Error)', ...
    'ClickedCallback', @(~,~) self.SaveDataCallback);

self.H.tb_customize = uipushtool(tb, ...
    'Icon',localToolbarIcon("customize"), ...
    'Separator','on', ...
    'Tooltip','Customize Settings... (Ctrl+U)', ...
    'ClickedCallback', @(~,~) self.OpenCustomizeDialog);

self.H.tb_protocol_designer = uipushtool(tb, ...
    'Icon',localToolbarIcon("protocol"), ...
    'Separator','on', ...
    'Tooltip','Protocol Designer... (Ctrl+P)', ...
    'ClickedCallback', @(~,~) self.LaunchUtility("ProtocolDesigner"));

% Toggle form of Utilities > Video > Live Webcam View (No Recording). Usable in every
% state, RUNNING included: UpdateGUIstate re-enables it after the 'setup'
% lockout. ToggleVideoLiveView may refuse or fail, so UpdateVideoLiveViewUI_
% always resets State to the actual view state afterwards.
self.H.tb_liveview = uitoggletool(tb, ...
    'Tag','setup_tb_liveview', ...
    'Icon',localToolbarIcon("liveview"), ...
    'Separator','on', ...
    'Tooltip','Open a display-only webcam view (nothing is recorded). Same as Utilities > Video > Live Webcam View.', ...
    'ClickedCallback', @(~,~) self.ToggleVideoLiveView);

% Webcam recording opt-in, formerly a bottom-bar checkbox. Pressed = record
% this run -- and, pressed or released mid-session, start or stop recording
% right away (onRecordVideoToggled_). Keeps the 'setup_record_video' tag and
% handle name: epsych.SelfTest checks the handle by name.
self.H.setup_record_video = uitoggletool(tb, ...
    'Tag','setup_record_video', ...
    'Icon',localToolbarIcon("record"), ...
    'State', logical(getpref('ep_RunExpt_Video','EnableRecording',false)), ...
    'Tooltip', ['Record webcam video via VLC during the run (never during Preview).' newline ...
                'Toggling during a session starts or stops recording immediately.' newline ...
                'Camera: Utilities > Video > Webcam Recorder Setup.  Save location: Customize > Paths.'], ...
    'ClickedCallback', @(h,~) self.onRecordVideoToggled_(logical(h.State)));

% Toggle form of View > Always On Top. AlwaysOnTop syncs the menu item's
% Checked state and this toggle's State, so the two entry points never
% disagree no matter which one flipped the setting.
self.H.tb_always_on_top = uitoggletool(tb, ...
    'Icon',localToolbarIcon("ontop"), ...
    'Separator','on', ...
    'Tooltip','Keep this window on top of all others (Ctrl+T). Same as View > Always On Top.', ...
    'ClickedCallback', @(h,~) self.AlwaysOnTop(logical(h.State)));

self.H.tb_wiki = uipushtool(tb, ...
    'Icon',localToolbarIcon("wiki"), ...
    'Separator','on', ...
    'Tooltip','Open the EPsych wiki in a browser', ...
    'ClickedCallback', @(~,~) web(EPsychInfo.DocumentationURL,'-browser'));

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
% Recents get their own submenu rather than loose items appended to Config:
% the entry point stays visible (with a disabled placeholder) even after the
% seven-day window in GetRecentConfigs prunes the list to nothing.
self.H.mnu_recent_configs = uimenu(mConfig,'Label','&Recent Configs', ...
    'Tag','setup_mnu_recent_configs','Separator','on');
self.H.mnu_config = mConfig;

% Subjects gets its own top-level menu rather than an item under Config: the
% roster is a different noun from the session configuration, and it is the
% second-most-used action after Run. It does not belong under Utilities
% either, which is documented as standalone tools -- this one writes CONFIG.
% Note the doubled ampersand: a single '&' would make P the mnemonic and eat
% the character.
mSubjects = uimenu(f,'Label','Subjects');
self.H.mnu_subjects = mSubjects;
self.H.mnu_subject_manager = uimenu(mSubjects,'Label','&Subjects && Projects...', ...
    'Tag','mnu_subject_manager','Accelerator','B', ...
    'MenuSelectedFcn', @(~,~) self.OpenSubjectManager);
self.H.mnu_remove_subject = uimenu(mSubjects,'Label','Remove Selected Subject', ...
    'Tag','setup_mnu_remove_subject', ...
    'MenuSelectedFcn', @(~,~) self.RemoveSubject);
self.H.mnu_roster_file = uimenu(mSubjects,'Label','Roster File...', ...
    'Tag','setup_mnu_roster_file','Separator','on', ...
    'MenuSelectedFcn', @(~,~) self.DefineRosterFile);

mCustom = uimenu(f,'Label','Customize');
uimenu(mCustom,'Label','Customize...','MenuSelectedFcn', @(~,~) self.OpenCustomizeDialog,'Accelerator','U')

% Utilities collects every standalone tool that ships with the toolbox, so an
% operator reaches the designers, the stimulus tools, and the peripheral GUIs
% from the session window instead of from the command line. View keeps only
% what changes this window.
mUtil = uimenu(f,'Label','Utilities');
self.H.mnu_utilities = mUtil;

self.H.mnu_protocol_designer = uimenu(mUtil,'Label','Protocol &Designer...', ...
    'Accelerator','P', ...
    'MenuSelectedFcn', @(~,~) self.LaunchUtility("ProtocolDesigner"));
self.H.mnu_trial_designer = uimenu(mUtil,'Label','Teensy Trial Designer...', ...
    'MenuSelectedFcn', @(~,~) self.LaunchUtility("TrialDesigner"));

% The three tools that come from the stimgen submodule share one submenu, so
% the Utilities list stays readable and an unpopulated submodule fails in one
% predictable place. Nesting is invisible to UpdateGUIstate, which reaches the
% 'setup' tags with a recursive findobj.
mStimGen = uimenu(mUtil,'Label','StimGen','Separator','on');
self.H.mnu_stimgen = mStimGen;

self.H.mnu_stim_player = uimenu(mStimGen,'Label','Stimulus Player...', ...
    'MenuSelectedFcn', @(~,~) self.LaunchUtility("StimPlayer"));
self.H.mnu_stim_inspector = uimenu(mStimGen,'Label','Stimulus Inspector...', ...
    'MenuSelectedFcn', @(~,~) self.LaunchUtility("StimInspector"));

% Calibration drives the hardware into Preview, so the 'setup' tag prefix
% keeps it out of reach while a session is RUNNING.
self.H.mnu_calibration = uimenu(mStimGen,'Label','Calibration GUI...','Enable','on', ...
    'Separator','on','Tag','setup_mnu_calibration', ...
    'MenuSelectedFcn', @(~,~) self.LaunchUtility("Calibration"));

self.H.mnu_CommutatorGUI = uimenu(mUtil,'Label','Commutator GUI','Enable','on', ...
    'Separator','on','Accelerator','G', ...
    'MenuSelectedFcn', @(~,~) self.LaunchCommutatorGUI);

% Everything that touches video -- the recorder, the live view, and the
% offline batch converter -- lives under one submenu so the Utilities list
% stays readable. Nesting is invisible to UpdateGUIstate, which reaches the
% 'setup' tags with a recursive findobj.
mVideo = uimenu(mUtil,'Label','Video','Separator','on');
self.H.mnu_video = mVideo;

self.H.mnu_vlc_setup = uimenu(mVideo,'Label','Webcam Recorder Setup...','Enable','on', ...
    'Accelerator','W', ...
    'MenuSelectedFcn', @(~,~) self.OpenVlcRecorderSetup);

% Watch the camera without writing a file. The label states the no-recording
% behavior outright; UpdateVideoLiveViewUI_ keeps it in sync with the view.
% Available mid-run (UpdateGUIstate re-enables it after the 'setup' lockout),
% at the cost of the VLC restart it performs: ~1 s to open, and up to 8 s for
% a clean quit, during which the trial loop does not run. It still refuses
% while a recording owns VLC, since Play would end that recording.
self.H.mnu_vlc_liveview = uimenu(mVideo,'Text','Live Webcam View (No Recording)','Enable','on', ...
    'Tag','setup_mnu_vlc_liveview', ...
    'MenuSelectedFcn', @(~,~) self.ToggleVideoLiveView);

% Offline work on recordings already on disk: converts the recorder's .ts
% files to a portable format. It never touches the hardware, so it stays
% available while a session runs.
self.H.mnu_video_converter = uimenu(mVideo,'Label','Batch Video Converter...','Separator','on', ...
    'MenuSelectedFcn', @(~,~) self.LaunchUtility("VideoConverter"));

mView = uimenu(f,'Label','View');
self.H.always_on_top = uimenu(mView,'Label','Always On Top','Checked','off', ...
    'Accelerator','T', ...
    'MenuSelectedFcn', @(~,~) self.AlwaysOnTop);
uimenu(mView,'Label','Version Info','MenuSelectedFcn', @(~,~) self.version_info,'Accelerator','I')

mHelp = uimenu(f,'Label','Help');
self.H.mnu_open_error_log = uimenu(mHelp,'Label','Open Current Error Log', ...
    'MenuSelectedFcn', @(~,~) self.OpenCurrentErrorLog);
% Separate item rather than a replacement: the association route above is the
% right one on most rigs, but where MATLAB owns .txt it lands the log back in
% the editor -- unsearchable while the session is running and easy to edit by
% accident. This one goes straight to the viewer named in Customize > Paths.
self.H.mnu_open_error_log_ext = uimenu(mHelp,'Label','Open Current Error Log (External Viewer)', ...
    'MenuSelectedFcn', @(~,~) self.OpenCurrentErrorLog(true));
% Deliberately not tagged 'setup': the read-only checks stay available while a
% session is running, which is when an operator most wants them.
self.H.mnu_self_test = uimenu(mHelp,'Label','Run Self-&Test...', ...
    'Tag','mnu_self_test','Accelerator','D', ...
    'MenuSelectedFcn', @(~,~) self.OpenSelfTest);
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

self.UpdateRecentConfigsMenu

% Layout

g = uigridlayout(f,[4 2]);
% Row 4 is two text lines tall so a long status message wraps instead of
% being clipped at the right edge.
g.RowHeight   = {22,'1x',40,40};
g.ColumnWidth = {'1x',100};
g.RowSpacing = 8; g.ColumnSpacing = 8; g.Padding = [8 8 8 8];

% ---------- Loaded config name (top strip) ----------
% Which .ecfg is in effect is otherwise only visible in the transient status
% message that LoadConfig posts, so it is lost as soon as anything else
% reports. updateConfigLabel_ keeps this in step with CurrentConfigFile; the
% full path lives in the tooltip because configs of the same name routinely
% exist under different subject folders.
self.H.config_name = uilabel(g, ...
    'Tag','config_name', ...
    'Text','Config: (none loaded)', ...
    'FontWeight','bold', ...
    'FontColor',[0.35 0.38 0.44], ...
    'VerticalAlignment','center');
self.H.config_name.Layout.Row = 1;
self.H.config_name.Layout.Column = [1 2];
self.updateConfigLabel_

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
% Spans both columns: the former right-side button stack is gone (its
% actions live on the toolbar and in the table's context menu), so the
% table takes the full width. Column 2 remains for the mode indicator.
self.H.subject_list.Layout.Row = 2;
self.H.subject_list.Layout.Column = [1 2];
self.H.subject_list.SelectionChangedFcn = @(h,ev) self.subject_list_SelectionChanged(h,ev);

% Right-click context menu for per-subject actions. Edit Protocol and View
% Trials absorbed the former right-side buttons of the same names; their
% handle names are unchanged because UpdateGUIstate, UpdateSubjectList, and
% epsych.SelfTest reference them by name, and uimenu supports Enable just
% as the buttons did.
cmProtocol = uicontextmenu(f);
self.H.edit_protocol = uimenu(cmProtocol,'Text','Edit Protocol...', ...
    'Tag','edit_protocol','MenuSelectedFcn', @(~,~) self.EditProtocol);
uimenu(cmProtocol,'Text','Update to Latest Version','MenuSelectedFcn', @(~,~) self.UpdateProtocol);
uimenu(cmProtocol,'Text','Change Protocol File...','MenuSelectedFcn', @(~,~) self.ChangeProtocolFile);
self.H.view_trials = uimenu(cmProtocol,'Text','View Trials','Separator','on', ...
    'Tag','view_trials','MenuSelectedFcn', @(~,~) self.ViewTrials);

% Subject-level actions, as opposed to the protocol-level ones above. Editing
% details in place is what an operator actually wants mid-setup -- correcting a
% weight or a typo previously meant removing and re-adding the subject.
self.H.edit_subject_details = uimenu(cmProtocol,'Text','Edit Subject Details...', ...
    'Tag','setup_edit_subject_details','Separator','on', ...
    'MenuSelectedFcn', @(~,~) self.EditSubjectDetails);
self.H.show_in_manager = uimenu(cmProtocol,'Text','Show in Subject Manager', ...
    'Tag','show_in_manager', ...
    'MenuSelectedFcn', @(~,~) self.ShowSubjectInManager);

self.H.subject_list.ContextMenu = cmProtocol;

% ---------- Bottom control bar (Run/Preview/Pause/Stop) ----------
% The webcam controls (live view toggle, record-video toggle) live on the
% toolbar above, so the bar holds only the four transport buttons.
gBottom = uigridlayout(g,[1 4]);
gBottom.Layout.Row = 3; gBottom.Layout.Column = 1;
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

% ---------- Mode indicator in bottom-right cell ----------
gLamp = uigridlayout(g,[1 1]);
gLamp.Layout.Row = 3; gLamp.Layout.Column = 2;
gLamp.RowHeight = {'1x'};
gLamp.ColumnWidth = {'1x'};
gLamp.Padding = [0 0 0 0];

self.H.modeIndicator = gui.ModeIndicator(gLamp);

% ---------- Status bar (spans the full width, below the controls) ----------
gStatus = uigridlayout(g,[1 2]);
gStatus.Layout.Row = 4; gStatus.Layout.Column = [1 2];
gStatus.RowHeight = {'1x'};
gStatus.ColumnWidth = {'1x','fit'};
gStatus.RowSpacing = 0; gStatus.ColumnSpacing = 8; gStatus.Padding = [0 0 0 0];

% gui.StatusBar must be given an explicit Position: with it empty the
% constructor reads parent.Position(3), and a uigridlayout has no Position.
% The value is ignored once Layout.Row is set. The first real message comes
% from UpdateGUIstate, which the constructor calls immediately.
self.H.statusBar = gui.StatusBar(gStatus, ...
    Position = [1 1 400 22], ...
    InitialText = 'Starting up...');
self.H.statusBar.Label.Layout.Row = 1;
self.H.statusBar.Label.Layout.Column = 1;
% Two-line status area: messages that carry a failure reason or a "Next:"
% hint are routinely wider than the window, so wrap rather than clip. The
% label is top-aligned so a one-line message keeps the same baseline as a
% wrapped one instead of jumping to the vertical centre.
self.H.statusBar.Label.WordWrap = 'on';
self.H.statusBar.Label.VerticalAlignment = 'top';

% States that an open VLC window is showing the camera only. Deliberately
% amber rather than red: a red indicator beside a webcam reads as
% "recording", which is the opposite of what this means. It sits in the
% status row rather than beside the transport buttons so that appearing and
% disappearing only resizes the (left-aligned) status label.
% Text is empty (not Visible='off') while idle so the 'fit' column collapses.
self.H.video_liveview_banner = uilabel(gStatus, ...
    'Text','', ...
    'FontWeight','bold', ...
    'FontColor',[0.85 0.45 0.00], ...
    'VerticalAlignment','top', ...
    'Tooltip','VLC is displaying the webcam stream only. Nothing is being written to disk.');
self.H.video_liveview_banner.Layout.Row = 1;
self.H.video_liveview_banner.Layout.Column = 2;

end

% -----------------------------------------------------------------------
function icon = localToolbarIcon(name)
% 16x16 truecolor icon for one toolbar tool, drawn as pixel art so the
% toolbar ships no image files. Each row is a 16-character string; each
% character is a key into the palette below, and '.' is transparent (NaN).
persistent cache
if isempty(cache), cache = struct(); end
key = char(name);
if isfield(cache, key)
    icon = cache.(key);
    return
end

C = struct( ...
    'k',[0.20 0.22 0.26], ...  % dark outline
    'w',[1.00 1.00 1.00], ...  % white
    's',[0.52 0.55 0.60], ...  % steel gray
    'y',[0.93 0.72 0.16], ...  % folder amber
    'Y',[0.98 0.85 0.42], ...  % folder highlight
    'b',[0.13 0.45 0.80], ...  % blue
    'g',[0.13 0.60 0.28], ...  % green
    'r',[0.83 0.16 0.16], ...  % red
    'R',[0.95 0.55 0.55], ...  % red highlight
    'o',[0.92 0.60 0.12], ...  % pencil orange
    't',[0.83 0.66 0.44]);     % pencil wood

switch name
    case "browse"  % closed folder with a magnifying glass
        rows = [ ...
            "................"
            ".kkkkk.........."
            ".kyyyykkkkkkkk.."
            ".kyyyyyyyyyyyk.."
            ".kYYYYYYYYYYYk.."
            ".kYYYYYYYYYYYk.."
            ".kYYYYYkkkkYYk.."
            ".kYYYYkwwwwkYk.."
            ".kYYYYkwwwwkYk.."
            ".kYYYYkwwwwkYk.."
            ".kYYYYYkkkkYYk.."
            ".kkkkkkkkkkkkk.."
            "...........kk..."
            "............kk.."
            ".............k.."
            "................"];

    case "load"    % open folder
        rows = [ ...
            "................"
            "................"
            ".kkkkk.........."
            ".kyyyykkkkkkk..."
            ".kyyyyyyyyyyk..."
            ".kyyyyyyyyyyk..."
            ".kyyyyyyyyyyk..."
            ".kyyyyyyyyyyk..."
            ".kkkkkkkkkkkkkk."
            ".kYYYYYYYYYYYYk."
            "..kYYYYYYYYYYYk."
            "..kYYYYYYYYYYYk."
            "...kYYYYYYYYYYk."
            "...kkkkkkkkkkkk."
            "................"
            "................"];

    case "refresh" % circular arrow, clockwise
        rows = [ ...
            "................"
            "................"
            "....gggggg......"
            "...gggggggg....."
            "...gg....ggg...."
            "..gg....gggggg.."
            "..gg.....gggg..."
            "..gg......gg...."
            "..gg.......g...."
            "..gg............"
            "...gg..........."
            "...gggg........."
            "....gggggg......"
            "................"
            "................"
            "................"];

    case "save"    % floppy disk
        rows = [ ...
            "................"
            ".kkkkkkkkkkkkk.."
            ".kbbbwwwwwwbbk.."
            ".kbbbwwwwbwbbk.."
            ".kbbbwwwwbwbbk.."
            ".kbbbwwwwbwbbk.."
            ".kbbbbbbbbbbbk.."
            ".kbbbbbbbbbbbk.."
            ".kbwwwwwwwwwbk.."
            ".kbwssssssswbk.."
            ".kbwwwwwwwwwbk.."
            ".kbwssssssswbk.."
            ".kbwwwwwwwwwbk.."
            ".kkkkkkkkkkkkk.."
            "................"
            "................"];

    case "addsubject" % person with a green plus
        rows = [ ...
            "................"
            "...kkkk........."
            "..kssssk........"
            "..kssssk........"
            "..kssssk....gg.."
            "...kkkk.....gg.."
            "..kkkkkk..gggggg"
            ".kssssssk.gggggg"
            ".kssssssk...gg.."
            ".kssssssk...gg.."
            ".kssssssk......."
            ".kkkkkkkk......."
            "................"
            "................"
            "................"
            "................"];

    case "subjects" % person beside a roster list
        rows = [ ...
            "................"
            "...kkkk........."
            "..kssssk........"
            "..kssssk...bbbbb"
            "..kssssk........"
            "...kkkk....bbbbb"
            "..kkkkkk........"
            ".kssssssk..bbbbb"
            ".kssssssk......."
            ".kssssssk..bbbbb"
            ".kssssssk......."
            ".kkkkkkkk......."
            "................"
            "................"
            "................"
            "................"];

    case "removesubject" % person with a red minus
        rows = [ ...
            "................"
            "...kkkk........."
            "..kssssk........"
            "..kssssk........"
            "..kssssk........"
            "...kkkk........."
            "..kkkkkk..rrrrrr"
            ".kssssssk.rrrrrr"
            ".kssssssk......."
            ".kssssssk......."
            ".kssssssk......."
            ".kkkkkkkk......."
            "................"
            "................"
            "................"
            "................"];

    case "savedata" % green arrow down into a tray
        rows = [ ...
            "................"
            ".......gg......."
            ".......gg......."
            ".......gg......."
            ".......gg......."
            ".......gg......."
            ".....gggggg....."
            "......gggg......"
            ".......gg......."
            "................"
            ".ss..........ss."
            ".ss..........ss."
            ".ssssssssssssss."
            ".ssssssssssssss."
            "................"
            "................"];

    case "ontop"   % pushpin
        rows = [ ...
            "................"
            ".....kkkkkk....."
            ".....kbbbbk....."
            ".....kbbbbk....."
            ".....kbbbbk....."
            "....kkkkkkkk...."
            "....kbbbbbbk...."
            "....kkkkkkkk...."
            ".......kk......."
            ".......kk......."
            ".......kk......."
            ".......k........"
            "................"
            "................"
            "................"
            "................"];

    case "customize" % gear
        rows = [ ...
            "................"
            ".......ss......."
            "...ss.ssss.ss..."
            "...ssssssssss..."
            "....ssssssss...."
            "....ssssssss...."
            "...sss....sss..."
            ".sssss....sssss."
            ".sssss....sssss."
            "...sss....sss..."
            "....ssssssss...."
            "....ssssssss...."
            "...ssssssssss..."
            "...ss.ssss.ss..."
            ".......ss......."
            "................"];

    case "protocol" % document with a pencil
        rows = [ ...
            "................"
            "..kkkkkkkkk....."
            "..kwwwwwwwk..oo."
            "..kwssssswk.oo.."
            "..kwwwwwwwkoo..."
            "..kwssssswoo...."
            "..kwwwwwwoo....."
            "..kwssssook....."
            "..kwwwwoowk....."
            "..kwssoowwk....."
            "..kwwttwwwk....."
            "..kwkwwwwwk....."
            "..kkkkkkkkk....."
            "................"
            "................"
            "................"];

    case "liveview" % eye
        rows = [ ...
            "................"
            "................"
            "................"
            ".....kkkkkk....."
            "...kkwwwwwwkk..."
            "..kwwwwbbwwwwk.."
            ".kwwwwbkkbwwwwk."
            ".kwwwwbkkbwwwwk."
            "..kwwwwbbwwwwk.."
            "...kkwwwwwwkk..."
            ".....kkkkkk....."
            "................"
            "................"
            "................"
            "................"
            "................"];

    case "record"  % record dot
        rows = [ ...
            "................"
            "................"
            "......rrrr......"
            "....rrrrrrrr...."
            "...rrRRRrrrrr..."
            "...rRRrrrrrrr..."
            "..rrrrrrrrrrrr.."
            "..rrrrrrrrrrrr.."
            "..rrrrrrrrrrrr.."
            "..rrrrrrrrrrrr.."
            "...rrrrrrrrrr..."
            "...rrrrrrrrrr..."
            "....rrrrrrrr...."
            "......rrrr......"
            "................"
            "................"];

    case "wiki"    % open book
        rows = [ ...
            "................"
            "................"
            "................"
            ".bbbbb....bbbbb."
            ".bwwwwb..bwwwwb."
            ".bwwwwwbbwwwwwb."
            ".bwsswwbbwwsswb."
            ".bwwwwwbbwwwwwb."
            ".bwsswwbbwwsswb."
            ".bwwwwwbbwwwwwb."
            ".bbwwwwbbwwwwbb."
            "..bbbwwbbwwbbb.."
            "....bbbbbbbb...."
            "................"
            "................"
            "................"];

    otherwise
        error('epsych:RunExpt:UnknownToolbarIcon','Unknown toolbar icon "%s".',name)
end

icon = localIconFromMask(rows, C);
cache.(key) = icon;
end

% -----------------------------------------------------------------------
function icon = localIconFromMask(rows, C)
% Convert a string mask into an m-by-n-by-3 truecolor array. '.' pixels stay
% NaN, which uipushtool/uitoggletool render as transparent.
nR = numel(rows);
nC = strlength(rows(1));
icon = nan(nR, nC, 3);
for i = 1:nR
    line = char(rows(i));
    for j = 1:numel(line)
        if line(j) ~= '.'
            icon(i,j,:) = C.(line(j));
        end
    end
end
end
