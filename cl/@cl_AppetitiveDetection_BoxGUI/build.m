function build(obj, fig)
% build(obj, fig)
% Assemble the layout, controls, panels, and plots for the Appetitive
% Detection task. Called once by the gui.BoxGUI constructor.
%
% Parameters:
%   obj : cl_AppetitiveDetection_BoxGUI instance
%   fig : uifigure created by gui.BoxGUI
%
% Controls resolve parameters by name through obj.P; names absent from the
% loaded protocol are skipped so the same layout serves every variant of
% the paradigm (and the hardware-free self-test run).
%
% Runtime parameters used:
% Hardware parameters:
%   dBSPL (optional) : Broadband stimulus level in dB SPL.
%   DelayPeriod : Internal delay-period state monitor.
%   DropPellet : Momentary hardware trigger to dispense a pellet.
%   ITIDur : Intertrial interval duration in ms.
%   InTrial : Logical indicator that a trial is currently active.
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
%   Shape : Toggle control for triggering shape playback/behavior.
%   SpoofTrough : Momentary trigger emulating a trough beam break.
%   StimDur (optional) : Stimulus duration in ms.
%   TimeoutDur : Timeout penalty duration in ms.
%   TonedBSPL (optional) : Tone stimulus level in dB SPL.
%   TrialDelivery : Toggle to enable automated trial delivery.
%   Trough : Trough sensor/state readout for monitoring.
%
% Software parameters:
%   Depth : Staircase-controlled modulation depth.
%   Depth_StepOnHit : Staircase depth decrement applied after hits.
%   Depth_StepOnMiss : Staircase depth increment applied after misses.
%   ManualTrigger : Toggle to manually trigger/observe a trial.
%   ReminderTrials : Toggle for reminder trial mode.
%   RepeatDelayOnAbort : Repeat current delay setting after abort when enabled.
%   RespWinPostStim : Post-stimulus response-window segment duration in ms.
%   RespWinPreStim : Pre-stimulus response-window segment duration in ms.
%   StimDelay : Delay before stimulus onset; supports fixed or randomized mode.
%   StimDelayTrain_StepDown : Training step size for decreasing stimulus delay.
%   StimDelayTrain_StepUp : Training step size for increasing stimulus delay.
%
% Documentation: documentation/gui/gui_BoxGUI.md
% Documentation: documentation/layouts/cl_AppetitiveDetection_GUI_B_layout.md

R = obj.RUNTIME;
P = obj.P;

layoutMain = uigridlayout(fig, [11, 7]);
layoutMain.RowHeight   = {60, 40, 90, 110, 60, 130, 40, '1x','1x','1x',40};
layoutMain.ColumnWidth = {150, 150, 100, '1x', '1x','1x', '1x'};
layoutMain.Padding     = [1 1 1 1];


% CONTROL BUTTONS ---------------------------------------
buttonLayout = uigridlayout(layoutMain,[2 3]);
buttonLayout.Layout.Row    = 1;
buttonLayout.Layout.Column = [1 4];
buttonLayout.Padding       = [0 0 0 0];
buttonLayout.ColumnWidth   = repmat({'1x'},1,6);
buttonLayout.RowHeight     = {'1x'};
buttonLayout.RowSpacing    = 0;
buttonLayout.ColumnSpacing = 0;

% Shape and Reminder hooks hang off the hw.Parameter rather than the
% control so they also fire when the value is written from elsewhere
% (phase load, remote set).
attach_trigger(P,'~Shape',          @cl_AppetitiveDetection_BoxGUI.trigger_Shape, R);
attach_trigger(P,'~ReminderTrials', @cl_AppetitiveDetection_BoxGUI.trigger_ReminderTrial, R);

% '~'-prefixed names also resolve the unprefixed parameter, so these calls
% work whether or not the protocol marks the toggles with the prefix.
obj.addButton(buttonLayout,'DropPellet',      Type='momentary', Text='Pellet');
obj.addButton(buttonLayout,'~Shape',          Type='toggle',    Text='Shape');
obj.hReminder = obj.addButton(buttonLayout,'~ReminderTrials', Type='toggle', Text='Reminder');
obj.addButton(buttonLayout,'~ManualTrigger',  Type='toggle',    Text='Observe');
obj.addButton(buttonLayout,'~TrialDelivery',  Type='toggle',    Text='Deliver Trials');
obj.addButton(buttonLayout,'SpoofTrough',     Type='momentary', Text='Trough');

bcmActive = min(lines(7)+0.4,1);
bNames = fieldnames(obj.hButtons);
for i = 1:numel(bNames)
    h = obj.hButtons.(bNames{i});
    h.colorNormal   = fig.Color;
    h.colorOnUpdate = bcmActive(mod(i-1,7)+1,:);
    set(h.h_uiobj, FontWeight='bold', FontSize=15, Enable='on');
