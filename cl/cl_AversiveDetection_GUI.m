classdef cl_AversiveDetection_GUI < handle

    properties (SetAccess = protected)
        h_figure

        h_OnlinePlot

        psychDetect % psychophysics.Detect

        PsychPlot % gui.PsychPlot
        ResponseHistory % gui.History

        plottedParameters = {'~InTrial_TTL','~RespWindow','~Spout_TTL',...
            '~ShockOn','~GO_Stim','~NOGO_Stim'}


        lblFARate
    end


    properties (Hidden)
        guiHandles
    end



    methods
        % constructor
        function obj = cl_AversiveDetection_GUI(RUNTIME)
            % only permit one instance to run
            f = findall(groot,'Type','figure');
            f = f(startsWith({f.Tag},'cl_AversiveDetection'));


            if ~isempty(f)
                % THIS IS A BUG THAT SHOULD BE FIXED
                vprintf(0,1,'RESTARTING GUI')
                delete(f);
            end


            % create detection object
            p = RUNTIME.HW.find_parameter('Depth');
            obj.psychDetect = psychophysics.Detection(p);

            % generate gui layout and components
            obj.create_gui;

            obj.create_onlineplot;


            if nargout == 0, clear obj; end

        end


        % destructor
        function delete(obj)
            t = timerfindall;
            n = {t.Name};
            i = startsWith(n,'epsych_gui');
            stop(t(i));
            delete(t(i));

            delete(obj.guiHandles);

            try
                close(obj.h_OnlinePlot);
            end
        end


        function update_trial_filter(obj,src,event)
            global RUNTIME

            depth     = [src.Data{:,1}];
            trialtype = [src.Data{:,2}];
            shocked   = [src.Data{:,3}];
            present   = [src.Data{:,4}];

            if ~present(trialtype==1)
                src.Data{trialtype==1,3} = true;
                present(trialtype==1) = true; % always
            end

            RUNTIME.TRIALS.activeTrials = present;

            if any(~present)
                vprintf(2,'Inactive Depths: %s',mat2str(depth(~present)));
            end
            vprintf(2,'Active Depths: %s',mat2str(depth(present)));

            % update panel label with trial type counts
            h = ancestor(src,'uipanel');
            ind = present&trialtype==0;
            h.Title = sprintf('Trial Filter: %d Go trials active [%.3f-%.3f]', ...
                sum(ind),min(depth(ind)),max(depth(ind)));
        end



        function update_NextTrial(obj,src,event)
            % notified that the next trial is ready

             h = findobj(obj.h_figure,'tag','tblNextTrial');
             D = event.Data;
             ntid = D.NextTrialID;
             nt = D.trials(ntid,:);
             am = nt{D.writeParamIdx.Depth};
             tt = nt{D.writeParamIdx.TrialType};
             nd = {am,tt};
             switch tt
                 case 0
                     nd{2} = 'GO';
                 case 1
                     nd{2} = 'NOGO';
                 case 2
                     nd{2} = 'REMIND';
             end
             h.Data = nd;


             % calculate session FA rate and update
             obj.lblFARate.Text = num2str(obj.psychDetect.FA_Rate(1)*100,'%.2f');
        end

        function create_gui(obj)
            global RUNTIME

            % Create the main figure
            fig = uifigure(Tag = 'cl_AversiveDetection_GUI', ...
                Name = 'Caras Lab Aversive Detection GUI');
            fig.Position = [1940 -1044 1400 1000];  % Set figure size

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
            h = gui.Parameter_Control(buttonLayout,p,Type='toggle',autoCommit=true);
            h.Text = "Reminders";
            h.colorNormal = bcmNormal(1,:);
            h.colorOnUpdate = bcmActive(1,:);

            % > ReferencePhys
            p = RUNTIME.S.Module.add_parameter('ReferencePhys',0);
            h = gui.Parameter_Control(buttonLayout,p,Type='toggle',autoCommit=true);
            h.Text = "ReferencePhys";
            h.colorNormal = bcmNormal(2,:);
            h.colorOnUpdate = bcmActive(2,:);


            % > Deliver Trials
            p = RUNTIME.HW.find_parameter('~TrialDelivery',includeInvisible=true);
            h = gui.Parameter_Control(buttonLayout,p,Type='toggle',autoCommit=true);
            h.Text = "Deliver Trials";
            h.colorNormal = bcmNormal(3,:);
            h.colorOnUpdate = bcmActive(3,:);

            % > Pause Trials
            p = RUNTIME.S.Module.add_parameter('PauseTrials',0);
            h = gui.Parameter_Control(buttonLayout,p,Type='toggle',autoCommit=true);
            h.Text = "Pause Trials";
            h.colorNormal = bcmNormal(4,:);
            h.colorOnUpdate = bcmActive(4,:);

            % > Air Puff
            p = RUNTIME.S.Module.add_parameter('AirPuff',0);
            h = gui.Parameter_Control(buttonLayout,p,Type='toggle',autoCommit=true);
            h.Text = "Air Puff";
            h.colorNormal = bcmNormal(5,:);
            h.colorOnUpdate = bcmActive(5,:);


            bh = findobj(fig,'Type', 'uistatebutton');
            set(bh, ...
                FontWeight = 'bold', ...
                FontSize = 13, ...
                Enable = "on");











            % % PARAMETERS ----------------------------------------------------
            % % Panel for "Reminder Trial"
            % panelReminderTrial = uipanel(layoutMain, 'Title', 'Reminder Trial');
            % panelReminderTrial.Layout.Row = [2 3];
            % panelReminderTrial.Layout.Column = [1 2];
            %
            % % > ReminderTrial
            % layoutReminderTrial = simple_layout(panelReminderTrial);
            %
            % % > Reminder Trial Table
            % tableReminderTrial = uitable(layoutReminderTrial);
            % tableReminderTrial.ColumnName = {'Depth','TrialType'};
            % tableReminderTrial.ColumnEditable = false;
            % tableReminderTrial.FontSize = 8;


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
            h.Evaluator = @evaluate_n_gonogo;
            h.Values = 0:5;
            h.Value = 3;
            h.Text = "Consecutive NoGo (min):";

            % >> Consecutive NOGO max
            p = RUNTIME.S.Module.add_parameter('ConsecutiveNOGO_max',5);
            h = gui.Parameter_Control(layoutTrialControls,p,Type='dropdown');%,autoCommit=true);
            h.Evaluator = @evaluate_n_gonogo;
            h.Values = 3:20;
            h.Value = 5;
            h.Text = "Consecutive NoGo (max):";


            % >> Trial order
            p = RUNTIME.S.Module.add_parameter('TrialOrder','Descending');
            h = gui.Parameter_Control(layoutTrialControls,p,Type='dropdown',autoCommit=true);
            h.Values = ["Descending","Ascending","Random"];
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
            h.Values = 200:100:1000;
            h.Text = "Response Window Duration (ms):";


            % >> Optogenetic trigger
            p = RUNTIME.HW.find_parameter('Optostim');
            h = gui.Parameter_Control(layoutTrialControls,p,Type='dropdown');
            h.Values = [0 1];
            h.Value = 0;
            h.Text = "Optogenetic Trigger:";










            % SOUND CONTROLS -----------------------------------------------------

            % >> dB SPL
            p = RUNTIME.HW.find_parameter('dBSPL');
            h = gui.Parameter_Control(layoutSoundControls,p,Type='dropdown');
            h.Values = 0:6:84;
            h.Value = 48;
            h.Text = "Sound Level (dB SPL):";


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


            % % >> AM Depth
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

            % >> Shock N hardest
            p = RUNTIME.S.Module.add_parameter('ShockN',3);
            h = gui.Parameter_Control(layoutShockControls,p,Type='dropdown');%,autoCommit=true);
            h.Values = 1:5;
            h.Value = 3;
            h.Text = "Shock Hardest #:";






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







            % Commit button ---------------------------------------------
            h = gui.Parameter_Update(layoutMain);
            h.Button.Layout.Row = [9 10];
            h.Button.Layout.Column = [3 4];
            h.Button.Text = ["Update" "Parameters"];
            h.Button.FontSize = 24;

            % find all 'Paramete_Control' objects
            hp = findall(fig,'-regexp','tag','^PC_');
            h.watchedHandles = [hp.UserData];




            % create/locate online plot ------------------------------------
            h = uibutton(layoutMain);
            h.Layout.Row = 11;
            h.Layout.Column = 3;
            h.Text = "Online Plot";
            h.ButtonPushedFcn = @obj.create_onlineplot;






            % Panel for "Trial Filter" ------------------------------------------
            panelTrialFilter = uipanel(layoutMain, 'Title', 'Trial Filter');
            panelTrialFilter.Layout.Row = [9 11];
            panelTrialFilter.Layout.Column = [1 2];
            panelTrialFilter.Scrollable = 'on';

            % > Trial Filter
            layoutTrialFilter = simple_layout(panelTrialFilter);


            % > Trial Filter Table
            tt = RUNTIME.TRIALS.trials;
            loc = RUNTIME.TRIALS.writeParamIdx;
            reminderInd = [tt{:,loc.Reminder}];
            d = tt(~reminderInd,loc.Depth);
            d(:,2) = tt(~reminderInd,loc.TrialType);
            d(:,3) = {false};
            d(:,4) = {true};
            % [~,i] = sort([d{:,1}],'descend');
            % d = d(i,:);
            tableTrialFilter = uitable(layoutTrialFilter);
            tableTrialFilter.Tag = 'tblTrialFilter';
            tableTrialFilter.ColumnName = {'Depth','TrialType','Shocked','Present'};
            tableTrialFilter.ColumnEditable = [false,false,false,true];
            tableTrialFilter.FontSize = 10;
            tableTrialFilter.Data = d;
            tableTrialFilter.CellEditCallback = @obj.update_trial_filter;
            obj.update_trial_filter(tableTrialFilter);




            % Panel for "Next Trial" ----------------------------------------
            panelNextTrial = uipanel(layoutMain, 'Title', 'Next Trial');
            panelNextTrial.Layout.Row = [1 2];
            panelNextTrial.Layout.Column = 7;

            layoutNextTrial = simple_layout(panelNextTrial);

            % > Next Trial Table
            % *** NEED TO SEE HOW THIS IMPLEMENTED ON THE CURRENT GUI ***
            tableNextTrial = uitable(layoutNextTrial);
            tableNextTrial.Tag = 'tblNextTrial';
            tableNextTrial.ColumnName = {'Depth','TrialType'};
            tableNextTrial.RowName = [];
            tableNextTrial.ColumnEditable = false;
            tableNextTrial.FontSize = 20;

            addlistener(RUNTIME.HELPER,'NewTrial',@(src,evnt) obj.update_NextTrial(src,evnt));





            % Axes for Main Plot ------------------------------------------------
            axPsych = uiaxes(layoutMain);
            axPsych.Layout.Row = [4 8];
            axPsych.Layout.Column = [3, 5];

            obj.PsychPlot = gui.PsychPlot(obj.psychDetect,axPsych);

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
            % ddX.Items = {'Depth'};
            % ddX.Value = 'Depth';
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

            p = RUNTIME.HW.find_parameter('MicPower');
            gui.MicrophonePlot(p,axesMicrophone);
            axesMicrophone.YAxis.Label.String = "RMS voltage";


            % Panel for "FA Rate" --------------------------------------------
            panelFARate = uipanel(layoutMain, 'Title', 'Session FA Rate');
            panelFARate.Layout.Row = 3;
            panelFARate.Layout.Column = 5;

            layoutFARate = simple_layout(panelFARate);

            % > FA Rate
            h = uilabel(layoutFARate);
            h.Tag = 'lblFARate';
            h.Text = "0";
            h.FontColor = 'r';
            h.FontSize = 40;
            h.FontWeight = 'bold';
            h.HorizontalAlignment = "center";
            obj.lblFARate = h;


            % Panel for "Response History" --------------------------------------
            panelResponseHistory = uipanel(layoutMain, 'Title', 'Response History');
            panelResponseHistory.Layout.Row = [3, 6];
            panelResponseHistory.Layout.Column = [6 7];

            % > Response History Table
            obj.ResponseHistory = gui.History(obj.psychDetect,panelResponseHistory);
            obj.ResponseHistory.ParametersOfInterest = {'Depth','TrialType','Reminder'};


            % Panel for "Trial History" ----------------------------------------
            panelTrialHistory = uipanel(layoutMain, 'Title', 'Trial History');
            panelTrialHistory.Layout.Row = [7 11];
            panelTrialHistory.Layout.Column = [6 7];


            % > Trial History
            layoutTrialHistory = simple_layout(panelTrialHistory);

            % > Trial History Table
            tableResponseHistory = uitable(layoutTrialHistory);
            tableResponseHistory.ColumnName = {'Depth','TrialType','# Trials','Hit rate (%)','dprime'};
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







        end

        function create_onlineplot(obj,varargin)
            global RUNTIME

            % Create separate legacy figure for online plotting because
            % it's much faster than uifigure
            % Axes for Behavior Plot --------------------------------------------
            f = findobj('type','figure','-and','name','cl_AversiveDetection_OnlinePlot');
            if isempty(f)
                f = figure(Name = 'Online Plot', ...
                    Tag = 'cl_AversiveDetection_OnlinePlot');
            else
                figure(f);
                return
            end

            p = obj.h_figure.Position;
            f.Position(1) = p(1);
            f.Position(2) = p(2) + p(4) + 100;
            f.Position(3) = p(3);
            f.Position(4) = 200;
            f.ToolBar = "none";
            f.MenuBar = "none";
            f.NumberTitle = "off";
            axesBehavior = axes(f);
            gui.OnlinePlot(RUNTIME,obj.plottedParameters,axesBehavior,1);

            obj.h_OnlinePlot = f;


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