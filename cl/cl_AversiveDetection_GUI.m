classdef cl_AversiveDetection_GUI < handle

    properties (SetAccess = protected)
        psychDetect % psychophysics.Detect

        PsychPlot % gui.PsychPlot

        plottedParameters = {'~InTrial_TTL','~RespWindow','~Spout_TTL',...
            '~ShockOn','~GO_Stim','~NOGO_Stim'}


    end
    
    properties (SetAccess = private)
        RUNTIME
    end

    properties (Hidden)
        guiHandles
    end



    methods
        % constructor
        function obj = cl_AversiveDetection_GUI(RUNTIME)


            obj.RUNTIME = RUNTIME;

            % only permit one instance to run
            f = findall(groot,'Type','figure');
            f = f(startsWith({f.Tag},'cl_AversiveDetection'));
            if ~isempty(f), delete(f); end


            % create detection object
            obj.psychDetect = psychophysics.Detection(RUNTIME,1,'AMdepth');

            % generate gui layout and components
            obj.create_gui;


            if nargout == 0, clear obj; end

        end




        function update_trial_filter(obj,src,event)

            amdepth = [src.Data{:,1}];
            present = [src.Data{:,3}];
            
            if ~present(amdepth==0)
                src.Data{amdepth==0,3} = true;
                present(amdepth==0) = true; % always
            end

            obj.RUNTIME.TRIALS.activeTrials = present;

            if any(~present)
                vprintf(2,'Inactive AMdepths: %s',mat2str(amdepth(~present)));
            end
            vprintf(2,'Active AMdepths: %s',mat2str(amdepth(present)));
        end




        function create_gui(obj)


            R = obj.RUNTIME;


            % Create the main figure
            fig = uifigure(Tag = 'cl_AversiveDetection_GUI', ...
                Name = 'Caras Lab Aversive Detection GUI');
            fig.Position = [100 100 1600 1000];  % Set figure size

            % Create a grid layout
            layoutMain = uigridlayout(fig, [11, 7]);
            layoutMain.RowHeight = {60, 40, 90, 110, 60, 130, 40, 100,50,170,'1x'};
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

            
            bcmNormal = jet(5);
            bcmActive = min(bcmNormal+.4,1);

            % > Remind
            p = R.S.Module.add_parameter('ReminderTrials',0);
            h = gui.Parameter_Control(buttonLayout,p,Type='toggle',autoCommit=true);
            h.Text = "Remind";
            h.colorNormal = bcmNormal(1,:);
            h.colorOnUpdate = bcmActive(1,:);
            
            % > ReferencePhys
            p = R.S.Module.add_parameter('ReferencePhys',0);
            h = gui.Parameter_Control(buttonLayout,p,Type='toggle',autoCommit=true);
            h.Text = "ReferencePhys";
            h.colorNormal = bcmNormal(2,:);
            h.colorOnUpdate = bcmActive(2,:);


            % > Deliver Trials
            p = R.S.Module.add_parameter('DeliverTrials',0);
            h = gui.Parameter_Control(buttonLayout,p,Type='toggle',autoCommit=true);
            h.Text = "Deliver Trials";
            h.colorNormal = bcmNormal(3,:);
            h.colorOnUpdate = bcmActive(3,:);

            % > Pause Trials
            p = R.S.Module.add_parameter('PauseTrials',0);
            h = gui.Parameter_Control(buttonLayout,p,Type='toggle',autoCommit=true);
            h.Text = "Pause Trials";
            h.colorNormal = bcmNormal(4,:);
            h.colorOnUpdate = bcmActive(4,:);

            % > Air Puff
            p = R.S.Module.add_parameter('AirPuff',0);
            h = gui.Parameter_Control(buttonLayout,p,Type='toggle',autoCommit=true);
            h.Text = "Air Puff";
            h.colorNormal = bcmNormal(5,:);
            h.colorOnUpdate = bcmActive(5,:);


            bh = findobj(fig,'Type', 'uistatebutton');
            set(bh, ...
                FontWeight = 'bold', ...
                FontSize = 13, ...
                Enable = "on");











            % PARAMETERS ----------------------------------------------------
            % Panel for "Reminder Trial"
            panelReminderTrial = uipanel(layoutMain, 'Title', 'Reminder Trial');
            panelReminderTrial.Layout.Row = [2 3];
            panelReminderTrial.Layout.Column = [1 2];

            % > ReminderTrial
            layoutReminderTrial = simple_layout(panelReminderTrial);

            % > Reminder Trial Table
            tableReminderTrial = uitable(layoutReminderTrial);
            tableReminderTrial.ColumnName = {'AMdepth','TrialType'};
            tableReminderTrial.ColumnEditable = false;
            tableReminderTrial.FontSize = 8;


            % TRIAL CONTROLS -------------------------------------------------
            % Panel for "Trial Controls"
            panelTrialControls = uipanel(layoutMain, 'Title', 'Trial Controls');
            panelTrialControls.Layout.Row = [4 5];
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
            panelSoundControls.Layout.Row = [6 7];
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
            p = R.S.Module.add_parameter('ConsecutiveNOGO_min',3);
            h = gui.Parameter_Control(layoutTrialControls,p,Type='dropdown');%,autoCommit=true);
            h.Evaluator = @evaluate_n_gonogo;
            h.Values = 0:5;
            h.Value = 3;
            h.Text = "Consecutive NoGo (min):";

            % >> Consecutive NOGO max
            p = R.S.Module.add_parameter('ConsecutiveNOGO_max',5);
            h = gui.Parameter_Control(layoutTrialControls,p,Type='dropdown');%,autoCommit=true);
            h.Evaluator = @evaluate_n_gonogo;
            h.Values = 3:20;
            h.Value = 5;
            h.Text = "Consecutive NoGo (max):";


            % >> Trial order
            p = R.S.Module.add_parameter('Trial_Order','Descending');
            h = gui.Parameter_Control(layoutTrialControls,p,Type='dropdown',autoCommit=true);
            h.Values = ["Descending","Ascending","Random"];
            h.Value = "Descending";
            h.Text = "Trial Order:";



            % >> Intertrial Interval
            p = R.HW.find_parameter('ITI_dur');
            h = gui.Parameter_Control(layoutTrialControls,p,Type='dropdown');
            h.Values= 250:100:2500;
            h.Text = "Intertrial Interval (ms):";


            % >> Response Window Duration
            p = R.HW.find_parameter('RespWinDur');
            h = gui.Parameter_Control(layoutTrialControls,p,Type='dropdown');
            h.Values = 200:100:1000;
            h.Text = "Response Window Duration (ms):";


            % >> Optogenetic trigger
            p = R.HW.find_parameter('Optostim');
            h = gui.Parameter_Control(layoutTrialControls,p,Type='dropdown');
            h.Values = [0 1];
            h.Value = 0;
            h.Text = "Optogenetic Trigger:";










            % SOUND CONTROLS -----------------------------------------------------

            % >> dB SPL
            p = R.HW.find_parameter('dBSPL');
            h = gui.Parameter_Control(layoutSoundControls,p,Type='dropdown');
            h.Values = 0:5:85;
            h.Value = 65;
            h.Text = "Sound Level (dB SPL):";


            % >> Duration
            p = R.HW.find_parameter('Stim_Duration');
            h = gui.Parameter_Control(layoutSoundControls,p,Type='dropdown');
            h.Values = 250:250:2000;
            h.Value = 1000;
            h.Text = "Stimulus Duration (ms):";


            % >> AM Rate
            p = R.HW.find_parameter('AMrate');
            h = gui.Parameter_Control(layoutSoundControls,p,Type='dropdown');
            h.Values = 1:20;
            h.Value = 5;
            h.Text = "AM Rate (Hz):";


            % % >> AM Depth
            % p = R.HW.find_parameter('AMdepth');
            % h = gui.Parameter_Control(layoutSoundControls,p,Type='dropdown');
            % h.Values = 0:.01:1;
            % h.Value = p.Value;
            % h.Text = "AM Depth (%):";



            % >> Highpass cutoff
            p = R.HW.find_parameter('Highpass');
            h = gui.Parameter_Control(layoutSoundControls,p,Type='dropdown');
            h.Values = 25:25:300;
            h.Value = p.Value;
            h.Text = "Highpass cutoff (Hz):";


            % >> Lowpass cutoff
            p = R.HW.find_parameter('Lowpass');
            h = gui.Parameter_Control(layoutSoundControls,p,Type='dropdown');
            h.Values =  1000:500:25000;
            h.Value = p.Value;
            h.Text = "Lowpass cutoff (Hz):";





            % Panel for "Shock Controls" ----------------------------------------
            panelShockControls = uipanel(layoutMain, 'Title', 'Shock Controls');
            panelShockControls.Layout.Row = 8;
            panelShockControls.Layout.Column = [1 2];

            % > Shock Controls
            layoutShockControls = uigridlayout(panelShockControls);
            layoutShockControls.ColumnWidth = {'1x'};
            layoutShockControls.RowHeight = {25,25,25};
            layoutShockControls.RowSpacing = 1;
            layoutShockControls.ColumnSpacing = 5;
            layoutShockControls.Padding = [0 0 0 0];

            % >> AutoShock ** WHAT IS AUTOSHOCK? ** 
            % p = R.HW.find_parameter('ShockFlag');
            % h = gui.Parameter_Control(layoutShockControls,p,Type="checkbox",autoCommit=true);
            % h.Value = true;

            % >> Shocker status
            p = R.HW.find_parameter('~ShockOn',includeInvisible=true);
            h = gui.Parameter_Control(layoutShockControls,p,type='readonly');
            h.Text = 'Shock State';

            % >> Shocker flag
            p = R.HW.find_parameter('ShockFlag');
            h = gui.Parameter_Control(layoutShockControls,p,Type="checkbox",autoCommit=true);
            h.Value = true;
            h.Text = 'Shock Enabled';

            % >> Shock duration dropdown 
            p = R.HW.find_parameter('ShockDur');
            h = gui.Parameter_Control(layoutShockControls,p,Type='dropdown');
            h.Values = 200:100:1200;
            h.Value = p.Value;
            h.Text = "Shock duration (ms):";








            % Panel for "Pump Controls" ------------------------------------------
            panelPumpControls = uipanel(layoutMain, 'Title', 'Pump Controls');
            panelPumpControls.Layout.Row = 9;
            panelPumpControls.Layout.Column = [1 2];


            p = R.S.Module.add_parameter('PumpRate',0.3);
            p.Unit = 'mL/min';
            h = gui.Parameter_Control(panelPumpControls,p,Type='dropdown',autoCommit=true);
            h.Values = (1:20)/10;
            h.Value = 0.3;
            h.Text = "Pump Rate (mL/min)";


    





            % Commit button ---------------------------------------------
            h = gui.Parameter_Update(layoutMain);
            h.Button.Layout.Row = [9 10];
            h.Button.Layout.Column = [3 4];
            h.Button.Text = ["Update" "Parameters"];
            h.Button.FontSize = 24;
            
            % find all 'Paramete_Control' objects
            hp = findall(fig,'-regexp','tag','^PC_'); 
            h.watchedHandles = [hp.UserData];











            % Panel for "Trial Filter" ------------------------------------------
            panelTrialFilter = uipanel(layoutMain, 'Title', 'Trial Filter');
            panelTrialFilter.Layout.Row = [10 11];
            panelTrialFilter.Layout.Column = [1 2];
            panelTrialFilter.Scrollable = 'on';

            % > Trial Filter
            layoutTrialFilter = simple_layout(panelTrialFilter);


            % > Trial Filter Table
            wp = R.TRIALS.writeparams;
            tt = R.TRIALS.trials;
            d = tt(:,ismember(wp,'AMdepth'));
            d(:,2) = tt(:,ismember(wp,'TrialType'));
            d(:,3) = {true};
            tableTrialFilter = uitable(layoutTrialFilter);
            tableTrialFilter.Tag = 'tblTrialFilter';
            tableTrialFilter.ColumnName = {'AMdepth','TrialType','Present'};
            tableTrialFilter.ColumnEditable = [false,false,true];
            tableTrialFilter.FontSize = 10;
            tableTrialFilter.Data = d;
            tableTrialFilter.CellEditCallback = @obj.update_trial_filter;




            % Panel for "Total Water" ----------------------------------------
            panelTotalWater = uipanel(layoutMain, 'Title', 'Total Water (mL)');
            panelTotalWater.Layout.Row = 1;
            panelTotalWater.Layout.Column = 6;


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
                h.create_gui(panelTotalWater);
                setpref('PumpCom','port',port);
            catch me
                lblTotalWater = uilabel(panelTotalWater);
                lblTotalWater.Text = "*CAN'T CONNECT PUMP*";
                lblTotalWater.FontColor = 'r';
                lblTotalWater.FontWeight = 'bold';
                vprintf(0,1,'Couldn''t connect to Pump. Check that the com port is correct')
            end



            % Panel for "Next Trial" ----------------------------------------
            panelNextTrial = uipanel(layoutMain, 'Title', 'Next Trial');
            panelNextTrial.Layout.Row = [1 2];
            panelNextTrial.Layout.Column = 7;

            layoutNextTrial = simple_layout(panelNextTrial);

            % > Next Trial Table
            % *** NEED TO SEE HOW THIS IMPLEMENTED ON THE CURRENT GUI ***
            tableNextTrial = uitable(layoutNextTrial);
            tableNextTrial.ColumnName = {'AMdepth','TrialType'};
            tableNextTrial.ColumnEditable = false;
            tableNextTrial.FontSize = 8;





            % Axes for Main Plot ------------------------------------------------
            axPsych = uiaxes(layoutMain);
            axPsych.Layout.Row = [4 8];
            axPsych.Layout.Column = [3, 5];

            obj.PsychPlot = gui.PsychPlot(obj.psychDetect,R.HELPER,axPsych);

            % ** I THINK THESE ARE HANDLED BY THE PSYCHPLOT OBJECT **
            % xlabel(axPsych,'AM depth')
            % ylabel(axPsych,'Hit Rate')
            % 
            % grid(axPsych,'on')
            % box(axPsych,'on')

            % % Panel for "Plotting Variables" ----------------------------------
            % panelPlottingVariables = uipanel(layoutMain, 'Title', 'Plotting Variables');
            % panelPlottingVariables.Layout.Row = [3 4];
            % panelPlottingVariables.Layout.Column = 6;
            % 
            % % > Plotting Variables
            % layoutPlottingVariables = uigridlayout(panelPlottingVariables);
            % layoutPlottingVariables.ColumnWidth = {100,100};
            % layoutPlottingVariables.RowHeight = repmat({25},1,4);
            % layoutPlottingVariables.ColumnSpacing = 5;
            % layoutPlottingVariables.RowSpacing = 1;
            % layoutPlottingVariables.Padding = [0 0 0 0];
            % 
            % % >> Y
            % lblY = uilabel(layoutPlottingVariables);
            % lblY.Layout.Row = 1;
            % lblY.Layout.Column = 1;
            % lblY.Text = "Y:";
            % lblY.HorizontalAlignment = "right";
            % 
            % % >> Y dropdown
            % ddY = uidropdown(layoutPlottingVariables);
            % ddY.Layout.Row = 1;
            % ddY.Layout.Column = 2;
            % ddY.Tag = 'ddY';
            % ddY.Items = {'Hit Rate','d-prime'};
            % ddY.Value = 'Hit Rate';
            % 
            % % >> X
            % lblX = uilabel(layoutPlottingVariables);
            % lblX.Layout.Row = 2;
            % lblX.Layout.Column = 1;
            % lblX.Text = "X:";
            % lblX.HorizontalAlignment = "right";
            % 
            % % >> X dropdown
            % ddX = uidropdown(layoutPlottingVariables);
            % ddX.Layout.Row = 2;
            % ddX.Layout.Column = 2;
            % ddX.Tag = 'ddX';
            % ddX.Items = {'AMdepth'};
            % ddX.Value = 'AMdepth';
            % 
            % % >> Grouping variable
            % lblGroupingVariable = uilabel(layoutPlottingVariables);
            % lblGroupingVariable.Layout.Row = 3;
            % lblGroupingVariable.Layout.Column = 1;
            % lblGroupingVariable.Text = "Grouping variable:";
            % lblGroupingVariable.HorizontalAlignment = "right";
            % 
            % % >> Grouping variable dropdown
            % ddGroupingVariable = uidropdown(layoutPlottingVariables);
            % ddGroupingVariable.Layout.Row = 3;
            % ddGroupingVariable.Layout.Column = 2;
            % ddGroupingVariable.Tag = 'ddGroupingVariable';
            % ddGroupingVariable.Items = {'None'};
            % ddGroupingVariable.Value = 'None';

            % % >> Include reminders ???
            % chkIncludeReminders = uicheckbox(layoutPlottingVariables);
            % chkIncludeReminders.Layout.Row = 4;
            % chkIncludeReminders.Layout.Column = [1 2];
            % chkIncludeReminders.Text = "Include reminders";
            % chkIncludeReminders.Value = false;
            % % chkIncludeReminders.ValueChangedFcn =






            
            % Axes for Microphone Display -------------------------------
            axesMicrophone = uiaxes(layoutMain);
            axesMicrophone.Layout.Row = [9 11];
            axesMicrophone.Layout.Column = 5;
            axis(axesMicrophone,'image');
            box(axesMicrophone,'on')
            
            gui.MicrophonePlot(p,axesMicrophone);
            axesMicrophone.YAxis.Label.String = "RMS voltage";


            % Panel for "FA Rate" --------------------------------------------
            % TO DO: UPDATE TO NEW HW.PARAMETER OBJECT
            panelFARate = uipanel(layoutMain, 'Title', 'FA Rate');
            panelFARate.Layout.Row = 3;
            panelFARate.Layout.Column = 5;

            layoutFARate = simple_layout(panelFARate);

            % > FA Rate
            lblFARate = uilabel(layoutFARate);
            lblFARate.Tag = 'lblFARate';
            lblFARate.Text = "0";
            lblFARate.FontColor = 'r';
            lblFARate.FontSize = 40;
            lblFARate.FontWeight = 'bold';
            lblFARate.HorizontalAlignment = "center";



            % Panel for "Response History" --------------------------------------
            panelResponseHistory = uipanel(layoutMain, 'Title', 'Response History');
            panelResponseHistory.Layout.Row = [3, 6];
            panelResponseHistory.Layout.Column = [6 7];

            % > Response History Table
            gui.History(obj.psychDetect,R.HELPER,panelResponseHistory);


            % Panel for "Trial History" ----------------------------------------
            panelTrialHistory = uipanel(layoutMain, 'Title', 'Trial History');
            panelTrialHistory.Layout.Row = [7 11];
            panelTrialHistory.Layout.Column = [6 7];


            % > Trial History
            layoutTrialHistory = simple_layout(panelTrialHistory);

            % > Trial History Table
            tableResponseHistory = uitable(layoutTrialHistory);
            tableResponseHistory.ColumnName = {'AMdepth','TrialType','# Trials','Hit rate (%)','dprime'};
            tableResponseHistory.ColumnEditable = false;
            tableResponseHistory.FontSize = 10;




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






            % Create separate legacy figure for online plotting because
            % it's much faster than uifigure
            % Axes for Behavior Plot --------------------------------------------
            figOnlinePlot = figure(Name = 'Online Plot', ...
                Tag = 'cl_AversiveDetection_OnlinePlot');
            p = fig.Position;
            figOnlinePlot.Position(1) = p(1);
            figOnlinePlot.Position(2) = p(2) + p(4) + 30;
            figOnlinePlot.Position(3) = p(3);
            figOnlinePlot.Position(4) = 200;
            figOnlinePlot.ToolBar = "none";
            figOnlinePlot.MenuBar = "none";
            figOnlinePlot.NumberTitle = "off";
            axesBehavior = axes(figOnlinePlot);
            gui.OnlinePlot(R,obj.plottedParameters,axesBehavior,1);



        end



        
    end

end



function [value,success] = evaluate_n_gonogo(obj,event)
% [value,success] = evaluate_n_gonogo(obj,event)
%
% implements the 'Evaluator' function
success = true;

value = event.Value; % new value

% first find all gui objects we want to evaluate
h = ancestor(obj.parent,'figure','toplevel');
h = findall(h,'-property','tag');
if isempty(h), return; end


isMin = endsWith(obj.Name,'_min');

if isMin
    i = endsWith(get(h,'Tag'),'ConsecutiveNOGO_max');
else
    i = endsWith(get(h,'Tag'),'ConsecutiveNOGO_min');
end
h = h(i);

if isempty(h), return; end % can happen during setup

% the handle to the Parameter object is included in the gui object's
% UserData

if isMin
    success = h.Value >= value;
else
    success = h.Value <= value;
end


if ~success
    value = event.PreviousValue; % return to previous value
    vprintf(0,1,'Max NoGo trials can''t be lower than Min NoGo trials')
end
end


% used by create_gui
function h = simple_layout(p)
h = uigridlayout(p);
h.ColumnWidth = {'1x'};
h.RowHeight = {'1x'};
h.Padding = [0 0 0 0];
end