% create_gui: Assembles the GUI layout, controls, panels, and plots for aversive detection.
% All UI and control setup for the experiment is performed here.
function create_gui(obj)
global RUNTIME

% Create the main figure
fig = uifigure(Tag = 'cl_AppetitiveDetection_GUI_B', ...
    Name = 'Caras Lab Appetitive Detection GUI B', ...
    CloseRequestFcn = @(src, event) obj.closeGUI(src, event), ...
    UserData=obj);
fig.Position = [1940 20 1400 1000];  % Set figure size
movegui(fig,'onscreen');
obj.h_figure = fig;

% Create a grid layout
layoutMain = uigridlayout(fig, [11, 7]);
layoutMain.RowHeight = {60, 40, 90, 110, 60, 130, 40, 100,100,100,'1x'};
layoutMain.ColumnWidth = {150, 150, 100, '1x', '1x','1x', '1x'};
layoutMain.Padding = [1 1 1 1];











% visualize grid (for testing)
% showGridBorders(layoutMain)

% CONTROL BUTTONS ---------------------------------------
% Grid layout for buttons
buttonLayout = uigridlayout(layoutMain,[2 3]);
buttonLayout.Layout.Row = 1;
buttonLayout.Layout.Column = [1 4];
buttonLayout.Padding = [0 0 0 0];
buttonLayout.ColumnWidth = repmat({'1x'},1,5);
buttonLayout.RowHeight = {'1x'};
buttonLayout.RowSpacing = 0;
buttonLayout.ColumnSpacing = 0;

bcmNormal = lines(6);
bcmActive = min(bcmNormal+.4,1);
% bcmNormal = repmat(fig.Color,size(bcmActive,1),1);


k = 1;
% > Drop Pellet
p = RUNTIME.HW.find_parameter('!DropPellet',includeInvisible=true);
h = gui.Parameter_Control(buttonLayout,p,Type='mommentary',autoCommit=true);
h.Text = "Pellet";
h.colorNormal = bcmNormal(k,:);
h.colorOnUpdate = bcmActive(k,:);
obj.hButtons.DropPellet = h;
k = k + 1;

% > Shape
p = RUNTIME.HW.find_parameter('~Shape',includeInvisible=true);
p.PostUpdateFcn = @cl_AppetitiveDetection_GUI_B.trigger_Shape;
h = gui.Parameter_Control(buttonLayout,p,Type='toggle',autoCommit=true);
h.Text = "Shape";
h.colorNormal = bcmNormal(k,:);
h.colorOnUpdate = bcmActive(k,:);
obj.hButtons.Shape = h;
k = k + 1;


% > Remind
p = RUNTIME.S.Module.add_parameter('ReminderTrials',0);
p.PostUpdateFcn = @cl_AppetitiveDetection_GUI_B.trigger_ReminderTrial;
h = gui.Parameter_Control(buttonLayout,p,Type='toggle',autoCommit=true);
h.Text = "Reminder";
h.colorNormal = bcmNormal(k,:);
h.colorOnUpdate = bcmActive(k,:);
obj.hButtons.Reminder = h;
k = k + 1;

% > Manual Trial
p = RUNTIME.HW.find_parameter('~ManualTrigger',includeInvisible=true);
h = gui.Parameter_Control(buttonLayout,p,Type='toggle',autoCommit=true);
h.Text = "Observe";
h.colorNormal = bcmNormal(k,:);
h.colorOnUpdate = bcmActive(k,:);
obj.hButtons.ManualTrial = h;
k = k + 1;

% > Deliver Trials
p = RUNTIME.HW.find_parameter('~TrialDelivery',includeInvisible=true);
h = gui.Parameter_Control(buttonLayout,p,Type='toggle',autoCommit=true);
h.Text = "Deliver Trials";
h.colorNormal = bcmNormal(k,:);
h.colorOnUpdate = bcmActive(k,:);
obj.hButtons.DeliverTrials = h;
k = k + 1;



bh = structfun(@(a) a.h_value,obj.hButtons,'uni',0);
bh = struct2cell(bh);
for i = 1:length(bh)
set(bh{i}, ...
    FontWeight = 'bold', ...
    FontSize = 15, ...
    Enable = "on");
