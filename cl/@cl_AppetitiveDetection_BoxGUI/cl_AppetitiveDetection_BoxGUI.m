classdef cl_AppetitiveDetection_BoxGUI < gui.BoxGUI
    % cl_AppetitiveDetection_BoxGUI Appetitive detection task control GUI.
    %
    % OBJ = cl_AppetitiveDetection_BoxGUI(RUNTIME) creates the Caras Lab
    % appetitive detection GUI: trigger buttons, staircase and trial
    % parameter controls, sound controls, phase selection, a trial-state
    % monitor, the psychometric plot, a parameter scatter, and a response
    % history table.
    %
    % This is the gui.BoxGUI-based version of cl_AppetitiveDetection_GUI_B.
    % The layout is the same; single-instance enforcement, figure creation,
    % position persistence, event listeners, Parameter_Update wiring, and
    % component teardown are inherited from gui.BoxGUI, so only build() and
    % the event hooks live here.
    %
    % Behavior is driven by a psychophysics.Staircase over the Depth
    % parameter, which is created by createPsych and therefore also supplies
    % the NewData event source for onNewData.
    %
    % Example:
    %   cl_AppetitiveDetection_BoxGUI(RUNTIME)   % called by epsych.RunExpt
    %
    % See also: gui.BoxGUI, cl_AppetitiveDetection_GUI_B, epsych.RunExpt,
    % documentation/gui/gui_BoxGUI.md,
    % documentation/layouts/cl_AppetitiveDetection_GUI_B_layout.md

    properties (SetAccess = protected)
        PhaseSelector          % gui.PhaseSelector instance
        h_PhaseSelector        % Container returned by PhaseSelector.createGUI
        ParameterMonitor       % gui.Parameter_Monitor instance (Trial State panel)
        ResponseHistory        % gui.History instance
        h_ScatterPanel         % gui.ParameterScatter instance
        FilenameField          % gui.FilenameValidator instance
        hReminder              % Reminder toggle control (also in hButtons)
        UpdateButton           % gui.Parameter_Update commit button
        lblPerformance         % Label showing session hit/abort/FA rates
        tableNextTrial         % Table showing the upcoming trial

        ttStimulus = 0;
        ttCatch    = 1;
        ttReminder = 2;
    end

    properties (Hidden)
        StaircaseTrainingGUIs       % containers.Map of gui.StaircaseTraining instances keyed by parameter name
        StaircaseTrainingListeners  % containers.Map of NewData listener handles keyed by parameter name
    end

    methods
        function obj = cl_AppetitiveDetection_BoxGUI(RUNTIME)
            % obj = cl_AppetitiveDetection_BoxGUI(RUNTIME)
            % Create the GUI. An existing instance is replaced.
            %  RUNTIME - epsych.Runtime object.
            obj@gui.BoxGUI(RUNTIME, ...
                Name='Caras Lab Appetitive Detection GUI', ...
                DefaultPosition=[1940 20 1400 1000]);

            if nargout == 0, clear obj; end
        end

        function delete(obj)
            % Staircase-training windows and their listeners are created
            % on demand by gui.eval_staircase_training_mode, so they are
            % outside the base class component registry.
            for m = {obj.StaircaseTrainingGUIs, obj.StaircaseTrainingListeners}
                if ~isa(m{1},'containers.Map'), continue; end
                k = m{1}.keys;
                for i = 1:numel(k)
                    v = m{1}(k{i});
                    if isvalid(v), delete(v); end
                end
            end

            delete@gui.BoxGUI(obj);
        end
    end

    methods (Access = protected)

        build(obj, fig)  % Build the GUI layout and wire all controls.

        function p = createPsych(obj, RUNTIME)
            % Staircase over Depth; its Helper becomes the NewData source.
            p = [];
            if isfield(obj.P,'Depth')
                p = psychophysics.Staircase(RUNTIME, obj.P.Depth);
            end
        end

        function onNewTrial(obj, ~, event)
            % Show the upcoming trial's depth and trial type.
            if isempty(obj.tableNextTrial) || ~isvalid(obj.tableNextTrial), return; end

            vprintf(4,'Update GUI for next trial')

            D  = event.Data;
            nt = D.trials(D.NextTrialID,:);
            am = nt{D.writeParamIdx.Depth};
            tt = nt{D.writeParamIdx.TrialType};

            switch tt
                case obj.ttStimulus, ttStr = 'STIM';
                case obj.ttCatch,    ttStr = 'CATCH';
                case obj.ttReminder, ttStr = 'REMIND';
                otherwise,           ttStr = num2str(tt);
            end

            obj.tableNextTrial.Data = {am, ttStr};
        end

        function onNewData(obj, ~, ~)
            % A Reminder trial is a one-shot: clear the toggle once the
            % trial it forced has completed.
            if ~isempty(obj.hReminder) && isvalid(obj.hReminder)
                p = obj.hReminder.Parameter;
                if p.Value == 1, p.Value = 0; end
            end

            if isempty(obj.Psych) || ~isvalid(obj.Psych), return; end
            if isempty(obj.lblPerformance) || ~isvalid(obj.lblPerformance), return; end

            % session performance summary
            rc = obj.Psych.responseCodes;
            if isempty(rc), return; end

            rc = epsych.BitMask.decode(rc);
            abortRate = sum(rc.Abort)      ./ sum(rc.TrialType_0);
            hitRate   = sum(rc.Hit)        ./ sum(rc.Hit | rc.Miss);
            faRate    = sum(rc.FalseAlarm) ./ sum(rc.TrialType_1);

            obj.lblPerformance.Text = sprintf( ...
                '  Hit Rate:\t%4.1f%%\nAbort Rate:\t%4.1f%%\nFalse Alarm Rate:\t%4.1f%%', ...
                hitRate*100, abortRate*100, faRate*100);
        end

        function onModeChange(obj, ~, event)
            % The base class already stopped registered monitors on Stop;
            % polling is left stopped so the final trial state stays
            % legible on screen, and resumes when the session runs again.
            if isempty(obj.ParameterMonitor) || ~isvalid(obj.ParameterMonitor), return; end

            switch event.NewMode
                case {hw.DeviceState.Preview, hw.DeviceState.Record}
                    obj.ParameterMonitor.start();
            end
        end
    end

    methods (Static)

        function trigger_ReminderTrial(obj, value, RUNTIME)
            % hw.Parameter PostUpdateFcn: force the next trial to be a
            % reminder trial.
            %  obj - the ReminderTrials hw.Parameter.
            if value == 0, return; end

            pdt = RUNTIME.find_parameter('~TrialDelivery',includeInvisible=true);
            if pdt.Value == 1
                obj.Value = 0;
                vprintf(0,1,'"Deliver Trials" must be inactive to initiate a Reminder trial')
                return
            end

            % FORCE_TRIAL tells ep_TimerFcn_RunTime to skip waiting for the
            % trial to complete and go directly to updating the next trial
            vprintf(3,'Forcing a Reminder Trial')
            RUNTIME.TRIALS.FORCE_TRIAL = true;
        end

        function trigger_FreeReward(obj, ~, ~)
            % hw.Parameter PostUpdateFcn: deliver a free reward.
            vprintf(3,'Initiating Free Trial Delivery')
            obj.Value = 1; % 100% depth
        end

        function trigger_Shape(obj, value, RUNTIME)
            % hw.Parameter PostUpdateFcn: present one 100% depth trial and
            % restore the working depth.
            if value == 0, return; end

            vprintf(3,'Initiating Shape Trial')
            cv = RUNTIME.P.Depth.Value; % current value
            RUNTIME.P.Depth.Value = 1;  % 100% depth

            obj.Value = 0;

            RUNTIME.P.Depth.Value = cv;
        end
    end
end
