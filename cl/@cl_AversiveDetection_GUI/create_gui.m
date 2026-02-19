% create_gui: Assembles the GUI layout, controls, panels, and plots for aversive detection.
% All UI and control setup for the experiment is performed here.
function create_gui(obj)
global RUNTIME

% Create the main figure
fig = uifigure(Tag = 'cl_AversiveDetection_GUI', ...
    Name = 'Caras Lab Aversive Detection GUI', ...
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

bcmActive = jet(5);
% bcmNormal = min(bcmActive+.4,1);
bcmNormal = repmat(fig.Color,size(bcmActive,1),1);


% > Remind
p = RUNTIME.S.Module.add_parameter('ReminderTrials',0);
p.PostUpdateFcn = @cl_AversiveDetection_GUI.trigger_ReminderTrial;
h = gui.Parameter_Control(buttonLayout,p,Type='toggle',autoCommit=true);
h.Text = "Reminder";
h.colorNormal = bcmNormal(1,:);
h.colorOnUpdate = bcmActive(1,:);
obj.hButtons.Reminder = h;


% > Deliver Trials
p = RUNTIME.HW.find_parameter('~TrialDelivery',includeInvisible=true);
h = gui.Parameter_Control(buttonLayout,p,Type='toggle',autoCommit=true);
h.Text = "Deliver Trials";
h.colorNormal = bcmNormal(3,:);
h.colorOnUpdate = bcmActive(3,:);
obj.hButtons.DeliverTrials = h;

% > Air Puff
p = RUNTIME.S.Module.add_parameter('AirPuff',0);
h = gui.Parameter_Control(buttonLayout,p,Type='toggle',autoCommit=true);
h.Text = "Air Puff";
h.colorNormal = bcmNormal(5,:);
h.colorOnUpdate = bcmActive(5,:);
obj.hButtons.AirPuff = h;


bh = findobj(fig,'Type', 'uistatebutton');
set(bh, ...
    FontWeight = 'bold', ...
    FontSize = 15, ...
    Enable = "on");










% TRIAL CONTROLS -------------------------------------------------
% Panel for "Trial Controls"
panelTrialControls = uipanel(layoutMain, 'Title', 'Trial Controls');
panelTrialControls.Layout.Row = [2 3];
panelTrialControls.Layout.Column = [1 2];

% > Trial Controls
layoutTrialControls = uigridlayout(panelTrialControls);
layoutTrialControls.ColumnWidth = {'1x'};
layoutTrialControls.RowHeight = repmat({25},1,6);
layoutTrialControls.RowSpacing = 1;
layoutTrialControls.ColumnSpacing = 5;
layoutTrialControls.Padding = [0 0 0 0];
layoutTrialControls.Scrollable = "on";

% Panel for "Sound Controls"
panelSoundControls = uipanel(layoutMain, 'Title', 'Sound Controls');
panelSoundControls.Layout.Row = [4 5];
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
p = RUNTIME.S.Module.add_parameter('ConsecutiveNOGO_min',3);
h = gui.Parameter_Control(layoutTrialControls,p,Type='dropdown');%,autoCommit=true);
h.EvaluatorFcn = @obj.eval_gonogo;
h.Values = 0:5;
h.Value = 3;
h.Text = "Consecutive NoGo (min):";

% >> Consecutive NOGO max
p = RUNTIME.S.Module.add_parameter('ConsecutiveNOGO_max',5);
h = gui.Parameter_Control(layoutTrialControls,p,Type='dropdown');%,autoCommit=true);
h.EvaluatorFcn = @obj.eval_gonogo;
h.Values = 3:20;
h.Value = 5;
h.Text = "Consecutive NoGo (max):";


% >> Trial order
p = RUNTIME.S.Module.add_parameter('TrialOrder','Descending');
h = gui.Parameter_Control(layoutTrialControls,p,Type='dropdown',autoCommit=true);
h.Values = ["Descending","Ascending"];
% h.Values = ["Descending","Ascending","Random"];
h.Value = "Descending";
h.Text = "Trial Order:";



% >> Intertrial Interval
p = RUNTIME.HW.find_parameter('ITI_dur');
h = gui.Parameter_Control(layoutTrialControls,p,Type='dropdown');
h.Values= 0:100:2500;
h.Text = "Intertrial Interval (ms):";


% >> Response Window Duration
p = RUNTIME.HW.find_parameter('RespWinDur');
h = gui.Parameter_Control(layoutTrialControls,p,Type='dropdown');
h.Values = 100:100:1000;
h.Value = 100;
h.Text = "Response Window Duration (ms):";


% >> Optogenetic trigger
p = RUNTIME.HW.find_parameter('Optostim');
h = gui.Parameter_Control(layoutTrialControls,p,Type='dropdown');
h.Values = [0 1];
h.Value = 0;
h.Text = "Optogenetic Trigger:";










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
p = RUNTIME.HW.find_parameter('Stim_Duration');
h = gui.Parameter_Control(layoutSoundControls,p,Type='dropdown');
h.Values = 250:250:2000;
h.Value = 1000;
h.Text = "Stimulus Duration (ms):";


