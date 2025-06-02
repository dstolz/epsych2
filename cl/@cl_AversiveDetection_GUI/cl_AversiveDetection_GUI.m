classdef cl_AversiveDetection_GUI < handle
    % cl_AversiveDetection_GUI: Interactive GUI for aversive detection behavior experiments.
    % This class creates a unified MATLAB app for online control, visualization, and performance review.

    properties (SetAccess = protected)
        h_figure               % Main figure handle
        h_OnlinePlot           % Handle to the online plot figure
        psychDetect            % psychophysics.Detect object
        psychPlot              % gui.psychPlot instance
        ResponseHistory        % gui.History instance
        Performance            % gui.Performance instance
        plottedParameters = {'~InTrial_TTL','~RespWindow','~Spout_TTL', ...
            '~ShockOn','~GO_Stim','~NOGO_Stim','~ReminderTrial','~TrialDelivery'} % Logical parameter tags
        lblFARate              % Label for FA Rate display
        tableTrialFilter       % Handle for the trial filter table
        hButtons               % Struct holding references to GUI control buttons
    end

    properties (Hidden)
        guiHandles             % Handles to all generated GUI components
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
            obj.psychDetect = psychophysics.Detect([],p);

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


        function update_trial_filter(obj,~,event)
            global RUNTIME


            src = obj.tableTrialFilter; % use this in case call is from outside the class
            depth     = [src.Data{:,1}];
            trialtype = [src.Data{:,2}];
            present   = [src.Data{:,4}];



            % always vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv
            present(trialtype==1) = true;
            [src.Data{trialtype==1,4}] = deal(true);
            % ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^


            p = RUNTIME.S.find_parameter('ShockN');
            shocked = find(present,p.Value,"last");
            shocked(ismember(shocked,find(trialtype==1))) = [];
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
            ind = present&trialtype==0;
            h.Title = sprintf('Trial Filter: %d Go trials active [%.3f-%.3f]', ...
                sum(ind),min(depth(ind)),max(depth(ind)));
        end


        function update_NewData(obj,src,event)
            % Turn Reminder button off after completing a Reminder trial           % trial
            if obj.hButtons.Reminder.Parameter.Value == 1
                obj.hButtons.Reminder.Parameter.Value = 0;
            end



            % calculate session FA rate and update
            obj.psychDetect.targetTrialType = 1; % CATCH TRIALS
            faRate = obj.psychDetect.Rate.FalseAlarm;
            if isnan(faRate), faTxt = '--'; else, faTxt = num2str(100*faRate,'%.2f'); end
            obj.lblFARate.Text = faTxt;

        end

        function update_NextTrial(obj,src,event)
            % notified that the next trial is ready

            D = event.Data;

            % Update Next Trial table
            h = findobj(obj.h_figure,'tag','tblNextTrial');
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





function [value,success] = evaluate_n_gonogo(obj,event)
% [value,success] = evaluate_n_gonogo(obj,event)
%
% implements the 'EvaluatorFcn' function
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