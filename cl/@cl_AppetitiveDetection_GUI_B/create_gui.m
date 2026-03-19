% create_gui: Assembles the GUI layout, controls, panels, and plots for aversive detection.
% All UI and control setup for the experiment is performed here.
function create_gui(obj)

R = obj.RUNTIME;    

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
layoutMain.RowHeight = {60, 40, 90, 110, 60, 130, 40, '1x','1x','1x',40};
layoutMain.ColumnWidth = {150, 150, 100, '1x', '1x','1x', '1x'};
layoutMain.Padding = [1 1 1 1];











% visualize grid (for testing)
%showGridBorders(layoutMain)

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

% bcmNormal = max(lines(6)-0.1,0);
bcmActive = min(lines(6)+0.4,1);
bcmNormal = repmat(fig.Color,size(bcmActive,1),1);


k = 1;
% > Drop Pellet
p = R.HW.find_parameter('!DropPellet',includeInvisible=true);
h = gui.Parameter_Control(buttonLayout,p,Type='momentary',autoCommit=true);
h.Text = "Pellet";
h.colorNormal = bcmNormal(k,:);
h.colorOnUpdate = bcmActive(k,:);
obj.hButtons.DropPellet = h;
k = k + 1;

% > Shape
p = R.HW.find_parameter('~Shape',includeInvisible=true);
p.PostUpdateFcn = @cl_AppetitiveDetection_GUI_B.trigger_Shape;
p.PostUpdateFcnArgs = {R};
h = gui.Parameter_Control(buttonLayout,p,Type='toggle',autoCommit=true);
h.Text = "Shape";
h.colorNormal = bcmNormal(k,:);
h.colorOnUpdate = bcmActive(k,:);
obj.hButtons.Shape = h;
k = k + 1;


% > Remind
p = R.S.Module.add_parameter('ReminderTrials',0);
p.PostUpdateFcn = @cl_AppetitiveDetection_GUI_B.trigger_ReminderTrial;
p.PostUpdateFcnArgs = {R};
h = gui.Parameter_Control(buttonLayout,p,Type='toggle',autoCommit=true);
h.Text = "Reminder";
h.colorNormal = bcmNormal(k,:);
h.colorOnUpdate = bcmActive(k,:);
obj.hButtons.Reminder = h;
k = k + 1;

% > Manual Trial
p = R.HW.find_parameter('~ManualTrigger',includeInvisible=true);
h = gui.Parameter_Control(buttonLayout,p,Type='toggle',autoCommit=true);
h.Text = "Observe";
h.colorNormal = bcmNormal(k,:);
h.colorOnUpdate = bcmActive(k,:);
obj.hButtons.ManualTrial = h;
k = k + 1;

% > Deliver Trials
p = R.HW.find_parameter('~TrialDelivery',includeInvisible=true);
h = gui.Parameter_Control(buttonLayout,p,Type='toggle',autoCommit=true);
h.Text = "Deliver Trials";
h.colorNormal = bcmNormal(k,:);
h.colorOnUpdate = bcmActive(k,:);
obj.hButtons.DeliverTrials = h;
k = k + 1;



bh = structfun(@(a) a.h_uiobj,obj.hButtons,'uni',0);
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
h.Layout.Column = [3 4];
h.Layout.Row    = [6 10];


p = R.HW.find_parameter({'PelletTotal','Platform','Trough','RespWinDelay','InTrial', ...
    '~DelayPeriod','~RespWindow','RespLatency','RespCode'}, ...
    includeInvisible=true);

obj.ParameterMonitorTable = gui.Parameter_Monitor(h,p,pollPeriod=0.1);
obj.ParameterMonitorTable.handle.FontSize = 14;





% LAYOUTS -------------------------------------------------
% Panel for "Trial Controls"
panelTrialControls = uipanel(layoutMain);
panelTrialControls.Layout.Row = [2 6];
panelTrialControls.Layout.Column = [1 2];

% Ppanel for Trial Controls
layoutTrialControls = uigridlayout(panelTrialControls);
layoutTrialControls.ColumnWidth = {'1x'};
layoutTrialControls.RowHeight = repmat({25},1,20);
layoutTrialControls.RowSpacing = 1;
layoutTrialControls.ColumnSpacing = 5;
layoutTrialControls.Padding = [0 0 0 0];
layoutTrialControls.Scrollable = "on";

% Panel for "Sound Controls"
panelSoundControls = uipanel(layoutMain, 'Title', 'Sound Controls');
panelSoundControls.Layout.Row = [7 8];
panelSoundControls.Layout.Column = [1 2];

