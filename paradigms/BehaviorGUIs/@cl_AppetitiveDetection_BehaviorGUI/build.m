function build(obj, fig)
% build(obj, fig)
% Assemble the layout, controls, panels, and plots for the Appetitive
% Detection task. Called once by the gui.BehaviorGUI constructor.
%
% Parameters:
%   obj : cl_AppetitiveDetection_BehaviorGUI instance
%   fig : uifigure created by gui.BehaviorGUI
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
%   P_Catch : Catch-trial hazard function. Min is the floor probability, Value
%       the step added per delivered stimulus trial, Max the ceiling.
%   P_Catch_Current (optional) : Live catch probability, created by
%       cl_AppetitiveStimDetect at run start; shown in the Trial State monitor.
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
%   CatchTrialsEnabled (optional) : Checkbox gating catch-trial presentation,
%       created by cl_AppetitiveStimDetect at run start (with
%       PersistWithPhase, so its state is saved to and restored from a phase).
%       When absent the p(Catch) fields stay enabled and catch trials are
%       always scheduled.
%   StimDelayTrainingEnabled (optional) : Checkbox enabling stimulus-delay
%       training mode; created here when the protocol does not declare it.
%       Marked PersistWithPhase, so a phase carries the training state.
%   StimDelayList (optional) : Ends of the block-randomized stimulus-delay
%       list -- its Min and Max, with StimDelayStep as the spacing, so
%       1000 / 4000 / 250 means 1000:250:4000 ms. Its presence is what selects
%       the block-randomization controls below over the original
%       StimDelay.isRandom pair; see cl_AppetitiveStimDetect.
%   StimDelayStep (optional) : Spacing between list values, in ms. Created by
%       cl_AppetitiveStimDetect (or here) when the protocol has none -- it
%       cannot live on StimDelayList.Value, which hw.Parameter clamps into
%       [Min Max].
%   StimDelayJitter (optional) : +/- ms added to each delivered delay.
%   StimDelayBlockEnabled (optional) : The "Randomize Stimulus Delay" checkbox
%       when StimDelayList is defined, created by cl_AppetitiveStimDetect at
%       run start (or here for the hardware-free launch). PersistWithPhase, so
%       a phase carries whether the subject trains on a varying delay.
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
% Documentation: documentation/gui/gui_BehaviorGUI.md
% Documentation: documentation/layouts/cl_AppetitiveDetection_GUI_B_layout.md

R = obj.RUNTIME;
P = obj.P;

layoutMain = uigridlayout(fig, [11, 7]);
layoutMain.RowHeight   = {80, 40, 90, 110, 60, 130, 40, '1x','1x','1x',40};
% Column 5 (Trial State) is fixed: it holds label/value text that does not
% benefit from extra width, so pinning it near its content width and giving
% column 4 the heavier weight sends the surplus to the Parameter Scatter.
layoutMain.ColumnWidth = {150, 150, 100, '1.3x', 250, '1x', '1x'};
layoutMain.Padding     = [1 1 1 1];


% CONTROL BUTTONS ---------------------------------------
buttonLayout = uigridlayout(layoutMain,[2 3]);
buttonLayout.Layout.Row    = 1;
buttonLayout.Layout.Column = [1 4];
buttonLayout.Padding       = [0 0 0 0];
% Six triggers, Notes, then Regenerate. The last column is wider because its
% label is a two-line phrase rather than a single word -- and because the
% extra width puts a gap between the trigger buttons an operator reaches for
% constantly and the one that interrupts the trial in progress.
buttonLayout.ColumnWidth   = [repmat({'1x'},1,7), {'1.3x'}];
buttonLayout.RowHeight     = {'1x'};
buttonLayout.RowSpacing    = 0;
buttonLayout.ColumnSpacing = 0;

% Shape and Reminder hooks hang off the hw.Parameter rather than the
% control so they also fire when the value is written from elsewhere
% (phase load, remote set).
attach_trigger(P,'~Shape',          @cl_AppetitiveDetection_BehaviorGUI.trigger_Shape, R);
attach_trigger(P,'~ReminderTrials', @cl_AppetitiveDetection_BehaviorGUI.trigger_ReminderTrial, R);

