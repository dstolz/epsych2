
% create_gui(obj)
% Assemble the GUI layout, controls, panels, and plots for the Appetitive Detection experiment.
% 
% This method creates and arranges all UI components for the experiment, including control buttons, parameter panels, plots, and tables. It is called during GUI initialization and configures all interactive elements for the session.
%
% Parameters:
%   obj : cl_AppetitiveDetection_GUI_B instance
%       The GUI object for which the layout is being created.
%
% Returns:
%   None. All handles and UI objects are stored in the obj properties.
%
% Runtime parameters used (R.TRIALS(1).parameters):
% Hardware parameters:
%   dBSPL (optional) : Broadband stimulus level in dB SPL.
%   DelayPeriod : Internal delay-period state monitor.
%   DropPellet : Momentary hardware trigger to dispense a pellet.
%   ITIDur : Intertrial interval duration in ms.
%   InTrial : Logical indicator that a trial is currently active.
%   MicPower (optional) : Microphone power/RMS monitoring channel (optional UI block).
%   NoisedBSPL (optional) : Noise stimulus level in dB SPL.
%   NumPellets : Number of pellets delivered per reward event.
%   P_Catch : Probability of scheduling a catch trial.
%   PelletTotal : Running count of pellets delivered this session.
%   Platform : Platform sensor/state readout for monitoring.
%   Rate (optional) : Modulation rate in Hz.
%   RespCode : Response outcome/status code for the active/recent trial.
%   RespLatency : Measured response latency for the active/recent trial.
%   RespWinDelay : Delay from stimulus reference to response window start.
%   RespWindow : Internal response-window state monitor.
%   RespWinDur : Response window duration in ms.
%   Shape : Toggle control for triggering shape playback/behavior.
%   StimDur (optional) : Stimulus duration in ms.
%   TimeoutDur : Timeout penalty duration in ms.
%   TonedBSPL (optional) : Tone stimulus level in dB SPL.
%   TrialDelivery : Toggle to enable automated trial delivery.
%   Trough : Trough sensor/state readout for monitoring.
%
% Software parameters:
%   ManualTrigger : Toggle to manually trigger/observe a trial.
%   ReminderTrials : Toggle for reminder trial mode.
%   RepeatDelayOnAbort : Repeat current delay setting after abort when enabled.
%   RespWinPostStim : Post-stimulus response-window segment duration in ms.
%   RespWinPreStim : Pre-stimulus response-window segment duration in ms.
%   Depth_StepOnHit : Staircase depth decrement applied after hits.
%   Depth_StepOnMiss : Staircase depth increment applied after misses.
%   StimDelay : Delay before stimulus onset; supports fixed or randomized mode.
%   StimDelayTrain_StepDown : Training step size for decreasing stimulus delay.
%   StimDelayTrain_StepUp : Training step size for increasing stimulus delay.
%
%
% Documentation: documentation/design/ep_ExperimentDesign.md
% Documentation: documentation/layouts/cl_AppetitiveDetection_GUI_B_layout.md

function create_gui(obj)

R = obj.RUNTIME;    

% Create the main figure
fig = uifigure(Tag = 'cl_AppetitiveDetection_GUI_B', ...
    Name = 'Caras Lab Appetitive Detection GUI B', ...
    CloseRequestFcn = @(src, event) obj.closeGUI(src, event), ...
    UserData=obj);
fig.Position = cl_AppetitiveDetection_GUI_B.getSavedFigurePosition([1940 20 1400 1000]);
% movegui(fig,'onscreen');
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
buttonLayout.ColumnWidth = repmat({'1x'},1,6);
buttonLayout.RowHeight = {'1x'};
buttonLayout.RowSpacing = 0;
buttonLayout.ColumnSpacing = 0;

% bcmNormal = max(lines(6)-0.1,0);
bcmActive = min(lines(7)+0.4,1);
bcmNormal = repmat(fig.Color,size(bcmActive,1),1);

