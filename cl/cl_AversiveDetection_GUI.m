classdef cl_AversiveDetection_GUI < handle

    properties
        psychDetect
        watchedParameters = {'~InTrial_TTL','~RespWindow','~Spout_TTL',...
            '~ShockOn','~GO_Stim','~NOGO_Stim'}
    end

    properties (SetAccess = immutable)
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
            f = findall(0,'Type','figure','Tag','cl_AversiveDetection_GUI');
            if ~isempty(f), delete(f); end
            % obj.psychDetect = psychophysics.Detection;

            obj.create_gui;


            if nargout == 0, clear obj; end
            
        end




        function create_gui(obj)


            % Create the main figure
            fig = uifigure(Tag = 'cl_AversiveDetection_GUI', ...
                Name = 'Caras Lab Aversive Detection GUI');
            fig.Position = [100 100 1600 1000];  % Set figure size

            % Create a grid layout
            mainLayout = uigridlayout(fig, [11, 9]);
            mainLayout.RowHeight = {60, 40, 90, 110, 60, 160, 90, 80,50,60,'1x'};
            mainLayout.ColumnWidth = {150, 150, 100, '1x', '1x','1x', '1x', 200,100};
            mainLayout.Padding = [1 1 1 1];


            % CONTROL BUTTONS ---------------------------------------
            % Grid layout for buttons
            buttonLayout = uigridlayout(mainLayout,[2 3]);
            buttonLayout.Layout.Row = [1 2];
            buttonLayout.Layout.Column = [1 2];
            buttonLayout.Padding = [0 0 0 0];
            buttonLayout.ColumnWidth = {'1x','1x','1x'};
            buttonLayout.RowHeight = {'1x','1x'};
            buttonLayout.RowSpacing = 0;
            buttonLayout.ColumnSpacing = 0;

            % > Apply Changes
            buttonApplyChanges = uibutton(buttonLayout);
            buttonApplyChanges.Layout.Row = 1;
            buttonApplyChanges.Layout.Column = 1;
            buttonApplyChanges.Text = "Apply Changes";
            buttonApplyChanges.Tag = "btnApplyChanges";
            buttonApplyChanges.BackgroundColor = 'y';

            % > Remind
            buttonRemind = uibutton(buttonLayout);
            buttonRemind.Layout.Row = 1;
            buttonRemind.Layout.Column = 2;
            buttonRemind.Text = "Remind";
            buttonRemind.Tag = "btnRemind";
            buttonRemind.BackgroundColor = 'g';

            % > ReferencePhys
            buttonReferencePhys = uibutton(buttonLayout);
            buttonReferencePhys.Layout.Row = 1;
            buttonReferencePhys.Layout.Column = 3;
            buttonReferencePhys.Text = "ReferencePhys";
            buttonReferencePhys.Tag = "btnReferencePhys";

            % > Deliver Trials
            buttonDeliverTrials = uibutton(buttonLayout);
            buttonDeliverTrials.Layout.Row = 2;
            buttonDeliverTrials.Layout.Column = 1;
            buttonDeliverTrials.Text = "Deliver Trials";
            buttonDeliverTrials.Tag = "btnDeliverTrials";
            buttonDeliverTrials.BackgroundColor = 'c';

            % > Pause Trials
            buttonPauseTrials = uibutton(buttonLayout);
            buttonPauseTrials.Layout.Row = 2;
            buttonPauseTrials.Layout.Column = 2;
            buttonPauseTrials.Text = "Pause Trials";
            buttonPauseTrials.Tag = "btnPauseTrials";
            buttonPauseTrials.BackgroundColor = "#b3c7ff";

            % > Air Puff
            buttonAirPuff = uibutton(buttonLayout);
            buttonAirPuff.Layout.Row = 2;
            buttonAirPuff.Layout.Column = 3;
            buttonAirPuff.Text = "Air Puff";
            buttonAirPuff.Tag = "btnAirPuff";
            buttonAirPuff.BackgroundColor = "#ffb164";

            bh = findobj(fig,'Type', 'uibutton', '-regexp', 'Tag', '^btn');
            set(bh, ...
                FontWeight = 'bold', ...
                FontSize = 13, ...
                Enable = "off", ...
                CreateFcn = @cl_gui_button_create, ... % cl_gui_button_create not yet created
                ButtonPushedFcn = @cl_gui_button_callback); % cl_gui_button_callback not yet created


            % PARAMETERS ----------------------------------------------------
            % Panel for "Reminder Trial"
            panelReminderTrial = uipanel(mainLayout, 'Title', 'Reminder Trial');
            panelReminderTrial.Layout.Row = 3;
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
            panelTrialControls = uipanel(mainLayout, 'Title', 'Trial Controls');
            panelTrialControls.Layout.Row = [4 5];
            panelTrialControls.Layout.Column = [1 2];

            % > Trial Controls
            layoutTrialControls = uigridlayout(panelTrialControls);
            layoutTrialControls.ColumnWidth = {'1x',100};
            layoutTrialControls.RowHeight = repmat({25},1,6);
            layoutTrialControls.RowSpacing = 1;
            layoutTrialControls.ColumnSpacing = 5;
            layoutTrialControls.Padding = [0 0 0 0];
            layoutTrialControls.Scrollable = "on";

            % >> Consecutive NOGO min
            lblConsecutiveNOGOmin = uilabel(layoutTrialControls);
            lblConsecutiveNOGOmin.Layout.Row = 1;
            lblConsecutiveNOGOmin.Layout.Column = 1;
            lblConsecutiveNOGOmin.Text = "Consecutive NOGO (min):";
            lblConsecutiveNOGOmin.HorizontalAlignment = "right";

            % >> Consecutive NOGO min dropdown
            ddConsecutiveNOGOmin = uidropdown(layoutTrialControls);
            ddConsecutiveNOGOmin.Layout.Row = 1;
            ddConsecutiveNOGOmin.Layout.Column = 2;
            ddConsecutiveNOGOmin.Tag = 'ddConsecutiveNOGOmin';
            ddConsecutiveNOGOmin.Items = arrayfun(@num2str,0:10,'uni',0);
            ddConsecutiveNOGOmin.Value = '3';


            % >> Consecutive NOGO max
            lblConsecutiveNOGOmax = uilabel(layoutTrialControls);
            lblConsecutiveNOGOmax.Layout.Row = 2;
            lblConsecutiveNOGOmax.Layout.Column = 1;
            lblConsecutiveNOGOmax.Text = "Consecutive NOGO (max):";
            lblConsecutiveNOGOmax.HorizontalAlignment = "right";

            % >> Consecutive NOGO max dropdown
            ddConsecutiveNOGOmax = uidropdown(layoutTrialControls);
            ddConsecutiveNOGOmax.Layout.Row = 2;
            ddConsecutiveNOGOmax.Layout.Column = 2;
            ddConsecutiveNOGOmax.Tag = 'ddConsecutiveNOGOmax';
            ddConsecutiveNOGOmax.Items = arrayfun(@num2str,1:20,'uni',0);
            ddConsecutiveNOGOmax.Value = '5';


            % >> Intertrial Interval
            lblIntertrialInterval = uilabel(layoutTrialControls);
            lblIntertrialInterval.Layout.Row = 3;
            lblIntertrialInterval.Layout.Column = 1;
            lblIntertrialInterval.Text = "Intertrial Interval (s):";
            lblIntertrialInterval.HorizontalAlignment = "right";

            % >> Intertrial Interval dropdown
            ddIntertrialInterval = uidropdown(layoutTrialControls);
            ddIntertrialInterval.Layout.Row = 3;
            ddIntertrialInterval.Layout.Column = 2;
            ddIntertrialInterval.Tag = 'ddIntertrialInterval';
            ddIntertrialInterval.Items = arrayfun(@num2str,0.05:0.05:1,'uni',0);
            ddIntertrialInterval.Value = '0.1';

            % >> Response Window Duration
            lblResponseWindowDuration = uilabel(layoutTrialControls);
            lblResponseWindowDuration.Layout.Row = 4;
            lblResponseWindowDuration.Layout.Column = 1;
            lblResponseWindowDuration.Text = "Response Window Duration (s):";
            lblResponseWindowDuration.HorizontalAlignment = "right";

            % >> Response Window Duration dropdown
            ddResponseWindowDuration = uidropdown(layoutTrialControls);
            ddResponseWindowDuration.Layout.Row = 4;
            ddResponseWindowDuration.Layout.Column = 2;
            ddResponseWindowDuration.Tag = 'ddResponseWindowDuration';
            ddResponseWindowDuration.Items = arrayfun(@num2str,0.05:0.05:1,'uni',0);
            ddResponseWindowDuration.Value = '0.1';


            % >> Optogenetic trigger
            lblOptogeneticTrigger = uilabel(layoutTrialControls);
            lblOptogeneticTrigger.Layout.Row = 5;
            lblOptogeneticTrigger.Layout.Column = 1;
            lblOptogeneticTrigger.Text = "Optogenetic Trigger:";
            lblOptogeneticTrigger.HorizontalAlignment = "right";

            % >> Optogenetic trigger dropdown
            ddOptogeneticTrigger = uidropdown(layoutTrialControls);
            ddOptogeneticTrigger.Layout.Row = 5;
            ddOptogeneticTrigger.Layout.Column = 2;
            ddOptogeneticTrigger.Tag = 'ddOptogeneticTrigger';
            ddOptogeneticTrigger.Items = {'Off','On'};
            ddOptogeneticTrigger.Value = 'Off';


            % >> Trial order
            lblTrialOrder = uilabel(layoutTrialControls);
            lblTrialOrder.Layout.Row = 6;
            lblTrialOrder.Layout.Column = 1;
            lblTrialOrder.Text = "Trial order:";
            lblTrialOrder.HorizontalAlignment = "right";

            % >> Trial order dropdown
            ddTrialOrder = uidropdown(layoutTrialControls);
            ddTrialOrder.Layout.Row = 6;
            ddTrialOrder.Layout.Column = 2;
            ddTrialOrder.Tag = 'ddTrialOrder';
            ddTrialOrder.Items = {'Descending','Ascending','Random'};
            ddTrialOrder.Value = 'Descending';


            % SOUND CONTROLS -----------------------------------------------------
            % Panel for "Sound Controls"
            panelSoundControls = uipanel(mainLayout, 'Title', 'Sound Controls');
            panelSoundControls.Layout.Row = [6 7];
            panelSoundControls.Layout.Column = [1 2];

            % > Sound Controls
            layoutSoundControls = uigridlayout(panelSoundControls);
            layoutSoundControls.ColumnWidth = {'1x',100};
            layoutSoundControls.RowHeight = repmat({25},1,9);
            layoutSoundControls.RowSpacing = 1;
            layoutSoundControls.ColumnSpacing = 5;
            layoutSoundControls.Padding = [0 0 0 0];
            layoutSoundControls.Scrollable = "on";

            % >> Frequency
            lblFrequency = uilabel(layoutSoundControls);
            lblFrequency.Layout.Row = 1;
            lblFrequency.Layout.Column = 1;
            lblFrequency.Text = "Frequency (Hz):";
            lblFrequency.HorizontalAlignment = "right";

            % >> Frequency dropdown
            ddFrequency = uidropdown(layoutSoundControls);
            ddFrequency.Layout.Row = 1;
            ddFrequency.Layout.Column = 2;
            ddFrequency.Tag = 'ddFrequency';
            ddFrequency.Items = {'500','1000','2000','4000'};
            ddFrequency.Value = '1000';


            % >> dB SPL
            lbldBSPL = uilabel(layoutSoundControls);
            lbldBSPL.Layout.Row = 2;
            lbldBSPL.Layout.Column = 1;
            lbldBSPL.Text = "dB SPL:";
            lbldBSPL.HorizontalAlignment = "right";

            % >> dB SPL dropdown
            dddBSPL = uidropdown(layoutSoundControls);
            dddBSPL.Layout.Row = 2;
            dddBSPL.Layout.Column = 2;
            dddBSPL.Tag = 'dddBSPL';
            dddBSPL.Items = arrayfun(@num2str,0:5:85,'uni',0);
            dddBSPL.Value = '60';


            % >> Duration
            lblDuration = uilabel(layoutSoundControls);
            lblDuration.Layout.Row = 3;
            lblDuration.Layout.Column = 1;
            lblDuration.Text = "Duration (s):";
            lblDuration.HorizontalAlignment = "right";

            % >> Duration dropdown
            ddDuration = uidropdown(layoutSoundControls);
            ddDuration.Layout.Row = 3;
            ddDuration.Layout.Column = 2;
            ddDuration.Tag = 'ddDuration';
            ddDuration.Items = arrayfun(@num2str,0.25:0.25:2,'uni',0);
            ddDuration.Value = '1';



            % >> AM Rate
            lblAMRate = uilabel(layoutSoundControls);
            lblAMRate.Layout.Row = 4;
            lblAMRate.Layout.Column = 1;
            lblAMRate.Text = "AM Rate (Hz):";
            lblAMRate.HorizontalAlignment = "right";

            % >> AM Rate dropdown
            ddAMRate = uidropdown(layoutSoundControls);
            ddAMRate.Layout.Row = 4;
            ddAMRate.Layout.Column = 2;
            ddAMRate.Tag = 'ddAMRate';
            ddAMRate.Items = arrayfun(@num2str,1:20,'uni',0);
            ddAMRate.Value = '5';


            % >> AM Depth
            lblAMDepth = uilabel(layoutSoundControls);
            lblAMDepth.Layout.Row = 5;
            lblAMDepth.Layout.Column = 1;
            lblAMDepth.Text = "AM Depth (%):";
            lblAMDepth.HorizontalAlignment = "right";

            % >> AM Depth dropdown
            ddAMRate = uidropdown(layoutSoundControls);
            ddAMRate.Layout.Row = 5;
            ddAMRate.Layout.Column = 2;
            ddAMRate.Tag = 'ddAMDepth';
            ddAMRate.Items = arrayfun(@num2str,0:10:100,'uni',0);
            ddAMRate.Value = '100';


            % >> FM Rate
            lblFMRate = uilabel(layoutSoundControls);
            lblFMRate.Layout.Row = 6;
            lblFMRate.Layout.Column = 1;
            lblFMRate.Text = "FM Rate (Hz):";
            lblFMRate.HorizontalAlignment = "right";

            % >> FM Rate dropdown
            ddFMRate = uidropdown(layoutSoundControls);
            ddFMRate.Layout.Row = 6;
            ddFMRate.Layout.Column = 2;
            ddFMRate.Tag = 'ddFMRate';
            ddFMRate.Items = arrayfun(@num2str,1:20,'uni',0);
            ddFMRate.Value = '4';


            % >> FM Depth
            lblFMDepth = uilabel(layoutSoundControls);
            lblFMDepth.Layout.Row = 7;
            lblFMDepth.Layout.Column = 1;
            lblFMDepth.Text = "FM Depth (%):";
            lblFMDepth.HorizontalAlignment = "right";

            % >> FM Depth dropdown
            ddFMRate = uidropdown(layoutSoundControls);
            ddFMRate.Layout.Row = 7;
            ddFMRate.Layout.Column = 2;
            ddFMRate.Tag = 'ddFMDepth';
            ddFMRate.Items = arrayfun(@num2str,0:10:100,'uni',0);
            ddFMRate.Value = '100';



            % >> Highpass cutoff
            lblHighpassCutoff = uilabel(layoutSoundControls);
            lblHighpassCutoff.Layout.Row = 8;
            lblHighpassCutoff.Layout.Column = 1;
            lblHighpassCutoff.Text = "Highpass cutoff (Hz):";
            lblHighpassCutoff.HorizontalAlignment = "right";

            % >> Highpass cutoff dropdown
            ddHighpassCutoff = uidropdown(layoutSoundControls);
            ddHighpassCutoff.Layout.Row = 8;
            ddHighpassCutoff.Layout.Column = 2;
            ddHighpassCutoff.Tag = 'ddHighpassCutoff';
            ddHighpassCutoff.Items = arrayfun(@num2str,25:25:300,'uni',0);
            ddHighpassCutoff.Value = '100';


            % >> Lowpass cutoff
            lblLowpassCutoff = uilabel(layoutSoundControls);
            lblLowpassCutoff.Layout.Row = 9;
            lblLowpassCutoff.Layout.Column = 1;
            lblLowpassCutoff.Text = "Lowpass cutoff (kHz):";
            lblLowpassCutoff.HorizontalAlignment = "right";

            % >> Lowpass cutoff dropdown
            ddLowpassCutoff = uidropdown(layoutSoundControls);
            ddLowpassCutoff.Layout.Row = 9;
            ddLowpassCutoff.Layout.Column = 2;
            ddLowpassCutoff.Tag = 'ddLowpassCutoff';
            ddLowpassCutoff.Items = arrayfun(@num2str,5:5:30,'uni',0);
            ddLowpassCutoff.Value = '20';




            % Panel for "Shock Controls" ----------------------------------------
            panelShockControls = uipanel(mainLayout, 'Title', 'Shock Controls');
            panelShockControls.Layout.Row = 8;
            panelShockControls.Layout.Column = [1 2];

            % > Shock Controls
            layoutShockControls = uigridlayout(panelShockControls);
            layoutShockControls.ColumnWidth = {100,'1x',100};
            layoutShockControls.RowHeight = {25,25};
            layoutShockControls.RowSpacing = 1;
            layoutShockControls.ColumnSpacing = 5;
            layoutShockControls.Padding = [0 0 0 0];

            % >> AutoShock
            chkAutoShock = uicheckbox(layoutShockControls);
            chkAutoShock.Layout.Row = 1;
            chkAutoShock.Layout.Column = 1;
            chkAutoShock.Text = "AutoShock";
            chkAutoShock.Tag = "chkAutoShock";
            chkAutoShock.Value = true;
            % chkAutoShock.ValueChangedFcn =

            % >> Shocker status
            lblShockerStatus = uilabel(layoutShockControls);
            lblShockerStatus.Layout.Row = 1;
            lblShockerStatus.Layout.Column = 2;
            lblShockerStatus.Text = "Shocker status:";
            lblShockerStatus.HorizontalAlignment = "right";

            % >> Shocker status dropdown
            ddShockerStatus = uidropdown(layoutShockControls);
            ddShockerStatus.Layout.Row = 1;
            ddShockerStatus.Layout.Column = 3;
            ddShockerStatus.Tag = 'ddShockerStatus';
            ddShockerStatus.Items = {'Off','On'};
            ddShockerStatus.Value = 'On';

            % >> Shock duration
            lblShockDuration = uilabel(layoutShockControls);
            lblShockDuration.Layout.Row = 2;
            lblShockDuration.Layout.Column = [1 2];
            lblShockDuration.Text = "Shock duration (s):";
            lblShockDuration.HorizontalAlignment = "right";

            % >> Shock duration dropdown
            ddShockDuration = uidropdown(layoutShockControls);
            ddShockDuration.Layout.Row = 2;
            ddShockDuration.Layout.Column = 3;
            ddShockDuration.Tag = 'ddShockDuration';
            ddShockDuration.Items = arrayfun(@num2str,0.1:0.1:0.5,'uni',0);
            ddShockDuration.Value = '0.3';



            % Panel for "Pump Controls" ------------------------------------------
            panelPumpControls = uipanel(mainLayout, 'Title', 'Pump Controls');
            panelPumpControls.Layout.Row = 9;
            panelPumpControls.Layout.Column = [1 2];

            % > Pump Controls
            layoutPumpControls = uigridlayout(panelPumpControls);
            layoutPumpControls.ColumnWidth = {'1x',100};
            layoutPumpControls.RowHeight = {25};
            layoutPumpControls.ColumnSpacing = 5;
            layoutPumpControls.Padding = [0 0 0 0];

            % >> Pump rate
            lblPumpRate = uilabel(layoutPumpControls);
            lblPumpRate.Layout.Row = 1;
            lblPumpRate.Layout.Column = 1;
            lblPumpRate.Text = "Pump rate (mL/min):";
            lblPumpRate.HorizontalAlignment = "right";

            % >> Pump rate dropdown
            ddPumpRate = uidropdown(layoutPumpControls);
            ddPumpRate.Layout.Row = 1;
            ddPumpRate.Layout.Column = 2;
            ddPumpRate.Tag = 'ddPumpRate';
            ddPumpRate.Items = arrayfun(@num2str,0.1:0.1:2,'uni',0);
            ddPumpRate.Value = '0.3';




            % Panel for "Trial Filter" ------------------------------------------
            panelTrialFilter = uipanel(mainLayout, 'Title', 'Trial Filter');
            panelTrialFilter.Layout.Row = [10 11];
            panelTrialFilter.Layout.Column = [1 2];


            % > Trial Filter
            layoutTrialFilter = simple_layout(panelTrialFilter);


            % > Trial Filter Table
            tableTrialFilter = uitable(layoutTrialFilter);
            tableTrialFilter.Tag = 'tblTrialFilter';
            tableTrialFilter.ColumnName = {'AMdepth','TrialType','Present'};
            tableTrialFilter.ColumnEditable = [false,false,true];
            tableTrialFilter.FontSize = 10;
            tableTrialFilter.Data = {...
                0, 'NOGO',true;
                0.03, 'GO', true;
                0.06, 'GO', true;
                0.08, 'GO', true;
                0.12, 'GO', true};
            % tableTrialFilter.CellEditCallback =



            % Panel for "Display Controls" ------------------------------------
            panelDisplayControls = uipanel(mainLayout, 'Title', 'Display');
            panelDisplayControls.Layout.Row = 1;
            panelDisplayControls.Layout.Column = 3;

            % > Display Controls
            layoutDisplayControls = simple_layout(panelDisplayControls);

            % > Display
            ddDisplay = uidropdown(layoutDisplayControls);
            ddDisplay.Tag = 'ddDisplay';
            ddDisplay.Items = {'Trial-Locked','Continuous'};
            ddDisplay.Value = 'Continuous';



            % Panel for "Keyboard shortcuts" ----------------------------------------
            panelKeyboardShortcuts = uipanel(mainLayout, 'Title', 'Keyboard Shortcuts');
            panelKeyboardShortcuts.Layout.Row = 1;
            panelKeyboardShortcuts.Layout.Column = 4;

            layoutKeyboardShortcuts = simple_layout(panelKeyboardShortcuts);

            lblKeyboardShortcuts = uilabel(layoutKeyboardShortcuts);
            lblKeyboardShortcuts.Text = [ ...
                "Use left and right arrows to scroll"; ...
                "Use plus and minus keys to zoon"];
            lblKeyboardShortcuts.FontSize = 10;




            % Panel for "Total Water" ----------------------------------------
            panelTotalWater = uipanel(mainLayout, 'Title', 'Total Water (mL)');
            panelTotalWater.Layout.Row = 1;
            panelTotalWater.Layout.Column = 7;

            layoutTotalWater = simple_layout(panelTotalWater);

            % > Total water *PRETTY SURE THIS CAN BE CREATED BY PUMP OBJ*
            lblTotalWater = uilabel(layoutTotalWater);
            lblTotalWater.Text = "*PUMP OBJ*";



            % Panel for "Next Trial" ----------------------------------------
            panelNextTrial = uipanel(mainLayout, 'Title', 'Next Trial');
            panelNextTrial.Layout.Row = [1 2];
            panelNextTrial.Layout.Column = 8;

            layoutNextTrial = simple_layout(panelNextTrial);

            % > Next Trial Table
            tableNextTrial = uitable(layoutNextTrial);
            tableNextTrial.ColumnName = {'AMdepth','TrialType'};
            tableNextTrial.ColumnEditable = false;
            tableNextTrial.FontSize = 8;





            % Axes for Main Plot ------------------------------------------------
            axesMain = uiaxes(mainLayout);
            axesMain.Layout.Row = [5 10];
            axesMain.Layout.Column = [3, 5];

            xlabel(axesMain,'AM depth')
            ylabel(axesMain,'Hit Rate')

            grid(axesMain,'on')
            box(axesMain,'on')


            % Panel for "Plotting Variables" ----------------------------------
            panelPlottingVariables = uipanel(mainLayout, 'Title', 'Plotting Variables');
            panelPlottingVariables.Layout.Row = [5 6];
            panelPlottingVariables.Layout.Column = 6;

            % > Plotting Variables
            layoutPlottingVariables = uigridlayout(panelPlottingVariables);
            layoutPlottingVariables.ColumnWidth = {100,100};
            layoutPlottingVariables.RowHeight = repmat({25},1,4);
            layoutPlottingVariables.ColumnSpacing = 5;
            layoutPlottingVariables.RowSpacing = 1;
            layoutPlottingVariables.Padding = [0 0 0 0];

            % >> Y
            lblY = uilabel(layoutPlottingVariables);
            lblY.Layout.Row = 1;
            lblY.Layout.Column = 1;
            lblY.Text = "Y:";
            lblY.HorizontalAlignment = "right";

            % >> Y dropdown
            ddY = uidropdown(layoutPlottingVariables);
            ddY.Layout.Row = 1;
            ddY.Layout.Column = 2;
            ddY.Tag = 'ddY';
            ddY.Items = {'Hit Rate','d-prime'};
            ddY.Value = 'Hit Rate';

            % >> X
            lblX = uilabel(layoutPlottingVariables);
            lblX.Layout.Row = 2;
            lblX.Layout.Column = 1;
            lblX.Text = "X:";
            lblX.HorizontalAlignment = "right";

            % >> X dropdown
            ddX = uidropdown(layoutPlottingVariables);
            ddX.Layout.Row = 2;
            ddX.Layout.Column = 2;
            ddX.Tag = 'ddX';
            ddX.Items = {'AMdepth'};
            ddX.Value = 'AMdepth';

            % >> Grouping variable
            lblGroupingVariable = uilabel(layoutPlottingVariables);
            lblGroupingVariable.Layout.Row = 3;
            lblGroupingVariable.Layout.Column = 1;
            lblGroupingVariable.Text = "Grouping variable:";
            lblGroupingVariable.HorizontalAlignment = "right";

            % >> Grouping variable dropdown
            ddGroupingVariable = uidropdown(layoutPlottingVariables);
            ddGroupingVariable.Layout.Row = 3;
            ddGroupingVariable.Layout.Column = 2;
            ddGroupingVariable.Tag = 'ddGroupingVariable';
            ddGroupingVariable.Items = {'None'};
            ddGroupingVariable.Value = 'None';

            % >> Include reminders
            chkIncludeReminders = uicheckbox(layoutPlottingVariables);
            chkIncludeReminders.Layout.Row = 4;
            chkIncludeReminders.Layout.Column = [1 2];
            chkIncludeReminders.Text = "Include reminders";
            chkIncludeReminders.Value = false;
            % chkIncludeReminders.ValueChangedFcn =


            % Panel for "Microphone Display" ------------------------------------
            panelMicrophoneDisplay = uipanel(mainLayout, 'Title', 'Microphone');
            panelMicrophoneDisplay.Layout.Row = [9 11];
            panelMicrophoneDisplay.Layout.Column = 6;

            layoutMicrophoneDisplay = simple_layout(panelMicrophoneDisplay);

            % Axes for Microphone Display
            axesMicrophone = uiaxes(layoutMicrophoneDisplay);
            axis(axesMicrophone,'image');

            lineMicrophone = line(axesMicrophone,[0 0],[0 1]);
            lineMicrophone.Color = 'y';
            lineMicrophone.LineWidth = 15;
            axesMicrophone.YLim = [0 10];
            axesMicrophone.XLim = [-1 1];
            axesMicrophone.XAxis.TickValues = [];
            axesMicrophone.YAxis.Label.String = "RMS voltage";
            axesMicrophone.YAxis.FontSize = 10;
            grid(axesMicrophone,'on');



            % Panel for "FA Rate" --------------------------------------------
            panelFARate = uipanel(mainLayout, 'Title', 'FA Rate');
            panelFARate.Layout.Row = [1 2];
            panelFARate.Layout.Column = 9;

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
            panelResponseHistory = uipanel(mainLayout, 'Title', 'Response History');
            panelResponseHistory.Layout.Row = [3, 6];
            panelResponseHistory.Layout.Column = [8 9];

            % % > Response History
            % layoutResponseHistory = simple_layout(panelResponseHistory);

            % > Response History Table
            % tableResponseHistory = uitable(layoutResponseHistory);
            % tableResponseHistory.ColumnName = {'AMdepth','TrialType','Response'};
            % tableResponseHistory.ColumnEditable = false;
            % tableResponseHistory.FontSize = 10;

            gui.History(obj.psychDetect,obj.RUNTIME.HELPER,panelResponseHistory);


            % Panel for "Trial History" ----------------------------------------
            panelTrialHistory = uipanel(mainLayout, 'Title', 'Trial History');
            panelTrialHistory.Layout.Row = [7 11];
            panelTrialHistory.Layout.Column = [7 9];
            

            % > Trial History
            layoutTrialHistory = simple_layout(panelTrialHistory);

            % > Trial History Table
            tableResponseHistory = uitable(layoutTrialHistory);
            tableResponseHistory.ColumnName = {'AMdepth','TrialType','# Trials','Hit rate (%)','dprime'};
            tableResponseHistory.ColumnEditable = false;
            tableResponseHistory.FontSize = 10;




            %
            hp = findobj(fig,'type','uipanel');
            set(hp, ...
                BorderType = "none", ...
                FontWeight = "bold", ...
                FontSize = 13)




            ddh = findobj(fig,'Type', 'uidropdown', '-regexp', 'Tag', '^dd');
            set(ddh,FontColor = 'b');

            obj.guiHandles = findobj(fig);

            


            % Create separate legacy figure for online plotting because
            % it's much faster than uifigure
            % Axes for Behavior Plot --------------------------------------------
            figOnlinePlot = figure(Name = 'Online Plot');
            p = fig.Position;
            figOnlinePlot.Position(1) = p(1);
            figOnlinePlot.Position(2) = p(2) + p(4) + 30;
            figOnlinePlot.Position(3) = p(3);
            figOnlinePlot.Position(4) = 200;
            figOnlinePlot.ToolBar = "none";
            figOnlinePlot.MenuBar = "none";
            figOnlinePlot.NumberTitle = "off";
            axesBehavior = axes(figOnlinePlot);
            gui.OnlinePlot(obj.RUNTIME,obj.watchedParameters,axesBehavior,1);
            
            % axesBehavior.YLim = [.5 2.5];
            % axesBehavior.YAxis.TickValues = [1 2];
            % axesBehavior.YAxis.TickLabels = ["Spout","In Trial"];
            % axesBehavior.YAxis.FontSize = 12;
            % axesBehavior.YAxis.FontWeight = "bold";
            % 
            % yline(axesBehavior,1.5)
            % 
            % box(axesBehavior,'on');
            % grid(axesBehavior,'on');
            % xlabel(axesBehavior,'time');


        end
    end

end


% used by create_gui
function h = simple_layout(p)
h = uigridlayout(p);
h.ColumnWidth = {'1x'};
h.RowHeight = {'1x'};
h.Padding = [0 0 0 0];
end