% '~'-prefixed names also resolve the unprefixed parameter, so these calls
% work whether or not the protocol marks the toggles with the prefix.
obj.addButton(buttonLayout,'DropPellet',      Type='momentary', Text='Pellet');
obj.addButton(buttonLayout,'~Shape',          Type='toggle',    Text='Shape');
obj.hReminder = obj.addButton(buttonLayout,'~ReminderTrials', Type='toggle', Text='Reminder');
obj.addButton(buttonLayout,'~ManualTrigger',  Type='toggle',    Text='Observe');
obj.addButton(buttonLayout,'~TrialDelivery',  Type='toggle',    Text='Deliver Trials');
obj.addButton(buttonLayout,'SpoofTrough',     Type='momentary', Text='Trough');

% Session notes: a button rather than a panel, since this layout has no
% spare rows. It opens the notes in a window of their own, and what is
% typed there is saved with the session's data (Info.Notes) and journaled
% as it is typed. Placed after the triggers so it takes the last column.
obj.NotesButton = obj.addNotesButton(buttonLayout, Text='Notes');
set(obj.NotesButton.OpenH, FontWeight='bold', FontSize=15);

% Regenerate the pending trial: dispatch it again so the stimulus delay and
% any other randomized parameter redraw, and committed edits reach the
% hardware without waiting for the next trial.
%
% The button is DEAD until Ctrl+Alt+Shift are all held -- the same gesture
% the Update Parameters button uses -- which is what keeps it out of reach of
% a mis-click in a row of buttons the operator uses constantly. This GUI also
% holds a gui.Parameter_Update, created below, which reads the same three
% modifiers; both take them from this GUI's gui.KeyBindings, so the order the
% two are built in no longer decides which of them sees the key.
%
% *** ONCE ARMED IT INTERRUPTS THE TRIAL IN PROGRESS AND ASKS NOTHING
% FURTHER. *** Pressed while the animal is on the platform it restarts the
% delay and response window under the subject, and the DATA record for that
% trial ends up carrying the values from the LAST dispatch. It is amber and
% set apart from the trigger buttons for that reason. The selector is NOT
% re-run (Reselect stays false): cl_AppetitiveStimDetect's selection pass is
% where the staircase steps, the catch hazard climbs, and a queued reminder
% is consumed, none of which should move because a delay was redrawn.
% Each press is written into the session notes, which is the only trace the
% data file keeps of it.
obj.RegenerateButton = obj.addRegenerateTrial(buttonLayout, ShowIcon=false);
set(obj.RegenerateButton.ButtonH, Text=["Regenerate";"Trial"], ...
    FontWeight='bold', FontSize=15);

bcmActive = min(lines(7)+0.4,1);
bNames = fieldnames(obj.hButtons);
for i = 1:numel(bNames)
    h = obj.hButtons.(bNames{i});
    h.colorNormal   = fig.Color;
    h.colorOnUpdate = bcmActive(mod(i-1,7)+1,:);
    set(h.h_uiobj, FontWeight='bold', FontSize=15, Enable='on');
end


% SESSION CLOCK ---------------------------------------------
% Only open cell in the top row: buttons fill columns 1-4, and the Next
% Trial / Performance panels span columns 6-7 across rows 1-2.
obj.SessionClock = obj.register(gui.SessionClock(layoutMain, FontSize=10));
obj.SessionClock.PanelH.Layout.Row    = 1;
obj.SessionClock.PanelH.Layout.Column = 5;
obj.SessionClock.attachRuntime(R);
obj.SessionClock.start();


% INFO ----------------------------------------------------

% >> Trial state monitor
% Sensor and trial-state flags render as lamps for at-a-glance reading;
% counters and latencies render as value labels that flash on change.
% Ordering matters: the five lamps are grouped ahead of the value readouts.
panelMonitor = uipanel(layoutMain, 'Title', 'Trial State');
panelMonitor.Layout.Column = 5;
panelMonitor.Layout.Row    = [6 8];

monitorParams = collect_params(P, {'Platform','Trough','InTrial','DelayPeriod','RespWindow', ...
    'PelletTotal','StimDelay','RespWinDelay','RespLatency','RespCode','P_Catch_Current'});