end

% INFO ----------------------------------------------------

% >> Info table
h = uipanel(layoutMain);
h.Layout.Column = 5;
h.Layout.Row    = [1 3];

p = RUNTIME.HW.find_parameter('PelletTotal');
p(2) = RUNTIME.HW.find_parameter('Platform');
p(3) = RUNTIME.HW.find_parameter('Trough');
p(4) = RUNTIME.HW.find_parameter('InTrial');
obj.ParameterMonitorTable = gui.Parameter_Monitor(h,p,pollPeriod=0.1);






% TRIAL CONTROLS -------------------------------------------------
% Panel for "Trial Controls"
panelTrialControls = uipanel(layoutMain, 'Title', 'Trial Controls');
panelTrialControls.Layout.Row = [2 5];
panelTrialControls.Layout.Column = [1 2];

% > Trial Controls
layoutTrialControls = uigridlayout(panelTrialControls);
layoutTrialControls.ColumnWidth = {'1x'};
layoutTrialControls.RowHeight = repmat({25},1,10);
layoutTrialControls.RowSpacing = 1;
layoutTrialControls.ColumnSpacing = 5;
layoutTrialControls.Padding = [0 0 0 0];
layoutTrialControls.Scrollable = "on";

% Panel for "Sound Controls"
panelSoundControls = uipanel(layoutMain, 'Title', 'Sound Controls');
panelSoundControls.Layout.Row = [6];
panelSoundControls.Layout.Column = [1 2];

% > Sound Controls
layoutSoundControls = uigridlayout(panelSoundControls);
layoutSoundControls.ColumnWidth = {'1x'};
layoutSoundControls.RowHeight = repmat({25},1,9);
layoutSoundControls.RowSpacing = 1;
layoutSoundControls.ColumnSpacing = 5;
layoutSoundControls.Padding = [0 0 0 0];
layoutSoundControls.Scrollable = "on";











% >> Consecutive NOGO min
p = RUNTIME.S.Module.add_parameter('ConsecutiveNOGO_min',1);
h = gui.Parameter_Control(layoutTrialControls,p,Type='dropdown');%,autoCommit=true);
h.EvaluatorFcn = @obj.eval_gonogo;
h.Values = 0:5;
h.Value = 1;
h.Text = "Consecutive NoGo (min):";

% >> Consecutive NOGO max
p = RUNTIME.S.Module.add_parameter('ConsecutiveNOGO_max',2);
h = gui.Parameter_Control(layoutTrialControls,p,Type='dropdown');%,autoCommit=true);
h.EvaluatorFcn = @obj.eval_gonogo;
h.Values = 0:10;
h.Value = 2;
h.Text = "Consecutive NoGo (max):";


% >> Trial order
p = RUNTIME.S.Module.add_parameter('TrialOrder','Random');
h = gui.Parameter_Control(layoutTrialControls,p,Type='dropdown',autoCommit=true);
h.Values = ["Descending","Ascending","Random","Staircase"];
h.Value = "Descending";
h.Text = "Trial Order:";



% >> Intertrial Interval
p = RUNTIME.HW.find_parameter('ITIDur');
h = gui.Parameter_Control(layoutTrialControls,p,Type='editfield');
h.Text = "Intertrial Interval (ms):";


% >> Response Window Delay
p = RUNTIME.HW.find_parameter('RespWinDelay');
h = gui.Parameter_Control(layoutTrialControls,p,Type='editfield');
h.Text = "Response Window Delay (ms):";



% >> Response Window Duration
p = RUNTIME.HW.find_parameter('RespWinDur');
h = gui.Parameter_Control(layoutTrialControls,p,Type='editfield');
h.Text = "Response Window Duration (ms):";



% >> Number of Pellets to Deliver
p = RUNTIME.HW.find_parameter('NumPellets');
h = gui.Parameter_Control(layoutTrialControls,p,Type='dropdown');
h.Values = 1:3;
h.Value = 1;
h.Text = "# Pellets:";