% > Sound Controls
layoutSoundControls = uigridlayout(panelSoundControls);
layoutSoundControls.ColumnWidth = {'1x'};
layoutSoundControls.RowHeight = repmat({25},1,9);
layoutSoundControls.RowSpacing = 1;
layoutSoundControls.ColumnSpacing = 5;
layoutSoundControls.Padding = [0 0 0 0];
layoutSoundControls.Scrollable = "on";




% Staircase controls --------------------------------------------------

% >> Staircase label
h = uilabel(layoutTrialControls);
h.Text = "Staircase Parameters";
h.FontSize = 16;
h.FontWeight = 'bold';



% >> Min Depth
p = R.S.Module.add_parameter('MinDepth',0.001);
p.Min = 1e-6;
p.Max = 1;
h = gui.Parameter_Control(layoutTrialControls,p,Type='editfield',autoCommit=true);
h.Text = "Minimum Depth (%):";


% >> Max Depth
p = R.S.Module.add_parameter('MaxDepth',1);
p.Min = 1e-6;
p.Max = 1;
h = gui.Parameter_Control(layoutTrialControls,p,Type='editfield',autoCommit=true);
h.Text = "Maximum Depth (%):";


% >> Step on Miss
p = R.S.Module.add_parameter('StepOnMiss',0.09);
p.Min = 1e-6;
p.Max = 0.5;
h = gui.Parameter_Control(layoutTrialControls,p,Type='editfield',autoCommit=true);
h.Text = "Increment on Miss (%):";

% >> Step on Hit
p = R.S.Module.add_parameter('StepOnHit',0.03);
p.Min = 1e-6;
p.Max = 0.5;
h = gui.Parameter_Control(layoutTrialControls,p,Type='editfield',autoCommit=true);
h.Text = "Decrement on Hit (%):";






%{

% >> Consecutive NOGO min
p = R.S.Module.add_parameter('ConsecutiveNOGO_min',1);
h = gui.Parameter_Control(layoutTrialControls,p,Type='dropdown');%,autoCommit=true);
h.EvaluatorFcn = @obj.eval_gonogo;
h.Values = 0:5;
h.Value = 1;
h.Text = "Consecutive NoGo (min):";

% >> Consecutive NOGO max
p = R.S.Module.add_parameter('ConsecutiveNOGO_max',2);
h = gui.Parameter_Control(layoutTrialControls,p,Type='dropdown');%,autoCommit=true);
h.EvaluatorFcn = @obj.eval_gonogo;
h.Values = 0:10;
h.Value = 2;
h.Text = "Consecutive NoGo (max):";


% >> Trial order
p = R.S.Module.add_parameter('TrialOrder','Staircase');
h = gui.Parameter_Control(layoutTrialControls,p,Type='dropdown',autoCommit=true);
h.Values = ["Descending","Ascending","Random","Staircase"];
h.Value = "Staircase";
h.Text = "Trial Order:";

%}

% TRIAL CONTROLS --------------------------------------------------
h = uilabel(layoutTrialControls);
h.Text = "Trial Parameters"; 
h.FontSize = 16;
h.FontWeight = 'bold';

% >> Intertrial Interval
p = R.HW.find_parameter('ITIDur');
h = gui.Parameter_Control(layoutTrialControls,p,Type='editfield');
h.Text = "Intertrial Interval (ms):";


% >> Stimulus Delay --- this is the time from trial start to stimulus onset, and is used in the post_stimdelay_update function to adjust the response window parameters to maintain the same temporal relationship between stimulus and response window when stimulus delay changes
pStimDur = R.HW.find_parameter('StimDur',silenceParameterNotFound=true);
pStimDur.Unit = 'ms';
pStimDur.Min = 1;
pStimDur.Max = 10000;

% >> Response window delay --- computed relative to end of stimulus, so that it can be adjusted based on stimulus duration changes
pRespWinDelay = R.HW.find_parameter('RespWinDelay');
pRespWinDelay.Unit = 'ms';


% >> Response Window Duration --- this is separate from the response window delay because we want it to be independently adjustable during training with variable stimulus delay
pRespWinDur = R.HW.find_parameter('RespWinDur');
pRespWinDur.Unit = 'ms';


% note that "Pre" and "Post" stimulus refer to the Stimulus Offset
% >> Pre-stimulus portion of response window --- this is used in the post_stimdelay_update function to maintain the same temporal relationship between stimulus and response window when stimulus delay changes
pRespWinPreStim = R.S.Module.add_parameter('RespWinPreStim',1000, ...
                        Unit = 'ms', ...
                        Min = 0, ...
                        Max = 10000);