obj.ParameterMonitor = obj.register(gui.Parameter_Monitor(panelMonitor, monitorParams, ...
    pollPeriod = 0.1, ...
    type       = "graphical", ...
    FontSize   = 14, ...
    Styles     = struct( ...
        Platform="lamp", Trough="lamp", InTrial="lamp", ...
        DelayPeriod="lamp", RespWindow="lamp")));


% PHASE SELECTION ------------------------------------------
% Phase definitions are shared with the original GUI_B implementation.
PhasePath = fullfile(EPsychInfo.root,'paradigms','BehaviorGUIs','@cl_AppetitiveDetection_BehaviorGUI','Phases');
if ~isfolder(PhasePath)
    PhasePath = fullfile(EPsychInfo.root,'cl','@cl_AppetitiveDetection_GUI_B','Phases'); % pre-rename layout
end

% Built unconditionally: gui.PhaseSelector tolerates a missing or empty phase
% directory (empty dropdown, Save still available), and hiding the control
% because no phases exist yet leaves no way to create the first one.
obj.PhaseSelector = obj.register(gui.PhaseSelector(R,PhasePath));
h = uipanel(layoutMain);
h.Layout.Row    = [2 3];
h.Layout.Column = [1 2];
obj.h_PhaseSelector = obj.PhaseSelector.createGUI(h);


% LAYOUTS -------------------------------------------------
% 22 rows: 21 controls plus one spare (the p(Catch) and stimulus-delay
% bounds each occupy a single Type='range' row). The column scrolls, so a
% protocol that defines fewer parameters simply leaves rows empty.
layoutTrialControls = obj.controlColumn(layoutMain, ...
    Row=[4 8], Column=[1 2], Rows=22);

layoutSoundControls = obj.controlColumn(layoutMain, Title='Sound Controls', ...
    Row=9, Column=[1 2], Rows=9);


% STAIRCASE CONTROLS --------------------------------------------------

% >> Staircase label
h = uilabel(layoutTrialControls);
h.Text = "Staircase Parameters";
h.FontSize = 16;
h.FontWeight = 'bold';

% >> Min Depth
obj.addControl(layoutTrialControls,'Depth',BoundProperty='Min',autoCommit=true,Text="Minimum Depth (dB):");

% >> Max Depth
obj.addControl(layoutTrialControls,'Depth',BoundProperty='Max',autoCommit=true,Text="Maximum Depth (dB):");

% >> Step on Miss
obj.addControl(layoutTrialControls,'Depth_StepOnMiss',autoCommit=true,Text="Increment on Miss (dB):");

% >> Step on Hit
obj.addControl(layoutTrialControls,'Depth_StepOnHit',autoCommit=true,Text="Decrement on Hit (dB):");

% >> Catch-trial hazard function: p starts at Min, rises by Step for every
% delivered stimulus trial up to Max, and resets to Min after a catch trial.
% The live value is shown in the Trial State monitor as P_Catch_Current.
%
% The checkbox gates the whole schedule and greys out the fields it
% controls. cl_AppetitiveStimDetect reads the same parameter (and creates it
% at run start when the protocol does not declare it), so the greyed fields
% and the trial schedule cannot disagree; a protocol without the parameter
% simply gets no checkbox and the always-on behavior.
hCatchEnable = obj.addControl(layoutTrialControls,'CatchTrialsEnabled',Type='checkbox', ...
    autoCommit=true,Text="Present Catch Trials");

% Floor and ceiling are the two ends of one quantity, so they share a row.
hPCatchRange = obj.addControl(layoutTrialControls,'P_Catch',Type='range',autoCommit=true, ...
    Text="p(Catch) Min / Max:");
hPCatchStep  = obj.addControl(layoutTrialControls,'P_Catch',autoCommit=true,Text="p(Catch) Step:");

if ~isempty(hCatchEnable)
    % This is a stage setting, not a momentary button, so a phase must carry
    % it (see hw.Parameter.isTransientControl). cl_AppetitiveStimDetect marks
    % the parameter when it resolves it, but that happens once at run start:
    % asserting it here as well means the flag is right whenever the checkbox
    % exists -- including a protocol that declares the parameter itself, and a
    % session whose selector was constructed before the flag existed.
    hCatchEnable.Parameter.PersistWithPhase = true;

    hCatchEnable.PostUpdateFcn     = @set_catch_trials_state;
    hCatchEnable.PostUpdateFcnArgs = {hPCatchRange,hPCatchStep};
    % Seed the enable state from the value carried over from a previous
    % session or a phase load, which create() has already put in the widget.
    set_catch_trials_state(hCatchEnable,hCatchEnable.Parameter.Value, ...
        hCatchEnable.Parameter,hPCatchRange,hPCatchStep);