end


% PHASE SELECTION ------------------------------------------
% Phase definitions are shared with the original GUI_B implementation.
PhasePath = fullfile(EPsychInfo.root,'cl','@cl_AppetitiveDetection_BoxGUI','Phases');
if ~isfolder(PhasePath)
    PhasePath = fullfile(EPsychInfo.root,'cl','@cl_AppetitiveDetection_GUI_B','Phases');
end

if isfolder(PhasePath)
    obj.PhaseSelector = obj.register(gui.PhaseSelector(R,PhasePath));
    h = uipanel(layoutMain);
    h.Layout.Row    = [1 2];
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
panelMonitor.Layout.Column = 5;
panelMonitor.Layout.Row    = [6 10];

monitorParams = collect_params(P, {'Platform','Trough','InTrial','DelayPeriod','RespWindow', ...
    'PelletTotal','StimDelay','RespWinDelay','RespLatency','RespCode'});

obj.ParameterMonitor = obj.register(gui.Parameter_Monitor(panelMonitor, monitorParams, ...
    pollPeriod = 0.1, ...
    type       = "graphical", ...
    FontSize   = 14, ...
    Styles     = struct( ...
        Platform="lamp", Trough="lamp", InTrial="lamp", ...
        DelayPeriod="lamp", RespWindow="lamp")));


% LAYOUTS -------------------------------------------------
layoutTrialControls = obj.controlColumn(layoutMain, ...
    Row=[2 6], Column=[1 2], Rows=20);

layoutSoundControls = obj.controlColumn(layoutMain, Title='Sound Controls', ...
    Row=[7 8], Column=[1 2], Rows=9);


% STAIRCASE CONTROLS --------------------------------------------------

% >> Staircase label
h = uilabel(layoutTrialControls);
h.Text = "Staircase Parameters";
h.FontSize = 16;
h.FontWeight = 'bold';

% >> Min Depth
obj.addControl(layoutTrialControls,'Depth',BoundProperty='Min',Text="Minimum Depth (%):");

% >> Max Depth
obj.addControl(layoutTrialControls,'Depth',BoundProperty='Max',autoCommit=true,Text="Maximum Depth (%):");

% >> Step on Miss
obj.addControl(layoutTrialControls,'Depth_StepOnMiss',autoCommit=true,Text="Increment on Miss (%):");

% >> Step on Hit
obj.addControl(layoutTrialControls,'Depth_StepOnHit',autoCommit=true,Text="Decrement on Hit (%):");

% >> Probability of Catch Trial
obj.addControl(layoutTrialControls,'P_Catch',autoCommit=true,Text="p(Catch Trial):");


% TRIAL CONTROLS --------------------------------------------------
h = uilabel(layoutTrialControls);
h.Text = "Trial Parameters";
h.FontSize = 16;
h.FontWeight = 'bold';

% >> Intertrial Interval
obj.addControl(layoutTrialControls,'ITIDur',Text="Intertrial Interval (ms):");

% note that "Pre" and "Post" stimulus refer to the Stimulus durations
% >> Pre-stimulus portion of response window
obj.addControl(layoutTrialControls,'RespWinPreStim',Text="RW Pre-Stimulus Duration (ms):");

% >> Post-stimulus portion of response window
obj.addControl(layoutTrialControls,'RespWinPostStim',Text="RW Post-Stimulus Duration (ms):");

% >> Repeat Delay Following Abort Option
h = obj.addControl(layoutTrialControls,'RepeatDelayOnAbort',Type='checkbox',autoCommit=true, ...
    Text="Repeat Delay on Abort:");
if ~isempty(h)
    % reflect a value carried over from a previous session
    h.Value = h.Parameter.Value;
end

% >> Stimulus Delay (direct value)
hStimDelayValue = obj.addControl(layoutTrialControls,'StimDelay',autoCommit=true, ...
    Text="Stimulus Delay (ms):");

% >> Stimulus Delay (toggle randomization)
hStimDelayRand = obj.addControl(layoutTrialControls,'StimDelay',Type='checkbox',autoCommit=true, ...
    BoundProperty='isRandom',Text="Randomize Stimulus Delay:");

% >> Stimulus Delay (Minimum for randomization)
hStimDelayMin = obj.addControl(layoutTrialControls,'StimDelay',autoCommit=true, ...
    BoundProperty='Min',Text="Stimulus Delay Min (ms):");

% >> Stimulus Delay (Maximum for randomization)
hStimDelayMax = obj.addControl(layoutTrialControls,'StimDelay',autoCommit=true, ...
    BoundProperty='Max',Text="Stimulus Delay Max (ms):");