P = R.all_parameters(asStruct=true,includeTriggers=true);
P = orderfields(P);

k = 1;
% > Drop Pellet
h = gui.Parameter_Control(buttonLayout,P.DropPellet,Type='momentary',autoCommit=true,Text="Pellet");
h.colorNormal = bcmNormal(k,:);
h.colorOnUpdate = bcmActive(k,:);
obj.hButtons.DropPellet = h;
k = k + 1;

% > Shape
P.Shape.PostUpdateFcn = @cl_AppetitiveDetection_GUI_B.trigger_Shape;
P.Shape.PostUpdateFcnArgs = {R};
h = gui.Parameter_Control(buttonLayout,P.Shape,Type='toggle',autoCommit=true,Text="Shape");
h.colorNormal = bcmNormal(k,:);
h.colorOnUpdate = bcmActive(k,:);
obj.hButtons.Shape = h;
k = k + 1;


% > Remind
P.ReminderTrials.PostUpdateFcn = @cl_AppetitiveDetection_GUI_B.trigger_ReminderTrial;
P.ReminderTrials.PostUpdateFcnArgs = {R};
h = gui.Parameter_Control(buttonLayout,P.ReminderTrials,Type='toggle',autoCommit=true,Text="Reminder");
h.colorNormal = bcmNormal(k,:);
h.colorOnUpdate = bcmActive(k,:);
obj.hButtons.Reminder = h;
k = k + 1;

% > Manual Trial
h = gui.Parameter_Control(buttonLayout,P.ManualTrigger,Type='toggle',autoCommit=true,Text="Observe");
h.colorNormal = bcmNormal(k,:);
h.colorOnUpdate = bcmActive(k,:);
obj.hButtons.ManualTrial = h;
k = k + 1;

% > Deliver Trials
h = gui.Parameter_Control(buttonLayout,P.TrialDelivery,Type='toggle',autoCommit=true,Text="Deliver Trials");
h.colorNormal = bcmNormal(k,:);
h.colorOnUpdate = bcmActive(k,:);
obj.hButtons.DeliverTrials = h;
k = k + 1;


% > Spoof Trough
h = gui.Parameter_Control(buttonLayout,P.SpoofTrough,Type='momentary',autoCommit=true,Text="Trough");
h.colorNormal = bcmNormal(k,:);
h.colorOnUpdate = bcmActive(k,:);
obj.hButtons.Trough = h;
k = k + 1;


bh = structfun(@(a) a.h_uiobj,obj.hButtons,'uni',0);
bh = struct2cell(bh);
for i = 1:length(bh)
set(bh{i}, ...
    FontWeight = 'bold', ...
    FontSize = 15, ...
    Enable = "on");
end




% PHASE SELECTION ------------------------------------------
PhasePath = fullfile(EPsychInfo.root,'cl','@cl_AppetitiveDetection_GUI_B','Phases');
if isfolder(PhasePath)
    obj.PhaseSelector = gui.PhaseSelector(R,PhasePath);
    h = uipanel(layoutMain);
    h.Layout.Row = [1 2];
    h.Layout.Column = 5;

    obj.h_PhaseSelector = obj.PhaseSelector.createGUI(h);
else
    vprintf(0,1,'Phase directory not found: %s', PhasePath)
end










% INFO ----------------------------------------------------

% >> Trial state monitor
% Sensor and trial-state flags render as lamps for at-a-glance reading;
% counters and latencies render as value labels that flash on change.
% Ordering matters: the five lamps are grouped ahead of the value readouts.
panelMonitor = uipanel(layoutMain, 'Title', 'Trial State');
panelMonitor.Layout.Column = [3 4];
panelMonitor.Layout.Row    = [6 10];


p = [P.Platform, P.Trough, P.InTrial, P.DelayPeriod, P.RespWindow, ...
    P.PelletTotal, P.StimDelay, P.RespWinDelay, P.RespLatency, P.RespCode];