end


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
% The control seats itself from the parameter, so a value carried over from a
% previous session is already reflected; re-assigning it here only pushed an
% unseeded (empty) value back through the autoCommit write-back.
obj.addControl(layoutTrialControls,'RepeatDelayOnAbort',Type='checkbox',autoCommit=true, ...
    Text="Repeat Delay on Abort:");

% >> Stimulus Delay (direct value)
hStimDelayValue = obj.addControl(layoutTrialControls,'StimDelay',autoCommit=true, ...
    Text="Stimulus Delay (ms):");

pStimDelay = getp(P,'StimDelay');
pDelayList = getp(P,'StimDelayList');

% Two ways to vary the stimulus delay, chosen by whether the protocol
% declares StimDelayList. The block sequence is the better one -- every
% delay in the list appears its exact share within each block, where
% StimDelay.isRandom draws randi([Min Max]) afresh every trial -- but the
% two cannot both be live: isRandom redraws inside set.Value on dispatch
% and would overwrite the sequence's value. So the checkbox is bound to
% isRandom only for a protocol with no list; with a list it is bound to
% StimDelayBlockEnabled and cl_AppetitiveStimDetect holds isRandom false.
if isempty(pDelayList)
    % >> Stimulus Delay (toggle randomization)
    hStimDelayRand = obj.addControl(layoutTrialControls,'StimDelay',Type='checkbox',autoCommit=true, ...
        BoundProperty='isRandom',Text="Randomize Stimulus Delay:");

    % >> Stimulus Delay (bounds used when randomizing)
    hStimDelayRange = obj.addControl(layoutTrialControls,'StimDelay',Type='range',autoCommit=true, ...
        Text="Stimulus Delay Min / Max (ms):");

    hDelayVarying = {hStimDelayRange};

    if ~isempty(hStimDelayRand)
        hStimDelayRand.PostUpdateFcn = @set_stimdelay_randomization_state;
        hStimDelayRand.PostUpdateFcnArgs = {hStimDelayValue,hStimDelayRange};
        set_stimdelay_randomization_state(hStimDelayRand,pStimDelay.isRandom,pStimDelay, ...
            hStimDelayValue,hStimDelayRange);
    end
else
    % The switch is a real parameter, not widget state, so a phase carries
    % whether a subject trains on a varying delay. cl_AppetitiveStimDetect
    % creates it at run start; ensure_session_setting covers the hardware-free
    % launch (SelfTest I6), where no selector has run. Its default matches the
    % selector's: a list of more than one value is worth randomizing.
    % The step is its own parameter because hw.Parameter clamps Value into
    % [Min Max] and gui.Parameter_Control limits the edit field to the same
    % range: a 250 ms step could be neither stored on nor typed into the
    % 1000-4000 ms list parameter. cl_AppetitiveStimDetect creates it at run
    % start; this call covers the hardware-free launch (SelfTest I6).
    pDelayStep = cl_AppetitiveStimDetect.ensureStimDelayStep(R,pDelayList);

    dfltBlock = numel(cl_AppetitiveStimDetect.stimDelayValues(pDelayList,pDelayStep)) > 1;
    pBlock = ensure_session_setting(R,P,'StimDelayBlockEnabled',dfltBlock, ...
        "Block-randomize the stimulus delay over StimDelayList");

    % >> Stimulus Delay (toggle block randomization)
    hStimDelayRand = obj.addControl(layoutTrialControls,pBlock,Type='checkbox',autoCommit=true, ...
        Text="Randomize Stimulus Delay:");

    % >> Stimulus Delay list: the ends on one row, the spacing on the next.
    % 1000 / 4000 with a step of 250 is 1000:250:4000 ms.
    hDelayListRange = obj.addControl(layoutTrialControls,pDelayList,Type='range',autoCommit=true, ...
        Text="Delay List Min / Max (ms):");
    hDelayListStep  = obj.addControl(layoutTrialControls,pDelayStep,autoCommit=true, ...
        Text="Delay List Step (ms):");

    % >> Jitter added to each delivered delay
    hDelayJitter = obj.addControl(layoutTrialControls,'StimDelayJitter',autoCommit=true, ...
        Text="Delay Jitter (+/- ms):");

    hDelayVarying = {hDelayListRange,hDelayListStep,hDelayJitter};

    if ~isempty(hStimDelayRand)
        % Asserted here as well as in the selector, so the flag is right
        % whenever the checkbox exists -- including a protocol that declares
        % the parameter itself, and a session whose selector predates it.
        hStimDelayRand.Parameter.PersistWithPhase = true;

        hStimDelayRand.PostUpdateFcn = @set_stimdelay_randomization_state;
        hStimDelayRand.PostUpdateFcnArgs = [{hStimDelayValue},hDelayVarying];
        set_stimdelay_randomization_state(hStimDelayRand,hStimDelayRand.Parameter.Value, ...
            hStimDelayRand.Parameter,hStimDelayValue,hDelayVarying{:});
    end