% >> Modulation Rate
p = RUNTIME.HW.find_parameter('Rate');
h = gui.Parameter_Control(layoutSoundControls,p,Type='dropdown');
h.Values = 1:20;
h.Value = 5;
h.Text = "Modulation Rate (Hz):";


% % >> Depth
% p = RUNTIME.HW.find_parameter('Depth');
% h = gui.Parameter_Control(layoutSoundControls,p,Type='dropdown');
% h.Values = 0:.01:1;
% h.Value = p.Value;
% h.Text = "AM Depth (%):";



% >> Highpass cutoff
p = RUNTIME.HW.find_parameter('Highpass',silenceParameterNotFound=true);
if ~isempty(p)
    h = gui.Parameter_Control(layoutSoundControls,p,Type='dropdown');
    h.Values = 25:25:300;
    h.Value = p.Value;
    h.Text = "Highpass cutoff (Hz):";
end

% >> Lowpass cutoff
p = RUNTIME.HW.find_parameter('Lowpass',silenceParameterNotFound=true);
if ~isempty(p)
    h = gui.Parameter_Control(layoutSoundControls,p,Type='dropdown');
    h.Values =  1000:500:25000;
    h.Value = p.Value;
    h.Text = "Lowpass cutoff (Hz):";
end





% Panel for "Shock Controls" ----------------------------------------
panelShockControls = uipanel(layoutMain, 'Title', 'Shock Controls');
panelShockControls.Layout.Row = 6;
panelShockControls.Layout.Column = [1 2];

% > Shock Controls
layoutShockControls = uigridlayout(panelShockControls);
layoutShockControls.ColumnWidth = {'1x'};
layoutShockControls.RowHeight = {25,25,25};
layoutShockControls.RowSpacing = 1;
layoutShockControls.ColumnSpacing = 5;
layoutShockControls.Padding = [0 0 0 0];

% >> AutoShock
% p = RUNTIME.HW.find_parameter('ShockFlag');
% h = gui.Parameter_Control(layoutShockControls,p,Type="checkbox",autoCommit=true);
% h.Value = true;

% >> Shocker status
p = RUNTIME.HW.find_parameter('~ShockOn',includeInvisible=true);
h = gui.Parameter_Control(layoutShockControls,p,type='readonly');
h.Text = 'Shock State';

% >> Shocker flag
p = RUNTIME.HW.find_parameter('ShockFlag');
h = gui.Parameter_Control(layoutShockControls,p,Type="checkbox",autoCommit=true);
h.Value = true;
h.Text = 'Shock Enabled';

% >> Shock duration dropdown
p = RUNTIME.HW.find_parameter('ShockDur');
h = gui.Parameter_Control(layoutShockControls,p,Type='dropdown');
h.Values = 200:100:1200;
h.Value = p.Value;
h.Text = "Shock duration (ms):";

% >> Shock N easiest
p = RUNTIME.S.Module.add_parameter('ShockN',3);
p.PostUpdateFcn = @obj.update_trial_filter;
h = gui.Parameter_Control(layoutShockControls,p,Type='dropdown',autoCommit=true);
h.Values = 1:5;
h.Value = 3;
h.Text = "Shock Easiest #:";






% Panel for "Pump Controls" ------------------------------------------
panelPumpControls = uipanel(layoutMain, 'Title', 'Pump Controls');
panelPumpControls.Layout.Row = 8;
panelPumpControls.Layout.Column = [1 2];


% > Pump Object
try
    port = getpref('PumpCom','port',[]);
    if isempty(port)
        freeports = serialportlist("available");
        idx = listdlg('ListString',freeports, ...
            'PromptString','Pick the Pump port', ...
            'SelectionMode','single');
        port = freeports{idx};
    end
    h = PumpCom(port);
    h.create_gui(panelPumpControls);
    setpref('PumpCom','port',port);
catch me
    lblTotalWater = uilabel(panelPumpControls);
    lblTotalWater.Text = "*CAN'T CONNECT PUMP*";
    lblTotalWater.FontColor = 'r';
    lblTotalWater.FontWeight = 'bold';
    vprintf(0,1,'Couldn''t connect to Pump. Check that the com port is correct')
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
d(:,3) = {false};
d(:,4) = num2cell([true(1); false(n-5-1,1); true(5,1)]);

h = uitable(layoutTrialFilter);
h.Tag = 'tblTrialFilter';
h.ColumnName = {'Depth','TrialType','Shocked','Present'};
h.ColumnEditable = [false,false,false,true];
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

p = RUNTIME.HW.find_parameter('MicPower');
gui.MicrophonePlot(p,axesMicrophone);
axesMicrophone.YAxis.Label.String = "RMS voltage";


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