obj.ParameterMonitor = gui.Parameter_Monitor(panelMonitor, p, pollPeriod=0.1, ...
    type="graphical", ...
    FontSize=14, ...
    Styles=struct( ...
        Platform="lamp", Trough="lamp", InTrial="lamp", ...
        DelayPeriod="lamp", RespWindow="lamp"));





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
gui.Parameter_Control(layoutTrialControls,P.Depth,BoundProperty='Min',Text="Minimum Depth (%):");


% >> Max Depth
gui.Parameter_Control(layoutTrialControls,P.Depth,BoundProperty='Max',autoCommit=true,Text="Maximum Depth (%):");


% >> Step on Miss
gui.Parameter_Control(layoutTrialControls,P.Depth_StepOnMiss,autoCommit=true,Text="Increment on Miss (%):");

% >> Step on Hit
gui.Parameter_Control(layoutTrialControls,P.Depth_StepOnHit,autoCommit=true,Text="Decrement on Hit (%):");





% >> Probability of Catch Trial
gui.Parameter_Control(layoutTrialControls,P.P_Catch,autoCommit=true,Text="p(Catch Trial):");




% TRIAL CONTROLS --------------------------------------------------
h = uilabel(layoutTrialControls);
h.Text = "Trial Parameters"; 
h.FontSize = 16;
h.FontWeight = 'bold';

% >> Intertrial Interval
gui.Parameter_Control(layoutTrialControls,P.ITIDur,Text="Intertrial Interval (ms):");


% note that "Pre" and "Post" stimulus refer to the Stimulus durations
% >> Pre-stimulus portion of response window
gui.Parameter_Control(layoutTrialControls,P.RespWinPreStim,Text="RW Pre-Stimulus Duration (ms):");
        

% >> Post-stimulus portion of response window
gui.Parameter_Control(layoutTrialControls,P.RespWinPostStim,Text="RW Post-Stimulus Duration (ms):");


% >> Repeat Delay Following Abort Option
h = gui.Parameter_Control(layoutTrialControls,P.RepeatDelayOnAbort,Type='checkbox',autoCommit=true,Text="Repeat Delay on Abort:");
h.Value = P.RepeatDelayOnAbort.Value; % ensure checkbox reflects the parameter value (in case it was loaded from a previous session)


% >> Stimulus Delay (direct value)
hStimDelayValue = gui.Parameter_Control(layoutTrialControls,P.StimDelay,autoCommit=true,Text="Stimulus Delay (ms):");



% >> Stimulus Delay (toggle randomization)
hStimDelayRand = gui.Parameter_Control(layoutTrialControls,P.StimDelay,Type='checkbox',autoCommit=true,BoundProperty='isRandom',Text="Randomize Stimulus Delay:");

% >> Stimulus Delay (Minimum for randomization)
hStimDelayMin = gui.Parameter_Control(layoutTrialControls,P.StimDelay,autoCommit=true,BoundProperty='Min',Text="Stimulus Delay Min (ms):");

% >> Stimulus Delay (Maximum for randomization)
hStimDelayMax = gui.Parameter_Control(layoutTrialControls,P.StimDelay,autoCommit=true,BoundProperty='Max',Text="Stimulus Delay Max (ms):");



hStimDelayRand.PostUpdateFcn = @set_stimdelay_randomization_state;
hStimDelayRand.PostUpdateFcnArgs = {hStimDelayValue,hStimDelayMin,hStimDelayMax};
set_stimdelay_randomization_state(hStimDelayRand,P.StimDelay.isRandom,P.StimDelay,hStimDelayValue,hStimDelayMin,hStimDelayMax);


% >> Stimulus Delay Training Mode --- launches a small gui to adjust parameters for training with variable stimulus delay
h = uibutton(layoutTrialControls,"state");
h.Text = "Stimulus Delay Training Mode";
h.ValueChangedFcn = @(src,event) gui.eval_staircase_training_mode(obj,[],event,P.StimDelay, ...
        StepUp = P.StimDelayTrain_StepUp.Value, ...
        StepDown = P.StimDelayTrain_StepDown.Value);



        
