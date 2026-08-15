classdef cl_AppetitiveDetection_BoxGUI < gui.BehaviorGUI
    % cl_AppetitiveDetection_BoxGUI Appetitive detection task control GUI.
    %
    % OBJ = cl_AppetitiveDetection_BoxGUI(RUNTIME) creates the Caras Lab
    % appetitive detection GUI: trigger buttons, staircase and trial
    % parameter controls, sound controls, phase selection, a trial-state
    % monitor, the psychometric plot, a parameter scatter, a session
    % performance summary, a response history table, and a session clock.
    %
    % This is the gui.BehaviorGUI-based version of cl_AppetitiveDetection_GUI_B.
    % The layout is the same; single-instance enforcement, figure creation,
    % position persistence, event listeners, Parameter_Update wiring, and
    % component teardown are inherited from gui.BehaviorGUI, so only build() and
    % the event hooks live here.
    %
    % Behavior is driven by a psychophysics.Staircase over the Depth
    % parameter, which is created by createPsych and therefore also supplies
    % the NewData event source for onNewData.
    %
    % Example:
    %   cl_AppetitiveDetection_BoxGUI(RUNTIME)   % called by epsych.RunExpt
    %
    % See also: gui.BehaviorGUI, cl_AppetitiveDetection_GUI_B, epsych.RunExpt,
    % documentation/gui/gui_BoxGUI.md,
    % documentation/layouts/cl_AppetitiveDetection_GUI_B_layout.md

    properties (SetAccess = protected)
        PhaseSelector          % gui.PhaseSelector instance
        h_PhaseSelector        % Container returned by PhaseSelector.createGUI
        ParameterMonitor       % gui.Parameter_Monitor instance (Trial State panel)
        SessionClock           % gui.SessionClock instance (top-row status widget)
        ResponseHistory        % gui.History instance
        h_ScatterPanel         % gui.ParameterScatter instance
        FilenameField          % gui.FilenameValidator instance
        hReminder              % Reminder toggle control (also in hButtons)
        UpdateButton           % gui.Parameter_Update commit button
        Performance            % gui.SessionPerformance instance (Session Performance panel)
        NextTrialPanel         % gui.NextTrial instance showing the upcoming trial
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
            obj@gui.BehaviorGUI(RUNTIME, ...
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

            delete@gui.BehaviorGUI(obj);
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

        function onNewData(~, ~, ~)
            % Nothing to do per trial.
            %
            % The Reminder toggle is NOT cleared here. NewData is broadcast
            % for the completed trial before the runtime calls selectNext for
            % the next one, so clearing it here withdrew the request in the
            % same pass that was about to honor it and the Reminder button
            % only ever force-ended the current trial. The one-shot is
            % consumed instead by cl_AppetitiveStimDetect, in the selection
            % pass that grants it.
            %
            % The session performance summary is not updated here either: the
            % gui.SessionPerformance panel owns its own
            % psychophysics.SessionMetrics and follows NewData itself.
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

        function trigger_ReminderTrial(~, value, ~)
            % hw.Parameter PostUpdateFcn: log the operator's request.
            %
            % The request is queued, not immediate: the trial in progress
            % runs to its natural end, and cl_AppetitiveStimDetect presents
            % the reminder as the next trial, clearing the toggle in the same
            % selection pass. This handler deliberately does NOT set
            % TRIALS.FORCE_TRIAL -- that ended the trial in progress early
            % and wrote a DATA record from a response the subject had not
            % finished making.
            %
            % It logs at level 1 because a queued request gives the operator
            % no immediate feedback beyond the button staying lit.
            if value == 0, return; end

            vprintf(1,'Reminder trial requested; queued for the next trial')
        end

        function trigger_FreeReward(obj, ~, ~)
            % hw.Parameter PostUpdateFcn: deliver a free reward.
            vprintf(3,'Initiating Free Trial Delivery')
            obj.Value = 1; 
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