% >> Timeout Duration
p = RUNTIME.HW.find_parameter('TimeoutDur');
h = gui.Parameter_Control(layoutTrialControls,p,Type='editfield');
h.Text = "Timeout Duration (ms):";






% SOUND CONTROLS -----------------------------------------------------

% >> dB SPL
p = RUNTIME.HW.find_parameter('dBSPL',silenceParameterNotFound=true);
if ~isempty(p)
    h = gui.Parameter_Control(layoutSoundControls,p,Type='editfield');
    h.Text = "Sound Level (dB SPL):";
end

% >> Tone dB SPL
p = RUNTIME.HW.find_parameter('TonedBSPL',silenceParameterNotFound=true);
if ~isempty(p)
    h = gui.Parameter_Control(layoutSoundControls,p,Type='editfield');
    h.Text = "Tone Sound Level (dB SPL):";
end

% >> Noise dB SPL
p = RUNTIME.HW.find_parameter('NoisedBSPL',silenceParameterNotFound=true);
if ~isempty(p)
    h = gui.Parameter_Control(layoutSoundControls,p,Type='editfield');
    h.Text = "Noise Sound Level (dB SPL):";
end

% >> Duration
p = RUNTIME.HW.find_parameter('StimDur',silenceParameterNotFound=true);
if ~isempty(p)
    h = gui.Parameter_Control(layoutSoundControls,p,Type='editfield');
    h.Text = "Stimulus Duration (ms):";
end

% >> Modulation Rate
p = RUNTIME.HW.find_parameter('Rate');
if ~isempty(p)
    h = gui.Parameter_Control(layoutSoundControls,p,Type='editfield');
    h.Text = "Modulation Rate (Hz):";
end





% Panel for "Trial Filter" ------------------------------------------
panelTrialFilter = uipanel(layoutMain, 'Title', 'Trial Filter');
panelTrialFilter.Layout.Row = [9 11];
panelTrialFilter.Layout.Column = [1 3];
panelTrialFilter.Scrollable = 'on';

% > Trial Filter
layoutTrialFilter = simple_layout(panelTrialFilter);


% > Trial Filter Table
tt = RUNTIME.TRIALS.trials;
loc = RUNTIME.TRIALS.writeParamIdx;
trialTypes = cell2mat(tt(:,loc.TrialType));
reminderInd = trialTypes == 2;
d = tt(~reminderInd,loc.Depth);
n = size(d,1);
d(:,2) = tt(~reminderInd,loc.TrialType);
d(:,3) = num2cell([true(1); false(n-5-1,1); true(5,1)]);

h = uitable(layoutTrialFilter);
h.Tag = 'tblTrialFilter';
h.ColumnName = {'Depth','TrialType','Present'};
h.ColumnEditable = [false,false,true];
h.FontSize = 10;
h.Data = d;
h.Interruptible = 'off';
h.CellEditCallback = @obj.update_trial_filter;
obj.tableTrialFilter = h;
obj.update_trial_filter(h);








% Commit button ---------------------------------------------
h = gui.Parameter_Update(layoutMain);
h.Button.Layout.Row = [9 10];
h.Button.Layout.Column = [4];
h.Button.Text = ["Update" "Parameters"];
h.Button.FontSize = 24;

% find all 'Parameter_Control' objects
hp = findall(fig,'-regexp','tag','^PC_');
h.watchedHandles = [hp.UserData];




% % create/locate online plot ------------------------------------
% h = uibutton(layoutMain);
% h.Layout.Row = 11;
% h.Layout.Column = 4;
% h.Text = "Online Plot";
% h.ButtonPushedFcn = @obj.create_onlineplot;

% Filename field -----------------------------------------------
panelFilename = uipanel(layoutMain, 'Title', 'Filename');
panelFilename.Layout.Row = 11;
panelFilename.Layout.Column = [4 5];

layoutFilename = simple_layout(panelFilename);


gui.FilenameValidator(layoutFilename,RUNTIME.TRIALS.DataFilename);




% Panel for "Next Trial" ----------------------------------------
panelNextTrial = uipanel(layoutMain, 'Title', 'Next Trial');
panelNextTrial.Layout.Row = [1 2];
panelNextTrial.Layout.Column = 6;