% >> Number of Pellets to Deliver
gui.Parameter_Control(layoutTrialControls,P.NumPellets,Type='dropdown',Text="# Pellets:");


% >> Timeout Duration
gui.Parameter_Control(layoutTrialControls,P.TimeoutDur,Text="Timeout Duration (ms):");






% SOUND CONTROLS -----------------------------------------------------

% >> dB SPL
if isfield(P,'dBSPL')
    gui.Parameter_Control(layoutSoundControls,P.dBSPL,Text="Sound Level (dB SPL):");
end

% >> Tone dB SPL
if isfield(P,'TonedBSPL')
    gui.Parameter_Control(layoutSoundControls,P.TonedBSPL,Text="Tone Sound Level (dB SPL):");
end

% >> Noise dB SPL
if isfield(P,'NoisedBSPL')
    gui.Parameter_Control(layoutSoundControls,P.NoisedBSPL,Text="Noise Sound Level (dB SPL):");
end

% >> Duration
if isfield(P,'StimDur')
    gui.Parameter_Control(layoutSoundControls,P.StimDur,Text="Stimulus Duration (ms):");
end

% >> Modulation Rate
if isfield(P,'Rate')
    gui.Parameter_Control(layoutSoundControls,P.Rate,Text="Modulation Rate (Hz):");
end






% Commit button ---------------------------------------------
h = gui.Parameter_Update(R,layoutMain);
h.Button.Layout.Row = [9 10];
h.Button.Layout.Column = [1 2];
h.Button.Text = ["Update" "Parameters"];
h.Button.FontSize = 24;

% find all 'Parameter_Control' objects
hp = findall(fig,'-regexp','tag','^PC_');
h.watchedHandles = [hp.UserData];




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




% Add listeners for updating the "Next Trial" table and other dynamic elements based on trial events
obj.hl_NewTrial   = addlistener(R.HELPER,'NewTrial',@(src,evnt) obj.update_NextTrial(src,evnt));
obj.hl_ModeChange = addlistener(R.HELPER,'ModeChange',@(src,ev) obj.onModeChange(src,ev));

% Add listener for updating the Psychophysics plot based on new data
obj.hl_NewData    = addlistener(obj.Psych.Helper,'NewData',@(src,evnt) obj.update_NewData(src,evnt));










% Axes for Main Plot ------------------------------------------------
axPsych = uiaxes(layoutMain);
axPsych.Layout.Row = [3 5];
axPsych.Layout.Column = [3 7];

obj.Psych.Plot(axPsych);





% Panel for "Performance" --------------------------------------------
panelPerformance = uipanel(layoutMain, 'Title', 'Session Performance');
panelPerformance.Layout.Row = [1 2];
panelPerformance.Layout.Column = 7;

layoutPerformance = uigridlayout(panelPerformance,[2 1]);
layoutPerformance.ColumnWidth = {'1x'};
layoutPerformance.RowHeight = {'fit','1x'};
layoutPerformance.RowSpacing = 4;
layoutPerformance.Padding = [0 0 0 0];

% obj.ModeIndicator = gui.ModeIndicator(layoutPerformance, FontSize=12);
% obj.ModeIndicator.attachRuntime(R);
% obj.ModeIndicator.setState(hw.DeviceState.Standby);

% > Performance
h = uilabel(layoutPerformance);
h.Tag = 'lblPerformance';
h.Layout.Row = 2;
h.Text = "0";
h.FontColor = 'r';
h.FontSize = 18;
h.FontWeight = 'bold';
h.HorizontalAlignment = "left";
obj.lblPerformance = h;


