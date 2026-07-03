classdef Runtime < handle & dynamicprops
    % epsych.Runtime
    % Runtime state container for EPsych experiment execution.
    %
    % Stores experiment-wide state including subject count, trial metadata,
    % hardware/software interfaces, event dispatchers, and timer services.
    %
    % Key properties:
    %   NSubjects   - Number of subjects (default: 1)
    %   TRIALS      - Protocol trial data and selection state
    %   HW          - Hardware interface object(s)
    %   S           - Software interface object(s)
    %   HELPER      - Event dispatcher object
    %   TIMER       - Timer object for runtime services
    %
    % Key methods:
    %   Runtime                    - Construct an empty runtime container
    %   writeParametersJSON        - Serialize runtime parameters to JSON
    %   readParametersJSON         - Load runtime parameters from JSON
    %   all_parameters             - Retrieve all hardware/software parameters
    %   updateTrialsFromParameters - Sync writable TRIALS fields from parameters
    %   createTemplateJSON         - Create a template JSON for parameter files
    %
    % Usage:
    %   r = epsych.Runtime;
    %   r.NSubjects = 2;
    %   r.writeParametersJSON('params.json');
    %
    % See also: documentation/epsych/epsych_Runtime.md


    properties
        isTest (1,1) logical = false % True if data is being generated for a test run

        HWinUse (1,:) string % List of hardware in use (string array)

        TRIALS            % Protocol-specific trial information, including trial selection function, trial parameters, and trial count
        dfltDataPath (1,1) string = "" % Default data path for output
        HELPER            % Helper/event dispatcher object (e.g., epsych.Helper)
        TIMER (1,1) timer % MATLAB timer object for runtime services


        TempDataDir (1,1) string = "" % Directory for acquired data
        DataFile string = strings(0,1)   % Filepath(s) for acquired data

        Interfaces        % Cell array of hardware and software interfaces (e.g., hw.TDT_RPcox, hw.Software)
 
        CORE              % Runtime core or struct-compatible

        StartTime datetime = NaT % Experiment start time (datetime)

        TrialComplete  % Manual trial completion flag (if in use, wait for manual completion of trial in RPvds)
    end

    properties (SetAccess = private)
        NSubjects (1,1) double {mustBePositive, mustBeInteger} = 1 % Number of subjects in the experiment
    end

    properties (Constant)
        % Define any constant properties here (e.g., default timer settings, required trigger names)
        REQUIRED_TRIGGERS = ["NewTrial", "ResetTrig", "TrialComplete"] % List of required trigger parameter suffixes
    end

    properties (Access = private)
        TRIALSInitialized_ (1,1) logical = false % True once TRIALS has been set for the first time on this Runtime instance
    end


    methods
        writeParametersJSON(obj, filepath)      % Serialize runtime parameters to a JSON file.
        P = readParametersJSON(obj, filepath)   % Load runtime parameters from a JSON file; returns the resolved hw.Parameter array.
        dispatchNextTrial(obj, subjectIdx)      % Dispatch the already selected next trial for one subject.
        resolveCoreParameters(obj, subjectIdx)  % Locate and cache mandatory trigger parameters (NewTrial, ResetTrig, TrialComplete) for one subject.

        function self = Runtime
            % self = Runtime
            % Construct an empty Runtime container and initialize state.
            vprintf(2, 'Initializing Runtime object')
        end

        function delete(self)
            % delete(self)
            % Clean up runtime resources owned by this object.
            %
            % Only the timer is torn down here. The hardware Interfaces are
            % owned by the epsych.Protocol and are merely borrowed by the
            % Runtime; they are returned to Idle on stop (see
            % ep_TimerFcn_Stop) and remain connected for reuse on the next
            % run. Disconnecting them here would force a delete/recreate of
            % the backend connection on every rerun, which some hardware
            % (e.g. TDT RPcoX/zBus) cannot survive, breaking the second run.
            % Hardware is released explicitly when the session closes
            % (see RunExpt.onCloseRequest).
            vprintf(2, 'Cleaning up Runtime resources')
            if ~isempty(self.TIMER) && isvalid(self.TIMER) && strcmp(self.TIMER.Running, 'on')
                stop(self.TIMER);
                delete(self.TIMER);
            end
        end

        function set.Interfaces(self, protocol_interfaces)
            % set.Interfaces(self, value)
            
            for p = protocol_interfaces(:).'
                vprintf(0,'Connecting to hardware interface: %s', class(p))
                
                if ~p.IsConnected
                    p.connect();
                    assert(p.IsConnected, ...
                        'epsych:RunExpt:HardwareConnectionFailed', ...
                        'Hardware interface "%s" failed to connect. Check hardware status before starting.', ...
                        class(p));
                end
                p.Runtime = self;
            end
            self.Interfaces = protocol_interfaces;
        end

        function set.TRIALS(self, value)
            % set.TRIALS(self, value)
            % Custom setter for TRIALS property to ensure it is a struct with required fields.

            self.TRIALS = value;
            self.NSubjects = length(self.TRIALS);

            % Resolving CORE triggers and dispatching the first trial must
            % happen only once per Runtime instance (when TRIALS is first
            % populated by ep_TimerFcn_Start). Later writes, such as
            % updateTrialsFromParameters syncing parameter edits mid-run,
            % must not re-trigger hardware or re-dispatch trials.
            if ~self.TRIALSInitialized_
                for i = 1:self.NSubjects
                    self.resolveCoreParameters(i);
                    self.dispatchNextTrial(i);
                end
                self.TRIALSInitialized_ = true;
            end

        end

        filter_parameters(obj, propertyName, propertyValue, options, poptions) % Return hw.Parameter objects whose named property matches a target value.
        p = find_parameter(obj, name, options)              % Return hw.Parameter handles matching the given name(s), with optional pre-filtering.
        p = all_parameters(obj, options)                % Retrieve all parameters from all registered interfaces, with optional filtering.
        updateTrialsFromParameters(obj, Parameters)     % Sync writable TRIALS fields from current parameter values.
    end

    methods (Static)
        tf = local_test(fcn, val, pat)      % Normalize any comparison result to a logical scalar.
        createTemplateJSON(filepath)        % Write a template JSON file with example hw.Parameter fields to disk.
    end
end