h = gui.Parameter_Control(layoutTrialControls,pRespWinPreStim,Type='editfield');
h.Text = "RW Pre-Stimulus Offset (ms):";


% >> RW Pre-stimulus delay training
h = uibutton(layoutTrialControls,"state");
h.Text = "RW Pre-Stimulus Offset Training Mode";
h.ValueChangedFcn = @(src,event) obj.eval_staircase_training_mode(src,event,pRespWinPreStim);

% >> Post-stimulus portion of response window --- this is used in the post-stimdelay_update function to maintain the same temporal relationship between stimulus and response window when stimulus delay changes
pRespWinPostStim = R.S.Module.add_parameter('RespWinPostStim',0, ...
                        Unit = 'ms', ...
                        Min = 1000, ...
                        Max = 10000);
h = gui.Parameter_Control(layoutTrialControls,pRespWinPostStim,Type='editfield');
h.Text = "RW Post-Stimulus Offset (ms):";


% >> Stimulus Delay (randomized --- value based on min/max settings below)
pStimDelay = R.HW.find_parameter('StimDelay');
pStimDelay.Unit = 'ms';
pStimDelay.Min = 500; % default min/max values, can be adjusted by user. These are just set to satisfy Parameter requirements and will be updated based on the "StimDelayMin/Max" parameters below.
pStimDelay.Max = 500;
pStimDelay.isRandom = true; % enable randomization for this parameter
pStimDelay.PostUpdateFcn = @obj.post_stimdelay_update;
pStimDelay.PostUpdateFcnArgs = {pStimDur,pRespWinDelay,pRespWinDur,pRespWinPreStim,pRespWinPostStim};


% >> Stimulus Delay Training Mode --- launches a small gui to adjust parameters for training with variable stimulus delay
h = uibutton(layoutTrialControls,"state");
h.Text = "Stimulus Delay Training Mode";
h.ValueChangedFcn = @(src,event) obj.eval_staircase_training_mode(src,event,pStimDelay);


pMin = R.S.Module.add_parameter('StimDelayMin',pStimDelay.Min, ...
                        Unit = 'ms', ...
                        Min = 100, ...
                        Max = 10000);
pMax = R.S.Module.add_parameter('StimDelayMax',pStimDelay.Max, ...
                        Unit = 'ms', ...
                        Min = 100, ...
                        Max = 10000);

% >> Stimulus Delay (min)
h = gui.Parameter_Control(layoutTrialControls,pMin,Type='editfield');
h.Text = "Stimulus Delay Min (ms):";
h.EvaluatorFcn = @obj.eval_dependent_parameter_randomization;
h.EvaluatorArgs = {pMin,pMax,pStimDelay}; % resolve paired min/max and target parameters from the changed parameter name


% >> Stimulus Delay (max)
h = gui.Parameter_Control(layoutTrialControls,pMax,Type='editfield');
h.Text = "Stimulus Delay Max (ms):";
h.EvaluatorFcn = @obj.eval_dependent_parameter_randomization;
h.EvaluatorArgs = {pMin,pMax,pStimDelay}; % pass the dependent parameters as additional arguments for range validation and automatic updating when min/max values change





% >> Response Window Duration
p = R.HW.find_parameter('RespWinDur');
h = gui.Parameter_Control(layoutTrialControls,p,Type='editfield');
h.Text = "Response Window Duration (ms):";



% >> Number of Pellets to Deliver
p = R.HW.find_parameter('NumPellets');
h = gui.Parameter_Control(layoutTrialControls,p,Type='dropdown');
h.Values = 1:3;
h.Value = 1;
h.Text = "# Pellets:";


% >> Timeout Duration
p = R.HW.find_parameter('TimeoutDur');
h = gui.Parameter_Control(layoutTrialControls,p,Type='editfield');
h.Text = "Timeout Duration (ms):";






% SOUND CONTROLS -----------------------------------------------------

% >> dB SPL
p = R.HW.find_parameter('dBSPL',silenceParameterNotFound=true);
if ~isempty(p)
    p.Unit = 'dB SPL';
    p.Min = -20;
    p.Max = 80;
    h = gui.Parameter_Control(layoutSoundControls,p,Type='editfield');
    h.Text = "Sound Level (dB SPL):";
end

% >> Tone dB SPL
p = R.HW.find_parameter('TonedBSPL',silenceParameterNotFound=true);
if ~isempty(p)
    p.Unit = 'dB SPL';
    p.Min = -20;
    p.Max = 80;
    h = gui.Parameter_Control(layoutSoundControls,p,Type='editfield');
    h.Text = "Tone Sound Level (dB SPL):";
end

