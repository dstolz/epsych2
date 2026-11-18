classdef Registry < epsych.SubjectRegistry
    % labdb.Registry
    % The Caras lab's CarasLabDB as EPsych's subject registry
    % (epsych.SubjectRegistry), over the shared client package labclient that
    % ships with CarasLabDB.
    %
    % Optional twice over: EPsych never needs it, and it switches itself off
    % (isAvailable false, so the Customize dialog does not offer it) unless
    % the CarasLabDB checkout -- its @CarasLabDB class and +labclient package
    % -- is on the MATLAB path, with a labclient recent enough for what this
    % adapter calls (CLIENT_VERSION against labclient.Api.Version; an older
    % checkout is said to need updating, in the log). Turn it on with
    % labdb.Registry.enable() or RunExpt > Customize > Subject Registry.
    %
    % It records through labclient, which every toolbox on the computer shares:
    % one settings struct (server, login, storage roots), one password in the
    % MATLAB vault, one outbox, one sender. Set those up once in labclient's
    % Database window (openSettings, or the lamp in Subjects & Projects).
    %
    % What it records:
    %   - a session, as a behavior event whose id is the session's SessionUID,
    %     with the saved data file as its output (labdb.SessionBundle);
    %   - a weighing typed into the roster, as a husbandry event. A second
    %     weighing of the same animal the same day, while the first is still
    %     waiting to be sent, REPLACES it -- a typo fix is not a second
    %     weighing.
    % A session saved again (RunExpt's Save Data) replaces its record while it
    % waits; once sent, the new bytes are registered as replacing the old file.
    %
    % It never waits on the network during a run: sessionRunning(true)
    % suspends labclient's sender until sessionRunning(false). Reads
    % (subjectStatus) come from labclient.SubjectCache; refreshStatus and
    % findSubjects without CacheOnly may contact the server, bounded by its
    % ConnectTimeout, and EPsych never calls them during a run.
    %
    % See also: documentation/labdb/labdb_Registry.md, epsych.SubjectRegistry,
    %   labdb.SessionBundle

    properties (Constant)
        REQUIRED_CLASSES = ["CarasLabDB" "labclient.Settings" "labclient.Bundles" ...
            "labclient.Outbox" "labclient.Sync" "labclient.DB" "labclient.SubjectCache"]
        % The version of labclient's interface this adapter is written for
        % (labclient.Api.Version). From 3 a session saved a third time
        % replaces the SECOND file: the adapter names the first file at every
        % save, and an older labclient left the second marked present.
        CLIENT_VERSION = 3
    end

    properties (Access = private)
        Suspension_ = []                % labclient.Sync.suspend() handle while a run is on
        Weighings_                      % containers.Map: subject|yyyy-MM-dd -> pending event id
    end

    methods (Static)
        function s = adapterLabel()
            s = "Lab DB (CarasLabDB)";
        end

        function [ok, why] = isAvailable()
            % [ok, why] = labdb.Registry.isAvailable()
            % Whether this computer has what the adapter needs on the path: the
            % CarasLabDB checkout, and one whose labclient package is recent
            % enough (CLIENT_VERSION). WHY says what to do when it has not.
            missing = labdb.Registry.REQUIRED_CLASSES(arrayfun(@(c) exist(c, 'class') ~= 8, ...
                labdb.Registry.REQUIRED_CLASSES));
            ok = isempty(missing);
            why = "";
            if ~ok
                why = "add the CarasLabDB checkout to the MATLAB path (missing " + ...
                    strjoin(missing, ", ") + ")";
                return
            end
            % A checkout from before labclient.Api has no version to ask for,
            % and is older than any this adapter can use.
            needed = labdb.Registry.CLIENT_VERSION;
            if exist('labclient.Api', 'class') ~= 8
                ok = false;
                why = sprintf("update the CarasLabDB checkout (git pull): its labclient package is from " + ...
                    "before version %d of its interface, which this adapter needs", needed);
            elseif labclient.Api.Version < needed
                ok = false;
                why = sprintf("update the CarasLabDB checkout (git pull): its labclient package is version " + ...
                    "%d of its interface, and this adapter needs %d", labclient.Api.Version, needed);
            end
        end

        function enable()
            % Use the lab database as this computer's subject registry.
            epsych.SubjectRegistry.setConfiguredClass('labdb.Registry');
        end

        function disable()
            epsych.SubjectRegistry.setConfiguredClass('');
        end
    end

    methods
        function obj = Registry()
            [ok, why] = labdb.Registry.isAvailable();
            if ~ok
                error('labdb:Registry:Unavailable', 'The lab database cannot be used here: %s.', why);
            end
            obj.Weighings_ = containers.Map('KeyType', 'char', 'ValueType', 'char');
            % The shared sender: started once per MATLAB, only when the lab
            % database is turned on in labclient's settings.
            try
                labclient.Sync.start(IfEnabled=true);
            catch ME
                vprintf(0, 1, ME);
            end
        end

        function delete(obj)
            obj.Suspension_ = [];
        end

        function tf = isEnabled(~)
            tf = true;
        end

        function s = label(~)
            s = "Lab DB";
        end

        function st = status(~)
            st = epsych.SubjectRegistry.blankStatus();
            try
                d = labclient.DB.status();
                st.State = string(d.State);
                st.Message = string(d.Message);
            catch ME
                st.State = "attention";
                st.Message = string(ME.message);
            end
            try
                c = labclient.Outbox.counts();
                st.Pending = double(c.pending);
                st.NeedYou = double(c.held) + double(c.failed);
            catch ME
                vprintf(2, 'labdb.Registry: outbox counts unavailable (%s)', ME.message);
            end
        end

        function sessionRunning(obj, tf)
            if tf
                if isempty(obj.Suspension_)
                    obj.Suspension_ = labclient.Sync.suspend();
                end
            else
                obj.Suspension_ = [];   % clearing the handle resumes the sender
            end
        end

        function sessionSaved(obj, records)
            if ~labdb.Registry.recordingOn_(), return, end
            s = labclient.Settings.load();
            for i = 1:numel(records)
                rec = records(i);
                try
                    obj.recordSession_(rec, s);
                catch ME
                    vprintf(0, 1, ME);
                    vprintf(0, 1, 'The session of "%s" could not be recorded for the lab database.', rec.Subject);
                end
            end
        end

        function weightMeasured(obj, subject, grams, when)
            if ~labdb.Registry.recordingOn_() || ~(isfinite(grams) && grams > 0), return, end
            s = labclient.Settings.load();
            b = labdb.SessionBundle.weight(subject, grams, when, s);
            if isempty(when.TimeZone), when.TimeZone = 'local'; end
            key = sprintf('%s|%s', labdb.SessionBundle.subjectId(subject.RegistryID, subject.Name), ...
                char(string(when, 'yyyy-MM-dd')));
            % The same animal again the same day, its first weighing still
            % waiting: a correction, so it takes the first one's place.
            if obj.Weighings_.isKey(key)
                prior = string(obj.Weighings_(key));
                if labdb.Registry.isWaiting_(prior)
                    b = labdb.Registry.withId_(b, prior);
                end
            end
            labclient.Outbox.put(b);
            obj.Weighings_(key) = char(b.bundle_id);
            vprintf(1, 'Weighing of %s (%.1f g) kept for the lab database.', subject.Name, grams);
        end

        function T = subjectStatus(~, registryIds)
            T = epsych.SubjectRegistry.emptyStatus(registryIds);
            if isempty(registryIds), return, end
            C = labclient.SubjectCache.status(reshape(string(registryIds), [], 1));
            T.Known = logical(C.known);
            T.Endpointed = logical(C.is_endpointed);
            T.EndpointAt = labdb.Registry.zoned_(C.endpoint_at);
            T.WeightG = double(C.latest_weight_g);
            T.WeightAt = labdb.Registry.zoned_(C.latest_weight_at);
            T.BaselineG = double(C.baseline_weight_g);
            T.AsOf = labdb.Registry.zoned_(C.as_of);
        end

        function T = findSubjects(~, filter)
            T = epsych.SubjectRegistry.emptySubjects();
            if nargin < 2 || ~isstruct(filter), filter = struct(); end
            cacheOnly = isfield(filter, 'CacheOnly') && logical(filter.CacheOnly);
            b = [];
            if ~cacheOnly
                b = labclient.DB.connect();
            end
            if isempty(b)
                return
            end
            f = struct();
            if isfield(filter, 'Project') && strlength(filter.Project) > 0
                f.ProjectId = string(filter.Project);
            end
            S = b.subjects(f);
            if height(S) == 0, return, end
            P = b.projects();
            names = strings(height(S), 1);
            for k = 1:height(S)
                hit = string(P.project_id) == string(S.project_id(k));
                if any(hit), names(k) = string(P.name(find(hit, 1))); end
            end
            species = labdb.Registry.speciesNames_(b, string(S.species_code));
            endp = false(height(S), 1);
            try
                C = labclient.SubjectCache.status(reshape(string(S.subject_id), [], 1));
                endp = logical(C.is_endpointed);
            catch ME
                vprintf(2, 'labdb.Registry: no cached endpoints (%s)', ME.message);
            end
            % lab.subject has date_of_birth; a backend that leaves it out
            % (an older client, the test fake) means "not known".
            dob = NaT(height(S), 1);
            if ismember('date_of_birth', S.Properties.VariableNames)
                dob = labdb.Registry.dateOf_(S.date_of_birth);
            end
            T = table(string(S.subject_id), names, string(S.project_id), ...
                labdb.Registry.sexWord_(string(S.sex)), species, dob, endp, ...
                'VariableNames', epsych.SubjectRegistry.emptySubjects().Properties.VariableNames);
        end

        function T = projects(~)
            T = epsych.SubjectRegistry.emptyProjects();
            b = labclient.DB.connect();
            if isempty(b), return, end
            P = b.projects();
            if height(P) == 0, return, end
            active = true(height(P), 1);
            if ismember('is_active', P.Properties.VariableNames)
                active = logical(P.is_active);
            end
            T = table(string(P.project_id), string(P.name), active, ...
                'VariableNames', {'RegistryID', 'Name', 'IsActive'});
        end

        function rep = refreshStatus(~, registryIds)
            rep = struct('OK', false, 'Message', "");
            try
                r = labclient.SubjectCache.refresh(reshape(string(registryIds), [], 1), Budget=10);
                rep.OK = logical(r.Connected);
                rep.Message = string(r.Message);
                if rep.OK && rep.Message == ""
                    rep.Message = sprintf("Read %d subject(s) from the lab database", r.Refreshed);
                    if ~isempty(r.NotFound)
                        rep.Message = rep.Message + sprintf("; not in it: %s", strjoin(r.NotFound, ", "));
                    end
                    rep.Message = rep.Message + ".";
                end
            catch ME
                rep.Message = "The lab database could not be read: " + string(ME.message);
            end
        end

        function openSettings(~)
            labclient.Panel.open();
        end
    end

    methods (Access = private)
        function recordSession_(obj, rec, s)
            % A record being sent this moment (by another MATLAB) cannot be
            % replaced; it will be "done" in a moment, and then the new bytes
            % go as a replacing file. A few short tries settle it.
            for attempt = 1:5
                try
                    obj.recordSessionOnce_(rec, s);
                    return
                catch ME
                    if ~strcmp(ME.identifier, 'labclient:Outbox:Claimed') || attempt == 5
                        rethrow(ME);
                    end
                    pause(0.4);
                end
            end
        end

        function recordSessionOnce_(~, rec, s)
            b = labdb.SessionBundle.behavior(rec, s);
            id = string(b.bundle_id);
            [prior, state] = labclient.Outbox.read(id);
            if state == "" || state ~= "done"
                % Not sent yet (or never kept): this capture is the record.
                labclient.Outbox.put(b);
                vprintf(1, 'Session of %s kept for the lab database (%s).', rec.Subject, id);
                return
            end
            % Sent already, and saved again since: the new bytes are a file of
            % that event, replacing the one it was sent with.
            newOut = b.record.outputs;
            oldOut = prior.record.outputs;
            if isempty(newOut), return, end
            if ~isempty(oldOut) && string(oldOut(1).sha256) == string(newOut(1).sha256)
                return   % same bytes: nothing new to say
            end
            item = newOut(1);
            if ~isempty(oldOut)
                item.replaces = string(oldOut(1).artifact_id);
            end
            labclient.Outbox.put(labclient.Bundles.files(EventId=id, Artifacts=item, ...
                CapturedBy=labclient.Bundles.capturedBy(s)));
            vprintf(1, 'Session of %s saved again: the new file is kept for the lab database.', rec.Subject);
        end
    end

    methods (Static, Access = private)
        function tf = recordingOn_()
            % Records are kept only while the lab database is turned on in
            % labclient's settings (as ephys_analysis does); the lamp then
            % reads "off" and the settings window turns it on.
            tf = false;
            try
                tf = logical(labclient.Settings.load().Enabled);
            catch ME
                vprintf(0, 1, ME);
            end
            if ~tf
                vprintf(2, 'labdb.Registry: the lab database is turned off on this computer; nothing recorded.');
            end
        end

        function tf = isWaiting_(id)
            tf = false;
            try
                [~, state] = labclient.Outbox.read(id);
                tf = any(state == ["pending" "held" "failed"]);
            catch
            end
        end

        function b = withId_(b, id)
            b.bundle_id = id;
            b.record.event.event_id = id;
            b = labclient.Bundles.seal(b);
        end

        function t = zoned_(v)
            % Cache times arrive as zoned text, datetime, or missing.
            n = numel(v);
            t = NaT(n, 1, 'TimeZone', 'local');
            for k = 1:n
                try
                    x = v(k);
                    if iscell(x), x = x{1}; end
                    if isdatetime(x)
                        if ~isnat(x)
                            if isempty(x.TimeZone), x.TimeZone = 'local'; end
                            t(k) = x;
                        end
                    elseif (ischar(x) || isstring(x)) && strlength(string(x)) > 0 && ~ismissing(string(x))
                        t(k) = datetime(string(x), 'InputFormat', "yyyy-MM-dd'T'HH:mm:ss.SSSSSSxxx", ...
                            'TimeZone', 'local');
                    end
                catch
                end
            end
        end

        function d = dateOf_(v)
            d = NaT(numel(v), 1);
            for k = 1:numel(v)
                try
                    x = v(k);
                    if iscell(x), x = x{1}; end
                    if isdatetime(x)
                        d(k) = x;
                    elseif strlength(string(x)) > 0 && ~ismissing(string(x))
                        d(k) = datetime(string(x), 'InputFormat', 'yyyy-MM-dd');
                    end
                catch
                end
            end
        end

        function w = sexWord_(c)
            % The database's M/F/U as the roster spells them (epsych.DefaultSubject).
            w = strings(numel(c), 1);
            w(c == "M") = "Male";
            w(c == "F") = "Female";
            w(c == "U") = "Unknown";
        end

        function n = speciesNames_(b, codes)
            n = codes;
            try
                Sp = b.species();
                for k = 1:numel(codes)
                    hit = string(Sp.code) == codes(k);
                    if any(hit), n(k) = string(Sp.common_name(find(hit, 1))); end
                end
            catch
            end
            n(ismissing(n)) = "";
        end
    end
end
