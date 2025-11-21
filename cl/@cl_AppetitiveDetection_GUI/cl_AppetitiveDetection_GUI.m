classdef cl_AppetitiveDetection_GUI < handle

    properties (SetAccess = protected)
        h_figure               % Main figure handle
        h_OnlinePlot           % Handle to the online plot figure
        psychDetect            % psychophysics.Detect object
        psychPlot              % gui.psychPlot instance
        % slidingWindowPlot      % gui.SlidingWindowPerformancePlot instance
        ResponseHistory        % gui.History instance
        Performance            % gui.Performance instance
        plottedParameters = {'~Observation_TTL','~Spout_TTL','~GO_Stim','~NOGO_Stim'} % Logical parameter tags
        lblFARate              % Label for FA Rate display
        tableTrialFilter       % Handle for the trial filter table
        hButtons               % Struct holding references to GUI control buttons

        bmStimulus  = epsych.BitMask.TrialType_0;
        bmCatch     = epsych.BitMask.TrialType_1;
        bmReminder  = epsych.BitMask.TrialType_2;

        ttStimulus  = 0;
        ttCatch     = 1;
        ttReminder  = 2;
    end

    properties (Hidden)
        guiHandles             % Handles to all generated GUI components
        hl_NewTrial
        hl_NewData
        hl_ModeChange
    end

    methods
        create_gui(obj)
        [value,success] = eval_gonogo(obj,src,event)

        % constructor
        function obj = cl_AppetitiveDetection_GUI(RUNTIME)
            % only permit one instance to run
            f = findall(groot,'Type','figure');
            f = f(startsWith({f.Tag},'cl_AppetitiveDetection_GUI'));


            if ~isempty(f)
                % THIS IS A BUG THAT SHOULD BE FIXED
                vprintf(0,1,'RESTARTING GUI')
                for i = 1:length(f)
                    try
                        delete(f(i).UserData);
                        delete(f(i));
                    end
                end
            end


            % create psychophysics object
            p = RUNTIME.HW.find_parameter('Depth');
            obj.psychDetect = psychophysics.Detect([],p);

            % generate gui layout and components
            obj.create_gui;

            % obj.create_onlineplot; % FIX PERFORMANCE


            if nargout == 0, clear obj; end

        end


        % destructor
        function delete(obj)
            % t = timerfindall;
            % n = {t.Name};
            % i = startsWith(n,'epsych_gui');
            % stop(t(i));
            % delete(t(i));

            vprintf(3,'cl_AppetitiveDetection_GUI destructor')
            delete(obj.guiHandles);
            obj.hl_NewTrial.Enabled = 0;
            obj.hl_NewData.Enabled = 0;
            delete(obj.hl_NewTrial);
            delete(obj.hl_NewData);

            try
                close(obj.h_OnlinePlot);
            end

            delete(timerfindall("Tag","GUIGenericTimer"))
        end

        function closeGUI(obj,src,event)
            vprintf(3,'cl_AppetitiveDetection_GUI:closeGUI')
            try
                delete(obj);
                delete(src)
            end
        end

        function update_trial_filter(obj,~,event)
            global RUNTIME


            src = obj.tableTrialFilter; % use this in case call is from outside the class
            depth     = [src.Data{:,1}];
            trialtype = [src.Data{:,2}];
            present   = [src.Data{:,4}];



            % always vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv
            present(trialtype==obj.ttCatch) = true;
            [src.Data{trialtype==obj.ttCatch,4}] = deal(true);
            % ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^


            p = RUNTIME.S.find_parameter('ShockN');
            shocked = find(present,p.Value,"last");
            shocked(ismember(shocked,find(trialtype==obj.ttCatch))) = [];
            [src.Data{:,3}] = deal(false);
            [src.Data{shocked,3}] = deal(true);


            RUNTIME.TRIALS.shockedTrials = shocked;
            RUNTIME.TRIALS.activeTrials = present;

            if any(~present)
                vprintf(4,'Inactive Depths: %s',mat2str(depth(~present)));
            end
            vprintf(2,'Active Depths: %s',mat2str(depth(present)));

            % update panel label with trial type counts
            h = ancestor(src,'uipanel');
            ind = present&trialtype==obj.ttStimulus;
            h.Title = sprintf('Trial Filter: %d Go trials active [%.3f-%.3f]', ...
                sum(ind),min(depth(ind)),max(depth(ind)));
        end

        function onModeChange(obj,src,ev)
            % fprintf('Mode changed to: %s\n', string(ev.NewMode));

            switch ev.NewMode
                case hw.DeviceState.Stop
                    fprintf('TO DO: Update filename\n')
            end
        end

        function update_NewData(obj,src,event)
            % Turn Reminder button off after completing a Reminder trial           % trial
            if obj.hButtons.Reminder.Parameter.Value == 1
                obj.hButtons.Reminder.Parameter.Value = 0;
            end


            try % TODO: FIGURE OUT WHY THIS IS HAPPENING

                % calculate session FA rate and update
                obj.psychDetect.targetTrialType = obj.bmCatch; % CATCH TRIALS
                faRate = obj.psychDetect.Rate.FalseAlarm;
                if isempty(faRate) || isnan(faRate), faTxt = '--'; else, faTxt = num2str(100*faRate,'%.2f'); end
                obj.lblFARate.Text = faTxt;
            end

        end

        function update_NextTrial(obj,src,event)
            % notified that the next trial is ready
            vprintf(4,'Update GUI for next trial')
            D = event.Data;

            % Update Next Trial table
            persistent h
            if isempty(h) || ~ishandle(h) || ~isvalid(h)
                h = findobj(obj.h_figure,'tag','tblNextTrial');
            end
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

        end



        function create_onlineplot(obj,varargin)
            global RUNTIME

            % Create separate legacy figure for online plotting because
            % it's much faster than uifigure
            % Axes for Behavior Plot --------------------------------------------
            f = findobj('type','figure','-and','name','cl_AppetitiveDetection_OnlinePlot');
            if isempty(f)
                f = figure(Name = 'Online Plot', ...
                    Tag = 'cl_AppetitiveDetection_OnlinePlot');
            else
                figure(f);
                return
            end

            p = obj.h_figure.Position;
            f.Position(1) = p(1);
            f.Position(2) = p(2) + p(4) + 100;
            f.Position(3) = p(3);
            f.Position(4) = 150;
            f.ToolBar = "none";
            f.MenuBar = "none";
            f.NumberTitle = "off";
            axesBehavior = axes(f);
            % gui.OnlinePlot(RUNTIME,obj.plottedParameters,axesBehavior,1);
            gui.OnlinePlotBM(RUNTIME,'OnlinePlotBits',axesBehavior,1);

            obj.h_OnlinePlot = f;


        end


    end

    methods (Static)

        function trigger_ReminderTrial(obj, value)
            global RUNTIME

            prt = RUNTIME.S.find_parameter('ReminderTrials');
            if prt.Value == 0, return; end

            pdt = RUNTIME.HW.find_parameter('~TrialDelivery',includeInvisible=true);
            if pdt.Value == 1
                obj.Value = 0;
                vprintf(0,1,'"Deliver Trials" must be inactive to initiate a Reminder trial')
                return
            end

            % the following FORCE_TRIAL tells ep_TimerFcn_RunTime to skip
            % waiting for trial to complete and just go directly to
            % updating for next trial
            vprintf(4,'Forcing a Reminder Trial')
            RUNTIME.TRIALS.FORCE_TRIAL = true;

        end

    end

end