end

% >> Stimulus Delay Training Mode --- launches a small gui to adjust parameters for training with variable stimulus delay
%
% A checkbox over a real parameter rather than a bare state button: the
% button's state lived only in the widget, so nothing recorded whether a
% subject trains on a variable delay and a phase could not restore it.
pStepUp   = getp(P,'StimDelayTrain_StepUp');
pStepDown = getp(P,'StimDelayTrain_StepDown');
pTrainMode = ensure_session_setting(R,P,'StimDelayTrainingEnabled',false, ...
    "Step the stimulus delay after selected trial outcomes (training mode)");
if ~isempty(pStimDelay) && ~isempty(pStepUp) && ~isempty(pStepDown) && ~isempty(pTrainMode)
    hStimDelayTrain = obj.addControl(layoutTrialControls,pTrainMode,Type='checkbox', ...
        autoCommit=true,Text="Stimulus Delay Training Mode");

    % PostUpdateFcn rather than the widget's own ValueChangedFcn:
    % gui.Parameter_Control runs it for external writes too, which is what
    % lets a phase load open or close the training window. The src argument
    % is [] deliberately -- passing the checkbox would disable it and leave
    % the operator no way to switch training back off.
    hStimDelayTrain.PostUpdateFcn = @(~,event,~) ...
        set_stimdelay_training_state(obj,event,pStimDelay,pStepUp,pStepDown, ...
            [{hStimDelayRand,hStimDelayValue},hDelayVarying]);

    % Reopen the training window when the value carried into this session
    % already says training is on (a protocol default, or a phase loaded
    % before this window existed). create() seats the widget, but only a
    % write fires the PostUpdateFcn.
    if logical(pTrainMode.Value)
        hStimDelayTrain.runPostUpdateFcn(struct('PreviousValue',[], ...
            'EventName','Build','Value',true));
    end
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
obj.UpdateButton.Button.Layout.Row    = [10 11];
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
    vprintf(2,'cl_AppetitiveDetection_BehaviorGUI: filename field skipped (%s)',ME.message)
end


% Panel for "Next Trial" ----------------------------------------
panelNextTrial = uipanel(layoutMain, 'Title', 'Next Trial');
panelNextTrial.Layout.Row    = [1 2];
panelNextTrial.Layout.Column = 6;

layoutNextTrial = simple_layout(panelNextTrial);

% TrialTypeNames is the protocol's own text label for TrialType (STIM,
% CATCH, REMIND, ...), so it needs no Formatters decode here.
obj.NextTrialPanel = obj.addNextTrial(layoutNextTrial, ...
    Fields=["Depth","TrialTypeNames"], FontSize=20);


% Axes for Main Plot ------------------------------------------------
axPsych = uiaxes(layoutMain);
axPsych.Layout.Row    = [3 5];
axPsych.Layout.Column = [3 7];

if ~isempty(obj.Psych)
    obj.Psych.Plot(axPsych);
end


