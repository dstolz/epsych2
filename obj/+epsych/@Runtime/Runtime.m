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
    %   EVENTS      - Event broadcaster (epsych.EventHub)
    %   TIMER       - Timer object for runtime services
    %   ReviewMode  - True when replaying a finished session (epsych.ReviewSession)
    %
    % Key methods:
    %   Runtime                    - Construct an empty runtime container
    %   writeParametersProtocol    - Save the current session as a protocol (.eprot) phase file
    %   readParameters             - Load a phase file (.eprot/.prot or legacy .json)
    %   writeParametersJSON        - Serialize runtime parameters to JSON (legacy phase format)
    %   readParametersJSON         - Back-compat wrapper for readParameters
    %   all_parameters             - Retrieve all hardware/software parameters
    %   updateTrialsFromParameters - Sync writable TRIALS fields from parameters
    %   createTemplateJSON         - Create a template JSON for parameter files
    %
    % Usage:
    %   r = epsych.Runtime;
    %   r.NSubjects = 2;
    %   r.writeParametersProtocol('phase_A.eprot');
    %
    % See also: documentation/epsych/epsych_Runtime.md


    properties
        isTest (1,1) logical = false % True if data is being generated for a test run

        % True when this runtime is replaying a finished session rather than
        % running one (epsych.ReviewSession). It suppresses the one-shot trial
        % dispatch in set.TRIALS -- a review must not write parameters or fire
        % triggers -- and it is the flag a behavior GUI consults before doing
        % anything that drives the rig. Paradigm GUIs that run their own timer
        % and hand trials back (examples/two_afc, examples/first_experiment,
        % examples/syringepump) MUST check it; the base class cannot stand them
        % down for them. See gui.BehaviorGUI.ReviewMode.
        ReviewMode (1,1) logical = false

        HWinUse (1,:) string % List of hardware in use (string array)

        % NOTES - The operator's typed session notes (epsych.SessionNotes).
        % Always present, so a caller never has to test for it: notes typed
        % before a run are stamped trial 0 and saved just the same. It is
        % epsych.SessionSnapshot.forSubject that folds them into the Info
        % variable every saving function already writes. gui.components.Notes is the
        % operator-facing end; anything else adds one with NOTES.add(text).
        NOTES epsych.SessionNotes {mustBeScalarOrEmpty} = epsych.SessionNotes.empty

        TRIALS            % Protocol-specific trial information, including trial selection function, trial parameters, and trial count
        DefaultDataPath (1,1) string = "" % Default data path for output
        EVENTS            % Event broadcaster shared by the session (epsych.EventHub)
        TIMER (1,1) timer % MATLAB timer object for runtime services


        TempDataDir (1,1) string = "" % Directory for acquired data
        DataFile string = strings(0,1)   % Filepath(s) for acquired data
        Journal          % epsych.TrialJournal array, one per subject; per-trial crash-safe append target (see ep_TimerFcn_Start)
        SessionDataFilename (1,:) string = strings(1,0) % Per-subject data file paths reserved before the run starts, so the save function and the video recorder agree on one name

        Interfaces        % Cell array of hardware and software interfaces (e.g., hw.TDT_RPcox, hw.Software)

        Protocol epsych.Protocol {mustBeScalarOrEmpty} = epsych.Protocol.empty % Session protocol whose Interfaces this runtime borrows; phases are saved by serializing it (writeParametersProtocol)
 
        TRIGGERS          % Per-subject cached handles to the REQUIRED_TRIGGERS parameters (NewTrial, ResetTrig, TrialComplete)
        P                % Cached hw.Parameter array for all parameters in use (struct form)

        StartTime datetime = NaT % Experiment start time (datetime)

        TrialComplete  % Manual trial completion flag (if in use, wait for manual completion of trial in RPvds)
    end

    properties (SetAccess = private)
        NSubjects (1,1) double {mustBePositive, mustBeInteger} = 1 % Number of subjects in the experiment
    end

    % Deprecated names kept so paradigm code written against the old property
    % names -- custom save functions, timer functions, and box GUIs that live
    % outside this repository -- keeps working. They forward silently rather
    % than warning because a timer function reads them on every tick. Remove
    % once the labs' paradigm folders have been migrated.
    properties (Dependent, Hidden)
        HELPER        % Deprecated alias for EVENTS
        CORE          % Deprecated alias for TRIGGERS
        dfltDataPath  % Deprecated alias for DefaultDataPath
    end

    properties (Constant)
        % Define any constant properties here (e.g., default timer settings, required trigger names)
        REQUIRED_TRIGGERS = ["NewTrial", "ResetTrig", "TrialComplete"] % List of required trigger parameter suffixes
    end

    properties (Access = private)
        TRIALSInitialized_ (1,1) logical = false % True once TRIALS has been set for the first time on this Runtime instance
        DispatchOrderCache_ = struct('params', {}, 'order', {}) % Per-subject dependency-ordered dispatch permutation; revalidated against the dispatched parameter handles each trial so an operator recompile (which replaces TRIALS.parameters) recomputes it
    end


    methods
        writeParametersJSON(obj, filepath)      % Serialize runtime parameters to a JSON file (legacy phase format).
        writeParametersProtocol(obj, filepath, description) % Save the current session as a protocol (.eprot) phase file.
        P = readParametersJSON(obj, filepath)   % Back-compat wrapper for readParameters.
        P = readParameters(obj, filepath)       % Load a phase file (.eprot/.prot or legacy .json); returns the resolved hw.Parameter array.
        dispatchNextTrial(obj, subjectIdx)      % Dispatch the already selected next trial for one subject.
        resolveTriggerParameters(obj, subjectIdx) % Locate and cache the required trigger parameters (NewTrial, ResetTrig, TrialComplete) for one subject.

        function self = Runtime
            % self = Runtime
            % Construct an empty Runtime container and initialize state.
            vprintf(2, 'Initializing Runtime object')

            % Created here rather than as a property default so the store
            % carries a back-reference to this runtime: that is what lets it
            % stamp a note with the current trial and write it to the session
            % journals without the caller supplying either.
            self.NOTES = epsych.SessionNotes(self);
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
            % What a reused interface must forget between runs -- a counter
            % on the device, an in-memory value -- is cleared by
            % hw.Interface.resetSession at the start of the next run instead.
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
                if p.RunOffline
                    % The operator answered RunExpt's connect-failure prompt by
                    % choosing to run without this backend. It stays in the
                    % array so its parameters remain visible to dispatchNextTrial
                    % and readParameters; its own I/O no-ops while disconnected.
                    vprintf(0,'Hardware interface %s is OFFLINE by operator choice', class(p))
                    p.Runtime = self;
                    continue
                end

                if self.ReviewMode
                    % A review attaches hw.Replay backends, which are never
                    % connected to anything. Announcing a connection here would
                    % put a line in the log that reads exactly like a rig
                    % coming up.
                    vprintf(2,'Attaching replay backend: %s', class(p))
                    p.Runtime = self;
                    continue
                end

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

            % Resolving the required triggers and dispatching the first trial
            % must happen only once per Runtime instance (when TRIALS is first
            % populated by ep_TimerFcn_Start). Later writes, such as
            % updateTrialsFromParameters syncing parameter edits mid-run,
            % must not re-trigger hardware or re-dispatch trials.
            %
            % A review skips it outright. dispatchNextTrial writes every
            % writable parameter through set.Value -- which would clamp,
            % re-evaluate expressions and re-randomize the very values being
            % reviewed -- and fires the ResetTrig/NewTrial triggers, none of
            % which a finished session should be made to do again. The review
            % positions its own trials through epsych.ReviewSession.seek.
            if ~self.TRIALSInitialized_
                if ~self.ReviewMode
                    for i = 1:self.NSubjects
                        self.resolveTriggerParameters(i);
                        self.dispatchNextTrial(i);
                    end
                    self.StartTime = datetime('now');
                end

                % The parameter map is wanted either way -- it is handles, not
                % values, so building it reads no hardware -- and a review
                % keeps the StartTime its snapshot recorded rather than the
                % moment the file was opened.
                self.P = self.all_parameters(asStruct=true);
                self.TRIALSInitialized_ = true;
            end

        end

        function value = get.HELPER(self),       value = self.EVENTS;          end
        function set.HELPER(self, value),        self.EVENTS = value;          end
        function value = get.CORE(self),         value = self.TRIGGERS;        end
        function set.CORE(self, value),          self.TRIGGERS = value;        end
        function value = get.dfltDataPath(self), value = self.DefaultDataPath; end
        function set.dfltDataPath(self, value),  self.DefaultDataPath = value; end

        P = filter_parameters(obj, propertyName, propertyValue, options, poptions) % Return hw.Parameter objects whose named property matches a target value.
        p = find_parameter(obj, name, options)              % Return hw.Parameter handles matching the given name(s), with optional pre-filtering.
        p = all_parameters(obj, options)                % Retrieve all parameters from all registered interfaces, with optional filtering.
        updateTrialsFromParameters(obj, Parameters)     % Sync writable TRIALS fields from current parameter values.
    end

    methods (Static)
        tf = local_test(fcn, val, pat)      % Normalize any comparison result to a logical scalar.
        createTemplateJSON(filepath)        % Write a template JSON file with example hw.Parameter fields to disk.
        [parameters, trials, writeparams, writeParamIdx] = compiledTrialColumns(compiled) % Trial table and the column map that names its columns, from a compiled protocol.
        [paramData, metadata] = phaseParameterData(filepath, options) % Parse a phase file (.eprot/.prot or legacy .json) into uniform parameter structs.
        varargout = phaseCache(action, filepath, entry) % Session-lifetime memo backing phaseParameterData.
    end
end


