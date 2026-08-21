classdef SessionNotes < handle
    % epsych.SessionNotes
    % The operator's typed notes for one session, and the one place they live.
    %
    % A note is a line of text stamped with the trial the session was on when
    % it was committed -- trial 0 before the first trial completes -- so that a
    % remark about the animal, the rig, or the room can be lined up with the
    % data afterwards. Notes are session-level by default: one log for the
    % session, written into every subject's data file. A note may instead be
    % tagged with a subject index, in which case only that subject's file
    % carries it, alongside every untagged note.
    %
    % The store is a plain handle object hanging off epsych.Runtime.NOTES, so
    % anything holding the runtime can add one -- a behavior GUI, a paradigm
    % callback, a script:
    %
    %   RUNTIME.NOTES.add('ear plug slipped');
    %
    % gui.Notes is the operator-facing end of it, and several gui.Notes over
    % one store (an embedded one and its pop-out) stay in step through the
    % NotesChanged event.
    %
    % Two things happen to every note as it is committed, and both are why
    % this is a class rather than a cell array inside the GUI:
    %
    %   * epsych.SessionSnapshot.forSubject folds the notes into the Info
    %     variable a saving function already writes, so ep_SaveDataFcn,
    %     cl_SaveDataFcn and any lab's own saving function pick them up with
    %     no edit at all.
    %   * the whole log is appended to each subject's epsych.TrialJournal
    %     under the record name 'notes'. The journal is append-only and its
    %     reader keeps the LAST record of a given name, so rewriting the
    %     entire log per note costs nothing at typing rates and leaves the
    %     newest complete log in the crash-recovery file. A note typed into a
    %     session that then crashes survives.
    %
    % Hand-edited text wins. When an operator turns on gui.Notes's Editable
    % mode and edits the log by hand, setText makes that text authoritative:
    % it is stored verbatim as Text, and Records is re-parsed from it. A line
    % that no longer carries a readable stamp parses with Trial = NaN rather
    % than being dropped, because discarding what an operator deliberately
    % typed is the worse failure.
    %
    % Properties (read-only):
    %   Records  - struct array, one per note: Trial, Time, Elapsed, Subject, Text
    %   Text     - the log as the operator last left it; '' until hand-edited
    %   IsEdited - true once the text has been hand-edited
    %
    % Methods:
    %   add          - Commit one note, stamped with the current trial
    %   setText      - Replace the log with hand-edited text (edited text wins)
    %   clear        - Discard every note
    %   forSubject   - The records that belong in one subject's data file
    %   render       - The log as text lines, in a chosen stamp format
    %   currentTrial - Completed trials, the stamp a new note would carry
    %
    % Events:
    %   NotesChanged - Any add, setText or clear
    %
    % Example:
    %   RUNTIME.NOTES.add('animal off task');
    %   recs = RUNTIME.NOTES.forSubject(1);
    %
    % Documentation: documentation/gui/gui_Notes.md
    % See also: gui.Notes, epsych.SessionSnapshot, epsych.TrialJournal

    properties (SetAccess = private)
        Records   % struct array of notes; see emptyRecords for the fields
        Text (1,:) char = ''            % Hand-edited log text; '' while never edited
        IsEdited (1,1) logical = false  % True once the text has been hand-edited
    end

    properties (Transient)
        % RUNTIME - The session these notes belong to, for the trial number,
        % the elapsed clock, and the journals. A back-reference rather than an
        % argument to add(), so a caller holding only the store still produces
        % correctly stamped notes. Transient because a saved store must not
        % drag a runtime, its hardware, and its timer into a MAT file.
        RUNTIME = []
    end

    properties (Constant)
        % Journal record name. One name, rewritten per note, so the recovery
        % file always holds the whole log rather than fragments to reassemble.
        JOURNAL_RECORD = 'notes'
    end

    events
        NotesChanged  % Fired after any change; listeners re-render
    end

    methods
        function obj = SessionNotes(RUNTIME)
            % obj = epsych.SessionNotes(RUNTIME)
            % Create an empty note store, optionally bound to a runtime.
            arguments
                RUNTIME = []
            end
            obj.RUNTIME = RUNTIME;
            obj.Records = epsych.SessionNotes.emptyRecords();
        end

        function rec = add(obj, text, options)
            % rec = add(obj, text, Subject=, Trial=, Time=)
            % Commit one note and return the record that was stored.
            %
            % Blank text is ignored -- an operator who taps Enter in an empty
            % field meant nothing by it -- and returns an empty record.
            % Multi-line text becomes one record with its newlines flattened
            % to spaces, because a record is one line by contract and a stamp
            % belongs to a line.
            %
            % Parameters:
            %   text    - The note.
            %   Subject - Subject index the note belongs to, or 0 (default)
            %             for the whole session.
            %   Trial   - Override the trial stamp. Default: the current trial.
            %   Time    - Override the wall-clock stamp. Default: now.
            arguments
                obj (1,1) epsych.SessionNotes
                text (1,:) char
                options.Subject (1,1) double {mustBeInteger, mustBeNonnegative} = 0
                options.Trial (1,1) double = NaN
                options.Time (1,1) datetime = datetime('now')
            end

            text = strtrim(regexprep(text, '\s*[\r\n]+\s*', ' '));
            if isempty(text)
                rec = epsych.SessionNotes.emptyRecords();
                return
            end

            trial = options.Trial;
            if isnan(trial)
                trial = obj.currentTrial(options.Subject);
            end

            rec = struct( ...
                'Trial',   trial, ...
                'Time',    options.Time, ...
                'Elapsed', obj.elapsedSeconds_(options.Time), ...
                'Subject', options.Subject, ...
                'Text',    text);

            if isempty(obj.Records)
                obj.Records = rec;
            else
                obj.Records(end+1) = rec;
            end

            % A note added after a hand-edit is appended to the edited text,
            % so the operator's version stays the one on file instead of being
            % silently replaced by a re-render of the records.
            if obj.IsEdited
                obj.Text = strtrim(sprintf('%s\n%s', obj.Text, ...
                    epsych.SessionNotes.formatRecord(rec, "elapsed")));
            end

            obj.changed_();
        end

        function setText(obj, text)
            % setText(obj, text)
            % Replace the log with hand-edited text; that text becomes what is
            % saved, and Records is re-parsed from it.
            %
            % Called by gui.Notes when the operator edits the box in Editable
            % mode. Text identical to what a re-render would produce still
            % marks the log edited: the component cannot tell the difference,
            % and claiming otherwise would be a guess.
            arguments
                obj (1,1) epsych.SessionNotes
                text
            end

            obj.Text = epsych.SessionNotes.joinLines(text);
            obj.IsEdited = true;
            obj.Records = epsych.SessionNotes.parseText(obj.Text);
            obj.changed_();
        end

        function clear(obj)
            % clear(obj)
            % Discard every note, including any hand-edited text.
            obj.Records = epsych.SessionNotes.emptyRecords();
            obj.Text = '';
            obj.IsEdited = false;
            obj.changed_();
        end

        function recs = forSubject(obj, subjectIdx)
            % recs = forSubject(obj, subjectIdx)
            % The records that belong in one subject's data file: the notes
            % tagged with that subject, plus every session-wide (Subject == 0)
            % note. With no index, or 0, every record.
            arguments
                obj (1,1) epsych.SessionNotes
                subjectIdx (1,1) double {mustBeInteger, mustBeNonnegative} = 0
            end

            recs = obj.Records;
            if isempty(recs) || subjectIdx == 0, return; end

            keep = [recs.Subject] == 0 | [recs.Subject] == subjectIdx;
            recs = recs(keep);
        end

        function lines = render(obj, options)
            % lines = render(obj, TimeStamp=, Subject=)
            % The log as a cellstr of lines, one per note.
            %
            % Hand-edited text is returned as it stands -- the operator's
            % version IS the log -- and TimeStamp then describes only how
            % notes added afterwards are stamped.
            %
            % TimeStamp:
            %   "elapsed" - [T042 00:17:05], time since the session started
            %   "clock"   - [T042 09:31:07], wall clock
            %   "none"    - [T042]
            arguments
                obj (1,1) epsych.SessionNotes
                options.TimeStamp (1,1) string {mustBeMember(options.TimeStamp, ...
                    ["elapsed","clock","none"])} = "elapsed"
                options.Subject (1,1) double {mustBeInteger, mustBeNonnegative} = 0
            end

            if obj.IsEdited
                lines = cellstr(strsplit(obj.Text, newline));
                return
            end

            recs = obj.forSubject(options.Subject);
            lines = cell(numel(recs),1);
            for i = 1:numel(recs)
                lines{i} = epsych.SessionNotes.formatRecord(recs(i), options.TimeStamp);
            end
        end

        function n = currentTrial(obj, subjectIdx)
            % n = currentTrial(obj, subjectIdx)
            % Completed trials for one subject or -- for a session-wide note on
            % a multi-box rig -- the furthest along any subject is. Zero before
            % the first trial completes, and zero with no runtime at all, which
            % is what a note typed before a run should say.
            arguments
                obj (1,1) epsych.SessionNotes
                subjectIdx (1,1) double {mustBeInteger, mustBeNonnegative} = 0
            end

            n = 0;
            R = obj.RUNTIME;
            if isempty(R) || ~isvalid(R), return; end

            try
                T = R.TRIALS;
                if isempty(T), return; end
                if subjectIdx > 0 && subjectIdx <= numel(T)
                    n = numel(T(subjectIdx).DATA);
                    return
                end
                for i = 1:numel(T)
                    n = max(n, numel(T(i).DATA));
                end
            catch ME
                vprintf(3, 'epsych.SessionNotes: no trial count available (%s)', ME.message)
            end
        end
    end

    methods (Static)
        function recs = emptyRecords()
            % recs = epsych.SessionNotes.emptyRecords()
            % A 0x0 struct array with the note fields, so a reader can index
            % and concatenate without testing isempty first.
            recs = struct('Trial', {}, 'Time', {}, 'Elapsed', {}, ...
                'Subject', {}, 'Text', {});
        end

        function obj = fromSnapshot(snapshot)
            % obj = epsych.SessionNotes.fromSnapshot(snapshot)
            % The notes a saved session carries, as a store a gui.Notes can
            % display. Used by epsych.ReviewSession, so a reviewed session
            % shows what was typed during it.
            %
            % The store is left unbound to any runtime: a review has no
            % journal to write to and no trial count to stamp with, and
            % gui.Notes refuses new notes in a review anyway.
            %
            % A file that predates notes, or one whose Info is a legacy shape,
            % yields an empty store rather than an error.
            arguments
                snapshot = []
            end

            obj = epsych.SessionNotes();
            if ~isstruct(snapshot) || ~isscalar(snapshot), return; end

            if isfield(snapshot, 'Notes') && isstruct(snapshot.Notes)
                obj.Records = snapshot.Notes;
            end
            if isfield(snapshot, 'NotesText')
                obj.Text = char(string(snapshot.NotesText));
            end
            if isfield(snapshot, 'NotesEdited')
                obj.IsEdited = logical(snapshot.NotesEdited);
            end
        end

        function s = formatRecord(rec, stamp)
            % s = epsych.SessionNotes.formatRecord(rec, stamp)
            % One record as one display line. See render for the formats.
            arguments
                rec (1,1) struct
                stamp (1,1) string = "elapsed"
            end

            if isnan(rec.Trial)
                trialStr = 'T---';
            else
                trialStr = sprintf('T%03d', rec.Trial);
            end

            switch stamp
                case "clock"
                    extra = [' ' char(string(rec.Time, 'HH:mm:ss'))];
                case "elapsed"
                    extra = [' ' epsych.SessionNotes.formatElapsed(rec.Elapsed)];
                otherwise
                    extra = '';
            end

            s = sprintf('[%s%s] %s', trialStr, extra, rec.Text);
        end

        function s = formatElapsed(secs)
            % s = epsych.SessionNotes.formatElapsed(secs)
            % HH:MM:SS since the session started. A note taken before the run
            % has no elapsed time and reads --:--:--, which is the honest
            % answer; 00:00:00 would claim the session had started.
            if isempty(secs) || ~isfinite(secs) || secs < 0
                s = '--:--:--';
                return
            end
            s = char(string(duration(0, 0, secs), 'hh:mm:ss'));
        end

        function txt = joinLines(value)
            % txt = epsych.SessionNotes.joinLines(value)
            % A uitextarea Value (cellstr), string array, or char matrix as one
            % newline-delimited char row.
            if isempty(value)
                txt = '';
                return
            end
            if ischar(value) && size(value,1) <= 1
                txt = value;
                return
            end
            txt = char(strjoin(cellstr(value), newline));
        end

        function recs = parseText(text)
            % recs = epsych.SessionNotes.parseText(text)
            % Re-derive records from hand-edited text. A line whose stamp is
            % gone or unreadable keeps its text with Trial = NaN: what the
            % operator wrote outranks this parser's opinion of it.
            recs = epsych.SessionNotes.emptyRecords();
            text = epsych.SessionNotes.joinLines(text);
            if isempty(strtrim(text)), return; end

            lines = strsplit(text, newline);
            for i = 1:numel(lines)
                ln = strtrim(lines{i});
                if isempty(ln), continue; end

                tok = regexp(ln, '^\[\s*T(\d+)[^\]]*\]\s*(.*)$', 'tokens', 'once');
                if isempty(tok)
                    rec = struct('Trial', NaN, 'Time', NaT, 'Elapsed', NaN, ...
                        'Subject', 0, 'Text', ln);
                else
                    rec = struct('Trial', str2double(tok{1}), 'Time', NaT, ...
                        'Elapsed', NaN, 'Subject', 0, 'Text', strtrim(tok{2}));
                end

                if isempty(recs)
                    recs = rec;
                else
                    recs(end+1) = rec;
                end
            end
        end
    end

    methods (Access = private)
        function changed_(obj)
            obj.journal_();
            notify(obj, 'NotesChanged');
        end

        function journal_(obj)
            % Rewrite the whole log into every subject's journal. Never
            % throws: losing the crash-recovery copy of a note must not take
            % the note, or the run, with it.
            R = obj.RUNTIME;
            if isempty(R) || ~isvalid(R) || isempty(R.Journal), return; end

            for i = 1:numel(R.Journal)
                try
                    J = R.Journal(i);
                    if ~isvalid(J) || strlength(J.FilePath) == 0, continue; end
                    J.append(epsych.SessionNotes.JOURNAL_RECORD, struct( ...
                        'Records',  obj.forSubject(i), ...
                        'Text',     obj.Text, ...
                        'IsEdited', obj.IsEdited));
                catch ME
                    vprintf(2, 'epsych.SessionNotes: could not journal notes for subject %d (%s)', ...
                        i, ME.message)
                end
            end
        end

        function s = elapsedSeconds_(obj, when)
            % Seconds since the session started; NaN before it has.
            s = NaN;
            R = obj.RUNTIME;
            if isempty(R) || ~isvalid(R), return; end
            try
                t0 = R.StartTime;
                if isempty(t0) || all(isnat(t0)), return; end
                s = seconds(when - t0(1));
            catch ME
                vprintf(3, 'epsych.SessionNotes: no session start time (%s)', ME.message)
            end
        end
    end
end