% Panel for "Performance" --------------------------------------------
% gui.SessionPerformance computes through a psychophysics.SessionMetrics,
% so the rates here and the psychometric plot read the same trials. The
% header names the trial window in effect; right-click to change it (all
% trials, the last N, or an explicit range) or to add metrics.
panelPerformance = uipanel(layoutMain, 'Title', 'Session Performance');
panelPerformance.Layout.Row    = [1 2];
panelPerformance.Layout.Column = 7;

obj.Performance = obj.addPerformance(panelPerformance, ...
    Metrics=["HitRate","FARate","AbortRate","DPrime"], ...
    FontSize=11, ShowDetail=false);


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
    obj.ResponseHistory.ParameterColumnFormats  = {'%0.1f', '%d', '%.1f ms'};
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
% gui.BehaviorGUI: a leading '~' or '!' is optional, so one name serves
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
vprintf(2,'cl_AppetitiveDetection_BehaviorGUI: parameter "%s" not available',name)
end


function v = step_value(p)
% v = step_value(p)
% Current training step magnitude, falling back to the design-time level.
%
% add_parameter seeds Values, not Value, so a parameter the trial dispatcher
% has not written yet has an empty Value -- and gui.eval_staircase_training_mode
% requires a scalar. That gap is reachable now that training mode can be
% switched by a phase load or a protocol default rather than only by an
% operator clicking mid-session.
v = p.Value;
if isempty(v) && ~isempty(p.Values)
    v = p.Values{1};
end
end


function p = ensure_session_setting(RUNTIME,P,name,defaultValue,description)
% p = ensure_session_setting(RUNTIME,P,name,defaultValue,description)
% Resolve a Boolean operator setting by name, creating it on the session's
% hw.Software interface when the loaded protocol does not declare one.
%
% These are the checkboxes an operator sets for a subject's training stage and
% then leaves alone. They carry UpdateEveryTrial = false because nothing writes
% them from the trial table -- the operator owns the value for the whole
% session -- and PersistWithPhase = true so a saved phase still carries the
% choice. Without the flag, hw.Parameter.isTransientControl reads any writable
% Boolean the dispatcher never refreshes as a momentary button and a phase
% neither saves nor restores it.
%
% Returns [] when there is no runtime or no software interface to host the
% parameter; callers must treat that as "skip the control".
p = [];
vn = matlab.lang.makeValidName(name);
if isfield(P,vn)
    p = P.(vn);
else
    if isempty(RUNTIME) || isempty(RUNTIME.Interfaces), return; end
    sw = RUNTIME.Interfaces(arrayfun(@(x) isa(x,'hw.Software'),RUNTIME.Interfaces));
    if isempty(sw), return; end

    p = sw(1).add_parameter(name,defaultValue,Type='Boolean',Description=description);
    p.UpdateEveryTrial = false;
    % add_parameter seeds Values, not Value.
    p.Value = defaultValue;
end
p.PersistWithPhase = true;
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


function set_catch_trials_state(src,newValue,~,varargin)
% set_catch_trials_state(src,newValue,param,hPCatch...)
% Enable or disable the p(Catch) hazard fields to match the catch-trial
% checkbox, so the greyed fields never suggest a schedule that
% cl_AppetitiveStimDetect is no longer running.
%
% Parameters:
%   src : gui.Parameter_Control
%       Catch-trial checkbox that triggered the update.
%   newValue : logical scalar | struct
%       New CatchTrialsEnabled value, or the event struct carrying it.
%   varargin : gui.Parameter_Control
%       p(Catch) controls to enable or disable; [] entries (parameters the
%       loaded protocol does not define) are skipped.

if isempty(src), return; end

if isstruct(newValue)
    newValue = newValue.Value;
end

if logical(newValue)
    state = "on";
else
    state = "off";
end

for i = 1:numel(varargin)
    h = varargin{i};
    if isempty(h) || ~isvalid(h), continue; end

    % widgets() rather than h_uiobj: the Min/Max control owns two entry
    % fields and both have to grey out together.
    set(h.widgets(),'Enable',state);
    if ishandle(h.h_label)
        h.h_label.Enable = state;
    end
end
end


