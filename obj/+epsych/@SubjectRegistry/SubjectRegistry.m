classdef SubjectRegistry < handle
    % epsych.SubjectRegistry
    % r = epsych.SubjectRegistry.current()
    % The seam between EPsych and a lab's subject registry -- the database
    % that owns each animal's identity (sex, species, birth, endpoint) and
    % keeps the lab's record of what was done to it.
    %
    % EPsych needs no registry. This class IS the "none" registry: every method
    % is a no-op or returns an empty answer, and current() hands it out until
    % the machine is configured otherwise (preference EPsych/SubjectRegistry
    % naming an adapter class). A fresh installation therefore runs exactly as
    % it would with no seam at all: no preference is read into existence
    % (ispref before getpref), nothing outside this repository is loaded, and
    % every surface that shows registry state asks isEnabled first and stays
    % hidden.
    %
    % An ADAPTER subclasses this and overrides what it supports. The rules an
    % adapter must keep, because EPsych calls it from places where a failure
    % or a wait would cost an experiment:
    %   - nothing it does may wait on a network during a run: sessionRunning
    %     (true) arrives when the trial loop starts and (false) once the
    %     session's data is saved; between them EPsych calls only
    %     sessionRunning, and the adapter must not send in the background;
    %   - sessionSaved and weightMeasured RECORD locally and return -- sending
    %     is the adapter's business, later, and a record that cannot be sent
    %     waits rather than failing;
    %   - subjectStatus answers from what the adapter already holds (a cache,
    %     with its AsOf time), never from the network; refreshStatus is the one
    %     call allowed to go and look, and EPsych never makes it during a run;
    %   - none of it throws. The static notify* wrappers below catch anyway,
    %     so a broken adapter costs a log line, never a session.
    % A method added here later must be concrete with a safe default, or every
    % existing adapter becomes unconstructable (the stimbridge rule).
    %
    % Methods (instance; the defaults below are the "none" registry's):
    %   tf  = isEnabled()                 - false
    %   s   = label()                     - "none"; e.g. "Lab DB"
    %   st  = status()                    - State "off", Message, Pending, NeedYou
    %   sessionRunning(tf)                - suspend (true) / resume (false) sending
    %   sessionSaved(records)             - epsych.SessionRecord array, after a save
    %   weightMeasured(subject, grams, when) - a weighing (subject: roster record)
    %   T   = subjectStatus(registryIds)  - cached status, one row per id
    %   T   = findSubjects(filter)        - registry animals (filter: struct)
    %   T   = projects()                  - registry projects/studies
    %   rep = refreshStatus(registryIds)  - refresh the cache (may contact the server)
    %   W   = sessionWarnings(subjects)   - endpoint / low-weight warnings
    %   openSettings()                    - the adapter's settings window
    %
    % Static:
    %   r = current(Use=, Reset=)         - this MATLAB's registry
    %   cls = configuredClass(), setConfiguredClass(cls)
    %   A = availableAdapters()           - for the Customize dialog
    %   notifySessionRunning(tf), notifySessionSaved(RUNTIME, CONFIG, FUNCS),
    %   notifyWeight(subject, grams, when) - never-throwing calls for core code
    %   T = emptyStatus(ids), emptySubjects(), emptyProjects()
    %
    % See also: documentation/epsych/epsych_SubjectRegistry.md,
    %   epsych.SessionRecord, epsych.SubjectRoster.importSubjects

    properties (Constant)
        PREF_GROUP = 'EPsych'
        PREF_NAME  = 'SubjectRegistry'

        % Adapters this repository ships. An adapter is offered only when its
        % own dependencies are present (its static isAvailable).
        KNOWN_ADAPTERS = {'labdb.Registry'}

        % Below this percentage of an animal's baseline weight, sessionWarnings
        % warns (the lab database's own default for the same check).
        LOW_WEIGHT_PERCENT = 85
    end

    % ------------------------------------------------------------------
    methods
        function tf = isEnabled(~)
            tf = false;
        end

        function s = label(~)
            s = "none";
        end

        function st = status(~)
            st = epsych.SubjectRegistry.blankStatus();
        end

        function sessionRunning(~, ~)
        end

        function sessionSaved(~, ~)
        end

        function weightMeasured(~, ~, ~, ~)
        end

        function T = subjectStatus(~, registryIds)
            T = epsych.SubjectRegistry.emptyStatus(registryIds);
        end

        function T = findSubjects(~, ~)
            T = epsych.SubjectRegistry.emptySubjects();
        end

        function T = projects(~)
            T = epsych.SubjectRegistry.emptyProjects();
        end

        function rep = refreshStatus(~, ~)
            rep = struct('OK', false, 'Message', "No subject registry is set up on this computer.");
        end

        function openSettings(~)
        end

        function W = sessionWarnings(obj, subjects)
            % W = sessionWarnings(obj, subjects)
            % What the registry knows that should make an operator think twice
            % before running these animals: an endpoint recorded, or a weight
            % under LOW_WEIGHT_PERCENT of baseline. From subjectStatus only --
            % the cache -- so it costs no network and works offline, saying how
            % old its knowledge is.
            %
            % Parameters:
            %   subjects - roster subject records (Name, RegistryID).
            % Returns:
            %   W - struct array: Name, RegistryID, Kind ("endpoint" |
            %       "low_weight"), Message, AsOf.
            W = struct('Name', {}, 'RegistryID', {}, 'Kind', {}, 'Message', {}, 'AsOf', {});
            if isempty(subjects) || ~obj.isEnabled(), return, end
            ids = string({subjects.RegistryID});
            linked = ids ~= "";
            if ~any(linked), return, end
            T = obj.subjectStatus(ids(linked));
            names = string({subjects(linked).Name});
            for k = 1:height(T)
                asOf = T.AsOf(k);
                when = "";
                if ~isnat(asOf), when = " (as of " + string(asOf, 'yyyy-MM-dd HH:mm') + ")"; end
                if T.Endpointed(k)
                    at = "";
                    if ~isnat(T.EndpointAt(k)), at = " on " + string(T.EndpointAt(k), 'yyyy-MM-dd'); end
                    W(end+1) = struct('Name', names(k), 'RegistryID', T.RegistryID(k), ...
                        'Kind', "endpoint", 'AsOf', asOf, 'Message', ...
                        names(k) + " (" + T.RegistryID(k) + ") has an endpoint recorded" + at + ...
                        " in the " + obj.label() + when + ".");
                end
                w = T.WeightG(k);
                b = T.BaselineG(k);
                if isfinite(w) && isfinite(b) && b > 0 && 100 * w / b < epsych.SubjectRegistry.LOW_WEIGHT_PERCENT
                    W(end+1) = struct('Name', names(k), 'RegistryID', T.RegistryID(k), ...
                        'Kind', "low_weight", 'AsOf', asOf, 'Message', sprintf( ...
                        '%s (%s) weighed %.1f g, %.0f%% of its %.1f g baseline%s.', ...
                        names(k), T.RegistryID(k), w, 100 * w / b, b, when));
                end
            end
        end
    end

    % ------------------------------------------------------------------
    methods (Static)
        function r = current(options)
            % r = epsych.SubjectRegistry.current()
            % r = epsych.SubjectRegistry.current(Reset=true)   % re-read the preference
            % r = epsych.SubjectRegistry.current(Use=reg)      % tests: use REG until Reset
            % This MATLAB's registry: the configured adapter, or the "none"
            % registry when there is none, it is missing, or it will not
            % construct (said once in the log). Never throws.
            arguments
                options.Use = []
                options.Reset (1,1) logical = false
            end
            persistent cached cachedClass injected
            if options.Reset
                cached = [];
                cachedClass = '';
                injected = [];
            end
            if ~isempty(options.Use)
                injected = options.Use;
            end
            if ~isempty(injected) && isvalid(injected)
                r = injected;
                return
            end
            cls = epsych.SubjectRegistry.configuredClass();
            if ~isempty(cached) && isvalid(cached) && strcmp(cachedClass, cls)
                r = cached;
                return
            end
            r = epsych.SubjectRegistry.make_(cls);
            cached = r;
            cachedClass = cls;
        end

        function cls = configuredClass()
            % The adapter class this computer is set to use, '' for none.
            cls = '';
            try
                if ispref(epsych.SubjectRegistry.PREF_GROUP, epsych.SubjectRegistry.PREF_NAME)
                    cls = char(string(getpref(epsych.SubjectRegistry.PREF_GROUP, ...
                        epsych.SubjectRegistry.PREF_NAME)));
                end
            catch ME
                vprintf(0, 1, ME)
            end
        end

        function setConfiguredClass(cls)
            % setConfiguredClass(cls)   % '' turns the registry off
            % Choose this computer's registry adapter. Refuses a class that is
            % not an available epsych.SubjectRegistry adapter.
            arguments
                cls (1,:) char
            end
            g = epsych.SubjectRegistry.PREF_GROUP;
            n = epsych.SubjectRegistry.PREF_NAME;
            if isempty(cls)
                if ispref(g, n), rmpref(g, n); end
                vprintf(1, 'Subject registry turned off on this computer.');
            else
                if exist(cls, 'class') ~= 8 || ~ismember('epsych.SubjectRegistry', superclasses(cls))
                    error('epsych:SubjectRegistry:NotAnAdapter', ...
                        '"%s" is not an epsych.SubjectRegistry adapter on the MATLAB path.', cls);
                end
                setpref(g, n, cls);
                vprintf(1, 'Subject registry set to %s on this computer.', cls);
            end
            epsych.SubjectRegistry.current(Reset=true);
        end

        function A = availableAdapters()
            % A = epsych.SubjectRegistry.availableAdapters()
            % Every adapter this repository ships: Class, Label, Available
            % (its dependencies are present), Why (when not).
            A = struct('Class', {}, 'Label', {}, 'Available', {}, 'Why', {});
            for k = 1:numel(epsych.SubjectRegistry.KNOWN_ADAPTERS)
                cls = epsych.SubjectRegistry.KNOWN_ADAPTERS{k};
                a = struct('Class', string(cls), 'Label', string(cls), 'Available', false, 'Why', "");
                try
                    if exist(cls, 'class') ~= 8
                        a.Why = "not on the MATLAB path";
                    else
                        a.Label = string(feval([cls '.adapterLabel']));
                        [a.Available, a.Why] = feval([cls '.isAvailable']);
                        a.Why = string(a.Why);
                    end
                catch ME
                    a.Why = string(ME.message);
                end
                A(end+1) = a;
            end
        end

        function notifySessionRunning(tf)
            % Tell the registry a run started (true) or its data is saved (false).
            try
                r = epsych.SubjectRegistry.current();
                if r.isEnabled()
                    r.sessionRunning(logical(tf));
                end
            catch ME
                vprintf(0, 1, ME)
            end
        end

        function notifySessionSaved(RUNTIME, CONFIG, FUNCS)
            % Hand the registry a record of each subject's session, after the
            % saving function returned. Built only when a registry is set up;
            % a Preview is never recorded.
            arguments
                RUNTIME
                CONFIG
                FUNCS = struct()
            end
            try
                r = epsych.SubjectRegistry.current();
                if ~r.isEnabled() || RUNTIME.isTest || isempty(RUNTIME.TRIALS), return, end
                n = numel(RUNTIME.TRIALS);
                recs = repmat(epsych.SessionRecord.blank(), 1, n);
                for i = 1:n
                    recs(i) = epsych.SessionRecord.fromRun(RUNTIME, CONFIG, i, FUNCS=FUNCS);
                end
                r.sessionSaved(recs);
            catch ME
                vprintf(0, 1, ME)
            end
        end

        function notifyWeight(subject, grams, when)
            % Tell the registry an animal was weighed. SUBJECT is a roster
            % subject record (Name, RegistryID, SubjectID).
            try
                r = epsych.SubjectRegistry.current();
                if r.isEnabled()
                    r.weightMeasured(subject, double(grams), when);
                end
            catch ME
                vprintf(0, 1, ME)
            end
        end

        function st = blankStatus()
            % State: "off" | "connected" | "offline" | "attention".
            st = struct('State', "off", 'Message', "", 'Pending', 0, 'NeedYou', 0);
        end

        function T = emptyStatus(registryIds)
            % One row per id, nothing known: the "none" registry's answer, and
            % the shape every adapter's subjectStatus returns.
            if nargin < 1, registryIds = strings(0, 1); end
            ids = reshape(string(registryIds), [], 1);
            n = numel(ids);
            T = table(ids, false(n, 1), false(n, 1), NaT(n, 1, 'TimeZone', 'local'), ...
                NaN(n, 1), NaT(n, 1, 'TimeZone', 'local'), NaN(n, 1), NaT(n, 1, 'TimeZone', 'local'), ...
                'VariableNames', {'RegistryID', 'Known', 'Endpointed', 'EndpointAt', ...
                'WeightG', 'WeightAt', 'BaselineG', 'AsOf'});
        end

        function T = emptySubjects()
            % The shape of findSubjects: table2struct of it feeds
            % epsych.SubjectRoster.importSubjects.
            T = table(strings(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), ...
                strings(0, 1), NaT(0, 1), false(0, 1), ...
                'VariableNames', {'RegistryID', 'Project', 'ProjectRegistryID', 'Sex', ...
                'Species', 'DateOfBirth', 'Endpointed'});
        end

        function T = emptyProjects()
            T = table(strings(0, 1), strings(0, 1), false(0, 1), ...
                'VariableNames', {'RegistryID', 'Name', 'IsActive'});
        end
    end

    methods (Static, Access = private)
        function r = make_(cls)
            r = epsych.SubjectRegistry();
            if isempty(cls), return, end
            try
                if exist(cls, 'class') ~= 8
                    vprintf(0, 1, ['The subject registry "%s" set on this computer is not ' ...
                        'on the MATLAB path; continuing without one.'], cls);
                    return
                end
                candidate = feval(cls);
                if ~isa(candidate, 'epsych.SubjectRegistry')
                    vprintf(0, 1, '"%s" is not an epsych.SubjectRegistry; continuing without one.', cls);
                    return
                end
                r = candidate;
            catch ME
                vprintf(0, 1, ME)
                vprintf(0, 1, 'The subject registry "%s" could not start; continuing without one.', cls);
            end
        end
    end
end