pStimDelay = getp(P,'StimDelay');
if ~isempty(hStimDelayRand)
    hStimDelayRand.PostUpdateFcn = @set_stimdelay_randomization_state;
    hStimDelayRand.PostUpdateFcnArgs = {hStimDelayValue,hStimDelayMin,hStimDelayMax};
    set_stimdelay_randomization_state(hStimDelayRand,pStimDelay.isRandom,pStimDelay, ...
        hStimDelayValue,hStimDelayMin,hStimDelayMax);
end

% >> Stimulus Delay Training Mode --- launches a small gui to adjust parameters for training with variable stimulus delay
pStepUp   = getp(P,'StimDelayTrain_StepUp');
pStepDown = getp(P,'StimDelayTrain_StepDown');
if ~isempty(pStimDelay) && ~isempty(pStepUp) && ~isempty(pStepDown)
    h = uibutton(layoutTrialControls,"state");
    h.Text = "Stimulus Delay Training Mode";
    h.ValueChangedFcn = @(src,event) gui.eval_staircase_training_mode(obj,[],event,pStimDelay, ...
        StepUp   = pStepUp.Value, ...
        StepDown = pStepDown.Value);
end

% >> Number of Pellets to Deliver
obj.addControl(layoutTrialControls,'NumPellets',Type='dropdown',Text="# Pellets:");

% >> Timeout Duration
obj.addControl(layoutTrialControls,'TimeoutDur',Text="Timeout Duration (ms):");


% SOUND CONTROLS -----------------------------------------------------

% >> dB SPL
obj.addControl(layoutSoundControls,'dBSPL',Text="Sound Level (dB SPL):");

% >> Tone dB SPL
obj.addControl(layoutSoundControls,'TonedBSPL',Text="Tone Sound Level (dB SPL):");

% >> Noise dB SPL
obj.addControl(layoutSoundControls,'NoisedBSPL',Text="Noise Sound Level (dB SPL):");

% >> Duration
obj.addControl(layoutSoundControls,'StimDur',Text="Stimulus Duration (ms):");

% >> Modulation Rate
obj.addControl(layoutSoundControls,'Rate',Text="Modulation Rate (Hz):");


% Commit button ---------------------------------------------
% watchedHandles are wired from the component registry after build
obj.UpdateButton = obj.addUpdateButton(layoutMain);
obj.UpdateButton.Button.Layout.Row    = [9 10];
obj.UpdateButton.Button.Layout.Column = [1 2];
obj.UpdateButton.Button.Text     = ["Update" "Parameters"];
obj.UpdateButton.Button.FontSize = 24;


% Filename field -----------------------------------------------
panelFilename = uipanel(layoutMain, 'Title', 'Filename');
panelFilename.Layout.Row    = 11;
panelFilename.Layout.Column = [3 5];

layoutFilename = simple_layout(panelFilename);

try
    obj.FilenameField = obj.register(gui.FilenameValidator(R,layoutFilename,R.TRIALS.DataFilename));
catch ME
    % a runtime without compiled trials (self-test) has no filename yet
    vprintf(2,'cl_AppetitiveDetection_BoxGUI: filename field skipped (%s)',ME.message)
end


% Panel for "Next Trial" ----------------------------------------
panelNextTrial = uipanel(layoutMain, 'Title', 'Next Trial');
panelNextTrial.Layout.Row    = [1 2];
panelNextTrial.Layout.Column = 6;

layoutNextTrial = simple_layout(panelNextTrial);

tableNextTrial = uitable(layoutNextTrial);
tableNextTrial.Tag            = 'tblNextTrial';
tableNextTrial.ColumnName     = {'Depth','TrialType'};
tableNextTrial.RowName        = [];
tableNextTrial.ColumnEditable = false;
tableNextTrial.FontSize       = 20;
obj.tableNextTrial = tableNextTrial;


% Axes for Main Plot ------------------------------------------------
axPsych = uiaxes(layoutMain);
axPsych.Layout.Row    = [3 5];
axPsych.Layout.Column = [3 7];

if ~isempty(obj.Psych)
    obj.Psych.Plot(axPsych);
end


% Panel for "Performance" --------------------------------------------
panelPerformance = uipanel(layoutMain, 'Title', 'Session Performance');
panelPerformance.Layout.Row    = [1 2];
panelPerformance.Layout.Column = 7;

layoutPerformance = uigridlayout(panelPerformance,[2 1]);
layoutPerformance.ColumnWidth = {'1x'};
layoutPerformance.RowHeight   = {'fit','1x'};
layoutPerformance.RowSpacing  = 4;
layoutPerformance.Padding     = [0 0 0 0];

h = uilabel(layoutPerformance);
h.Tag        = 'lblPerformance';
h.Layout.Row = 2;
h.Text       = "0";
h.FontColor  = 'r';
h.FontSize   = 18;
h.FontWeight = 'bold';
h.HorizontalAlignment = "left";
obj.lblPerformance = h;