function set_stimdelay_training_state(obj,event,pStimDelay,pStepUp,pStepDown,hControls)
% set_stimdelay_training_state(obj,event,pStimDelay,pStepUp,pStepDown,hControls)
% Open or close stimulus-delay training mode, and grey the delay
% randomization controls for its duration.
%
% Training mode steps StimDelay itself, from its own window and its own
% NewData listener, and writes the result into the trials table. Nothing
% else may drive the parameter while it runs: gui.eval_staircase_training_mode
% suspends isRandom, and cl_AppetitiveStimDetect stands its block sequence
% down. The controls are greyed rather than hidden so the operator can still
% see the configuration that resumes when training is switched off.
%
% Parameters:
%   obj : cl_AppetitiveDetection_BehaviorGUI
%   event : struct
%       PostUpdateFcn event whose Value is the training on/off state.
%   pStimDelay : hw.Parameter
%       Parameter the training staircase steps.
%   pStepUp, pStepDown : hw.Parameter
%       Training step magnitudes.
%   hControls : cell of gui.Parameter_Control
%       Delay controls to grey while training runs. The first entry is the
%       randomization checkbox, which is also what restores the others when
%       training ends; [] entries are skipped.

gui.eval_staircase_training_mode(obj,[],event,pStimDelay, ...
    StepUp   = step_value(pStepUp), ...
    StepDown = step_value(pStepDown));

training = logical(event.Value);
if training
    state = "off";
else
    state = "on";
end

for i = 1:numel(hControls)
    h = hControls{i};
    if isempty(h) || ~isvalid(h), continue; end
    set(h.widgets(),'Enable',state);
    if ishandle(h.h_label)
        h.h_label.Enable = state;
    end
end

if training, return; end

% Enabling everything is only half a restore: which delay controls are
% usable depends on the randomization checkbox, not on training. Re-running
% its PostUpdateFcn re-applies that, rather than duplicating the rule here.
hRand = hControls{1};
if isempty(hRand) || ~isvalid(hRand) || ~isa(hRand.PostUpdateFcn,'function_handle')
    return
end
hRand.runPostUpdateFcn(struct('PreviousValue',[], ...
    'EventName','TrainingModeOff','Value',hRand.h_uiobj.Value));
end


function set_stimdelay_randomization_state(src,newValue,param,hStimDelayValue,varargin)
% set_stimdelay_randomization_state(src,newValue,param,hStimDelayValue,hVarying...)
% Keep the stimulus-delay randomization state and its controls synchronized:
% a varying delay is described by the controls in hVarying and the fixed
% Stimulus Delay field is read-only, or the reverse.
%
% Serves both randomization schemes. The controls that describe HOW the delay
% varies differ -- StimDelay's own Min/Max for the isRandom path, the list
% bounds, step and jitter for the block sequence -- so they arrive as a
% variable-length list rather than as one named argument.
%
% Parameters:
%   src : gui.Parameter_Control
%       Randomization checkbox that triggered the update.
%   newValue : logical scalar | struct
%       New checkbox value, or the event struct carrying it.
%   param : hw.Parameter
%       Bound parameter passed by gui.Parameter_Control PostUpdateFcn (unused).
%   hStimDelayValue : gui.Parameter_Control
%       UI control for direct StimDelay value editing.
%   varargin : gui.Parameter_Control
%       Controls describing the varying delay; [] entries (parameters the
%       loaded protocol does not define) are skipped.

if isempty(src) || isempty(hStimDelayValue)
    return
end

if isstruct(newValue)
    newValue = newValue.Value;
end

isRandom = logical(newValue);

if isRandom
    editState = "off";
    varyingState = "on";
    valueFieldColor = [0.94 0.94 0.94];
else
    % Allow direct fixed-value editing when randomization is disabled.
    editState = "on";
    varyingState = "off";
    valueFieldColor = hStimDelayValue.colorNormal;
end

hStimDelayValue.h_uiobj.Editable = editState;
hStimDelayValue.h_uiobj.BackgroundColor = valueFieldColor;

for i = 1:numel(varargin)
    h = varargin{i};
    if isempty(h) || ~isvalid(h), continue; end

    % widgets() rather than h_uiobj: both entries of a Min/Max row follow the
    % randomization state together.
    set(h.widgets(),'Enable',varyingState);
    if ishandle(h.h_label)
        h.h_label.Enable = varyingState;
    end
end
end