layoutNextTrial = simple_layout(panelNextTrial);

% > Next Trial Table
tableNextTrial = uitable(layoutNextTrial);
tableNextTrial.Tag = 'tblNextTrial';
tableNextTrial.ColumnName = {'Depth','TrialType'};
tableNextTrial.RowName = [];
tableNextTrial.ColumnEditable = false;
tableNextTrial.FontSize = 20;

obj.hl_NewTrial = addlistener(RUNTIME.HELPER,'NewTrial',@(src,evnt) obj.update_NextTrial(src,evnt));
obj.hl_NewData  = addlistener(obj.psychDetect.Helper,'NewData',@(src,evnt) obj.update_NewData(src,evnt));
obj.hl_ModeChange =addlistener(RUNTIME.HELPER,'ModeChange',@(src,ev) obj.onModeChange(src,ev));







% DS 9/23/2025 --- removed due to performance issues
% % Axes for Sliding Window Performance Plot ------------------------
% axSlidingWindow = uiaxes(layoutMain);
% axSlidingWindow.Layout.Row = [2 3];
% axSlidingWindow.Layout.Column = [3 5];
% obj.slidingWindowPlot = gui.SlidingWindowPerformancePlot(obj.psychDetect,axSlidingWindow);
% obj.slidingWindowPlot.plotType = 'dPrime';



% Axes for Main Plot ------------------------------------------------
axPsych = uiaxes(layoutMain);
axPsych.Layout.Row = [4 8];
axPsych.Layout.Column = [3 5];

obj.psychPlot = gui.PsychPlot(obj.psychDetect,axPsych);
% obj.psychPlot.logx = true;
















% Axes for Microphone Display -------------------------------
axesMicrophone = uiaxes(layoutMain);
axesMicrophone.Layout.Row = [9 10];
axesMicrophone.Layout.Column = 5;
axis(axesMicrophone,'image');
box(axesMicrophone,'on')

p = RUNTIME.HW.find_parameter('MicPower',silenceParameterNotFound=true);
if ~isempty(p)
    gui.MicrophonePlot(p,axesMicrophone);
    axesMicrophone.YAxis.Label.String = "RMS voltage";
end

% Panel for "FA Rate" --------------------------------------------
panelFARate = uipanel(layoutMain, 'Title', 'Session FA Rate');
panelFARate.Layout.Row = [1 2];
panelFARate.Layout.Column = 7;

layoutFARate = simple_layout(panelFARate);

% > FA Rate
h = uilabel(layoutFARate);
h.Tag = 'lblFARate';
h.Text = "0";
h.FontColor = 'r';
h.FontSize = 30;
h.FontWeight = 'bold';
h.HorizontalAlignment = "center";
obj.lblFARate = h;


% Panel for "Response History" --------------------------------------
panelResponseHistory = uipanel(layoutMain, 'Title', 'Response History');
panelResponseHistory.Layout.Row = [3 8];
panelResponseHistory.Layout.Column = [6 7];

% > Response History Table
obj.ResponseHistory = gui.History(obj.psychDetect,panelResponseHistory);
obj.ResponseHistory.ParametersOfInterest = {'Depth','TrialType','Reminder'};


% Panel for "Performance" ----------------------------------------
panelPerformance = uipanel(layoutMain, 'Title', 'Performance');
panelPerformance.Layout.Row = [9 11];
panelPerformance.Layout.Column = [6 7];

obj.Performance = gui.Performance(obj.psychDetect,panelPerformance);
obj.Performance.ParametersOfInterest = {'Depth'};




% update panel title aesthetics
hp = findobj(fig,'type','uipanel');
set(hp, ...
    BorderType = "none", ...
    FontWeight = "bold", ...
    FontSize = 13)


% update dropdown aesthetics
ddh = findobj(fig,'Type', 'uidropdown');
set(ddh,FontColor = 'b');

obj.guiHandles = findobj(fig);


end






% used by create_gui
function h = simple_layout(p)
h = uigridlayout(p);
h.ColumnWidth = {'1x'};
h.RowHeight = {'1x'};
h.Padding = [0 0 0 0];
end