% Panel for Scatter plot ------------------------------------------------
panelScatter = uipanel(layoutMain, 'Title', 'Parameter Scatter');
panelScatter.Layout.Row    = [6 10];
panelScatter.Layout.Column = [3 4];

scatterArgs = {'PreferenceTag','AppetitiveDetection_ScatterPlot'};
scatterSel  = {'XParameter','Depth'; 'YParameter','RespLatency'; 'ColorParameter','RespCode'};
for i = 1:size(scatterSel,1)
    q = getp(P,scatterSel{i,2});
    if ~isempty(q)
        scatterArgs = [scatterArgs, scatterSel(i,1), {q.validName}];
    end
end
obj.h_ScatterPanel = obj.register(gui.ParameterScatter(R,panelScatter,scatterArgs{:}));


% Panel for "Response History" --------------------------------------
panelResponseHistory = uipanel(layoutMain, 'Title', 'Response History');
panelResponseHistory.Layout.Row    = [6 11];
panelResponseHistory.Layout.Column = [6 7];

if ~isempty(obj.Psych)
    obj.ResponseHistory = obj.register(gui.History(obj.Psych,panelResponseHistory));
    % green hit, red miss, blue correct reject, orange false alarm, yellow abort
    obj.ResponseHistory.BitColors = ["#c8ffd9", "#ffcdcd", "#b3e1ff","#ffeacf","#faffcc"];
    obj.ResponseHistory.ParametersOfInterest    = {'Depth','TrialType','RespLatency'};
    obj.ResponseHistory.ParameterColumnFormats  = {'%0.3f %%', '%d', '%.0f ms'};
end


% update panel title aesthetics
hp = findobj(fig,'type','uipanel');
set(hp, ...
    BorderType = "none", ...
    FontWeight = "bold", ...
    FontSize   = 13)

% update dropdown aesthetics
ddh = findobj(fig,'Type', 'uidropdown');
set(ddh,FontColor = 'b');

end






% used by build

function p = getp(P,name)
% p = getp(P,name)
% Resolve a parameter by name against the cached parameter struct, matching
% gui.BoxGUI: a leading '~' or '!' is optional, so one name serves
% protocols that mark the parameter as a trigger and those that do not.
% Returns [] when the loaded protocol has no such parameter.
p = [];
candidates = unique({matlab.lang.makeValidName(name), ...
    matlab.lang.makeValidName(regexprep(name,'^[~!]+',''))},'stable');
for c = candidates
    if isfield(P,c{1})
        p = P.(c{1});
        return
    end
end
vprintf(2,'cl_AppetitiveDetection_BoxGUI: parameter "%s" not available',name)
end


function attach_trigger(P,name,fcn,RUNTIME)
% attach_trigger(P,name,fcn,RUNTIME)
% Install an hw.Parameter PostUpdateFcn, skipping parameters the loaded
% protocol does not define.
p = getp(P,name);
if isempty(p), return; end
p.PostUpdateFcn     = fcn;
p.PostUpdateFcnArgs = {RUNTIME};
end


function p = collect_params(P,names)
% p = collect_params(P,names)
% Gather hw.Parameter objects by name, in the order given, dropping names
% absent from the loaded protocol.
p = hw.Parameter.empty(1,0);
for i = 1:numel(names)
    q = getp(P,names{i});
    if ~isempty(q)
        p(end+1) = q;
    end
end
end


function h = simple_layout(p)
% h = simple_layout(p)
% Single-cell grid layout filling a parent panel.
h = uigridlayout(p);
h.ColumnWidth = {'1x'};
h.RowHeight   = {'1x'};
h.Padding     = [0 0 0 0];
end


function set_stimdelay_randomization_state(src,newValue,param,hStimDelayValue,hStimDelayMin,hStimDelayMax)
% set_stimdelay_randomization_state(src,newValue,param,hStimDelayValue,hStimDelayMin,hStimDelayMax)
% Keep StimDelay randomization state and related controls synchronized.
%
% Parameters:
%   src : gui.Parameter_Control
%       Randomization checkbox that triggered the update.
%   newValue : logical scalar
%       New isRandom value.
%   param : hw.Parameter
%       Bound parameter passed by gui.Parameter_Control PostUpdateFcn (unused).
%   hStimDelayValue : gui.Parameter_Control
%       UI control for direct StimDelay value editing.
%   hStimDelayMin, hStimDelayMax : gui.Parameter_Control
%       UI controls for StimDelay randomized min and max values.

if isempty(src) || isempty(hStimDelayValue) || isempty(hStimDelayMin) || isempty(hStimDelayMax)
    return
end

if isstruct(newValue)
    newValue = newValue.Value;
end

isRandom = logical(newValue);

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