% Panel for Scatter plot ------------------------------------------------
panelScatter = uipanel(layoutMain, 'Title', 'Parameter Scatter');
panelScatter.Layout.Row = [6 10];
panelScatter.Layout.Column = 5;
obj.h_ScatterPanel = gui.ParameterScatter(R,panelScatter, ...
    PreferenceTag  = 'AppetitiveDetection_ScatterPlot', ...
    XParameter     = P.Depth.validName, ...
    YParameter     = P.RespLatency.validName, ...
    ColorParameter = P.RespCode.validName);


% Panel for "Response History" --------------------------------------
panelResponseHistory = uipanel(layoutMain, 'Title', 'Response History');
panelResponseHistory.Layout.Row = [6 11];
panelResponseHistory.Layout.Column = [6 7];

% > Response History Table
obj.ResponseHistory = gui.History(obj.Psych,panelResponseHistory);
obj.ResponseHistory.BitColors = ["#c8ffd9", "#ffcdcd", "#b3e1ff","#ffeacf","#faffcc"]; % override default BitMask colors with black for no response, orange for miss, and black for hit
obj.ResponseHistory.ParametersOfInterest = {'Depth','TrialType','RespLatency'};
obj.ResponseHistory.ParameterColumnFormats = {'%0.3f %%', '%d', '%.0f ms'};


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

% simple_layout(p)
% Helper function to create a simple 1x1 uigridlayout inside a parent panel.
% Used for consistent layout of subpanels in the GUI.
%
% Parameters:
%   p : uipanel
%       The parent panel in which to create the layout.
%
% Returns:
%   h : uigridlayout
%       The created grid layout object.
function h = simple_layout(p)
    h = uigridlayout(p);
    h.ColumnWidth = {'1x'};
    h.RowHeight = {'1x'};
    h.Padding = [0 0 0 0];
end


function set_stimdelay_randomization_state(src,newValue,param,hStimDelayValue,hStimDelayMin,hStimDelayMax)
% set_stimdelay_randomization_state(src,newValue,param,hStimDelayValue,hStimDelayMin,hStimDelayMax)
% Keep StimDelay randomization state and related controls synchronized.
%
% Parameters:
%   src : gui.Parameter_Control
%       RandomizeStimDelay software parameter that triggered the update.
%   newValue : logical scalar
%       New RandomizeStimDelay value.
%   param : hw.Parameter
%       Bound parameter passed by gui.Parameter_Control PostUpdateFcn (unused).
%   hStimDelayValue : gui.Parameter_Control
%       UI control for direct StimDelay value editing.
%   hStimDelayMin, hStimDelayMax : gui.Parameter_Control
%       UI controls for StimDelay randomized min and max values.

arguments
    src %(1,1) gui.Parameter_Control
    newValue% (1,1) logical
    param
    hStimDelayValue (1,1) gui.Parameter_Control
    hStimDelayMin (1,1) gui.Parameter_Control
    hStimDelayMax (1,1) gui.Parameter_Control
end

if isempty(src), return; end

if isstruct(newValue)
    newValue = newValue.Value;
end

isRandom = logical(newValue);
%pStimDelay.isRandom = isRandom;

if isRandom
    editState = "off";
    minMaxState = "on";
    valueFieldColor = [0.94 0.94 0.94];
else
    % Allow direct fixed-value editing when randomization is disabled.
    editState = "on";
    minMaxState = "off";
    valueFieldColor = hStimDelayValue.colorNormal;
end

%hStimDelayValue.h_uiobj.Limits = [pStimDelay.Min pStimDelay.Max];
hStimDelayValue.h_uiobj.Editable = editState;
hStimDelayValue.h_uiobj.BackgroundColor = valueFieldColor;

hStimDelayMin.h_uiobj.Enable = minMaxState;
hStimDelayMax.h_uiobj.Enable = minMaxState;

if ishandle(hStimDelayMax.h_label)
    hStimDelayMax.h_label.Enable = minMaxState;
end
if ishandle(hStimDelayMin.h_label)
    hStimDelayMin.h_label.Enable = minMaxState;
end
end
