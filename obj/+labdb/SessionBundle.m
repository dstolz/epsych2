classdef SessionBundle
    % labdb.SessionBundle
    % b = labdb.SessionBundle.behavior(rec)
    % b = labdb.SessionBundle.weight(subject, grams, when)
    % The lab database's records of what EPsych did, built from EPsych's own
    % plain data and nothing else: a session (epsych.SessionRecord) becomes one
    % behavior event with its data file as the event's output, and a weighing
    % becomes one husbandry event. Both are caraslabdb-bundle/1 records for
    % labclient's outbox, with no dataset folder: they name the subject
    % directly, so any MATLAB on the computer can send them, and a subject the
    % database does not have holds the record until a person assigns it.
    %
    % Headless and static, so the mapping is testable with no server, no
    % Database Toolbox and no outbox.
    %
    % The behavior event's id IS the session's SessionUID. Every copy of the
    % data file carries it (Info.SessionUID), which is what lets a second
    % copier (ephys_analysis's copySessions) find this event instead of making
    % another; labclient's copy rule already matches the file's bytes.
    %
    % See also: labdb.Registry, epsych.SessionRecord, epsych.SubjectRegistry

    properties (Constant)
        TOOL = "epsych"
    end

    methods (Static)
        function b = behavior(rec, s)
            % b = labdb.SessionBundle.behavior(rec)
            % b = labdb.SessionBundle.behavior(rec, settings)
            % The behavior-event record of one subject's session, sealed when
            % its data file could be hashed. Throws labdb:SessionBundle:NoId
            % for a record with no SessionUID (nothing could name it twice).
            arguments
                rec (1,1) struct
                s = labclient.Settings.load()
            end
            if ~labdb.SessionBundle.isUuid(rec.SessionUID)
                error('labdb:SessionBundle:NoId', ...
                    'The session of "%s" has no SessionUID, so it cannot be recorded once.', rec.Subject);
            end
            detail = struct();
            if rec.ProtocolName ~= "", detail.task = char(rec.ProtocolName); end
            paradigm = rec.Paradigm;
            if paradigm == "", paradigm = rec.BehaviorGUI; end
            if paradigm ~= "", detail.paradigm = char(paradigm); end
            detail.trials_completed = double(rec.NumTrials);

            outs = labclient.Bundles.noItems();
            if rec.DataFile ~= "" && isfile(rec.DataFile)
                sha = labclient.fileSha256(rec.DataFile);
                outs = labclient.Bundles.item(rec.DataFile, Role="raw", Kind="epsych", Format="mat", ...
                    ArtifactId=labdb.SessionBundle.derivedId(rec.SessionUID, sha), Sha256=sha);
            end

            b = labclient.Bundles.event(EventId=lower(rec.SessionUID), EventType="behavior", ...
                OccurredAt=labdb.SessionBundle.timeOf(rec.StartTime), Detail=detail, ...
                Attributes=labdb.SessionBundle.attributes(rec), Notes=rec.NotesText, ...
                SubjectId=labdb.SessionBundle.subjectId(rec.RegistryID, rec.Subject), ...
                Performer=labdb.SessionBundle.performer(s), ...
                Outputs=outs, CapturedBy=labclient.Bundles.capturedBy(s));
            b = labclient.Bundles.seal(b);
        end

        function b = weight(subject, grams, when, s)
            % b = labdb.SessionBundle.weight(subject, grams, when)
            % The husbandry-event record of one weighing, in grams.
            arguments
                subject (1,1) struct
                grams (1,1) double {mustBePositive, mustBeFinite}
                when (1,1) datetime
                s = labclient.Settings.load()
            end
            attr = struct('epsych', struct( ...
                'roster_subject_id', string(subject.SubjectID), ...
                'subject_name', string(subject.Name), ...
                'captured_by_tool', labdb.SessionBundle.TOOL));
            b = labclient.Bundles.event(EventId=labclient.Bundles.newId(), EventType="husbandry", ...
                OccurredAt=labdb.SessionBundle.timeOf(when), ...
                Detail=struct('measure', 'weight', 'weight_g', grams), Attributes=attr, ...
                SubjectId=labdb.SessionBundle.subjectId(subject.RegistryID, subject.Name), ...
                Performer=labdb.SessionBundle.performer(s), CapturedBy=labclient.Bundles.capturedBy(s));
            b = labclient.Bundles.seal(b);
        end

        function a = attributes(rec)
            % What the behavior event's attributes say about the session:
            % everything an analysis would need to find and trust the file,
            % beyond the detail columns. Deterministic in REC, so the digest
            % of a record built twice from one session is the same.
            e = struct( ...
                'session_uid', lower(rec.SessionUID), ...
                'subject_name', rec.Subject, ...
                'box_id', rec.BoxID, ...
                'protocol_file', rec.ProtocolFile, ...
                'protocol_version', rec.ProtocolVersion, ...
                'paradigm', rec.Paradigm, ...
                'selector_class', rec.SelectorClass, ...
                'behavior_gui', rec.BehaviorGUI, ...
                'saving_fcn', rec.SavingFcn, ...
                'roster_file', rec.RosterFile, ...
                'roster_subject_id', rec.SubjectID, ...
                'roster_project_id', rec.ProjectID, ...
                'roster_project', rec.Project, ...
                'registry_project_id', rec.ProjectRegistryID, ...
                'ended_at', labdb.SessionBundle.timeOf(rec.EndTime), ...
                'ended_with_error', logical(rec.EndedWithError), ...
                'error_message', rec.ErrorMessage, ...
                'data_file', rec.DataFile, ...
                'data_file_expected', rec.DataFileExpected, ...
                'host', rec.Host, ...
                'os_user', rec.User, ...
                'epsych_version', rec.EPsychVersion, ...
                'epsych_checksum', rec.EPsychChecksum, ...
                'stimgen_checksum', rec.StimgenChecksum, ...
                'problems', {cellstr(rec.Problems)});
            if isnan(e.box_id), e.box_id = []; end
            a = struct('captured_by_tool', labdb.SessionBundle.TOOL, 'epsych', e);
        end

        function id = subjectId(registryId, name)
            % The database subject a record names: the roster's link, else
            % the roster name -- which is the registry id whenever the animal
            % came in through importSubjects, and otherwise holds the record
            % for a person to assign.
            id = strtrim(string(registryId));
            if id == "", id = strtrim(string(name)); end
        end

        function p = performer(s)
            p = struct('person_id', string(s.PersonId), 'person_email', string(s.PersonEmail));
        end

        function t = timeOf(dt)
            % A zoned time as bundle text; an unzoned one is this computer's.
            if isempty(dt) || isnat(dt)
                t = "";
                return
            end
            if isempty(dt.TimeZone), dt.TimeZone = 'local'; end
            t = labclient.Bundles.timeText(dt);
        end

        function id = derivedId(sessionUid, sha)
            % A UUID-shaped id fixed by the session and the file's bytes, so a
            % record rebuilt from the same file names the same artifact.
            h = char(labclient.fileSha256(lower(string(sessionUid)) + "|" + lower(string(sha)), Text=true));
            h(13) = '4';
            h(17) = dec2hex(bitor(bitand(hex2dec(h(17)), 3), 8), 1);
            h = lower(h);
            id = string([h(1:8) '-' h(9:12) '-' h(13:16) '-' h(17:20) '-' h(21:32)]);
        end

        function tf = isUuid(u)
            tf = ~isempty(regexp(char(lower(string(u))), ...
                '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', 'once'));
        end
    end
end