% >> Noise dB SPL
p = R.HW.find_parameter('NoisedBSPL',silenceParameterNotFound=true);
if ~isempty(p)
    p.Unit = 'dB SPL';
    p.Min = -20;
    p.Max = 80;
    h = gui.Parameter_Control(layoutSoundControls,p,Type='editfield');
    h.Text = "Noise Sound Level (dB SPL):";
end

% >> Duration
if ~isempty(pStimDur)    
    h = gui.Parameter_Control(layoutSoundControls,pStimDur,Type='editfield');
    h.Text = "Stimulus Duration (ms):";
end

% >> Modulation Rate
p = R.HW.find_parameter('Rate');
if ~isempty(p)
    p.Unit = 'Hz';
    p.Min = 0.1;
    p.Max = 1000;
    h = gui.Parameter_Control(layoutSoundControls,p,Type='editfield');
    h.Text = "Modulation Rate (Hz):";
end



%{

% Panel for "Trial Filter" ------------------------------------------
panelTrialFilter = uipanel(layoutMain, 'Title', 'Trial Filter');
panelTrialFilter.Layout.Row = [9 11];
panelTrialFilter.Layout.Column = [1 3];
panelTrialFilter.Scrollable = 'on';

% > Trial Filter
layoutTrialFilter = simple_layout(panelTrialFilter);


% > Trial Filter Table
tt = R.TRIALS.trials;
loc = R.TRIALS.writeParamIdx;
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


%}




% Commit button ---------------------------------------------
h = gui.Parameter_Update(R,layoutMain);
h.Button.Layout.Row = [9 10];
h.Button.Layout.Column = [1 2];
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
panelFilename.Layout.Column = [3 5];

layoutFilename = simple_layout(panelFilename);


gui.FilenameValidator(R,layoutFilename,R.TRIALS.DataFilename);




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

obj.hl_NewTrial = addlistener(R.HELPER,'NewTrial',@(src,evnt) obj.update_NextTrial(src,evnt));
obj.hl_NewData  = addlistener(obj.Psych.Helper,'NewData',@(src,evnt) obj.update_NewData(src,evnt));
obj.hl_ModeChange =addlistener(R.HELPER,'ModeChange',@(src,ev) obj.onModeChange(src,ev));










% Axes for Main Plot ------------------------------------------------
axPsych = uiaxes(layoutMain);
axPsych.Layout.Row = [3 5];
axPsych.Layout.Column = [3 7];

obj.Psych.enablePlot(axPsych);















%{
% Axes for Microphone Display -------------------------------
axesMicrophone = uiaxes(layoutMain);
axesMicrophone.Layout.Row = [9 10];
axesMicrophone.Layout.Column = 5;
axis(axesMicrophone,'image');
box(axesMicrophone,'on')

p = R.HW.find_parameter('MicPower',silenceParameterNotFound=true);
if ~isempty(p)
    gui.MicrophonePlot(p,axesMicrophone);
    axesMicrophone.YAxis.Label.String = "RMS voltage";
end
%}


% Panel for "Performance" --------------------------------------------
panelPerformance = uipanel(layoutMain, 'Title', 'Session Performance');
panelPerformance.Layout.Row = [1 2];
panelPerformance.Layout.Column = 7;

layoutPerformance = simple_layout(panelPerformance);

% > Performance
h = uilabel(layoutPerformance);
h.Tag = 'lblPerformance';
h.Text = "0";
h.FontColor = 'r';
h.FontSize = 18;
h.FontWeight = 'bold';
h.HorizontalAlignment = "left";
obj.lblPerformance = h;


% Panel for "Response History" --------------------------------------
panelResponseHistory = uipanel(layoutMain, 'Title', 'Response History');
panelResponseHistory.Layout.Row = [6 11];
panelResponseHistory.Layout.Column = [6 7];

% > Response History Table
obj.ResponseHistory = gui.History(obj.Psych,panelResponseHistory);
obj.ResponseHistory.BitColors = ["#b4ffca", "#ffcdcd", "#76c8ff","#ffce8f","#f0fc86"]; % override default BitMask colors with black for no response, orange for miss, and black for hit
obj.ResponseHistory.ParametersOfInterest = {'Depth','TrialType','Reminder'};


%{
% Panel for "Performance" ----------------------------------------
panelPerformance = uipanel(layoutMain, 'Title', 'Performance');
panelPerformance.Layout.Row = [9 11];
panelPerformance.Layout.Column = [6 7];

obj.Performance = gui.Performance(obj.psychDetect,panelPerformance);
obj.Performance.ParametersOfInterest = {'Depth'};
%}



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