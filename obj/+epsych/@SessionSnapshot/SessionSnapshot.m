classdef SessionSnapshot
    % epsych.SessionSnapshot
    % The description of a session that a saved data file has to carry for the
    % session to be reviewable later.
    %
    % A saved .mat holds Data -- one struct per trial, fields named after the
    % parameters that were recorded. That is enough to re-plot behaviour, and
    % the examples/*/explore_*_data.m scripts do exactly that. It is not enough
    % to reopen the paradigm's own behavior GUI, because a build() method asks
    % for parameters by name and nothing in Data says what those parameters
    % were: their type, units, bounds, design-time levels, or which module they
    % belonged to. Neither is the compiled trial table there, so nothing can say
    % what the next trial WOULD have been.
    %
    % This class produces that description as a plain struct -- no handles, no
    % hardware, nothing that needs a live session to load -- so that any saving
    % function can write it alongside Data with one line:
    %
    %   Info = RUNTIME.TRIALS(i).SessionInfo;   % captured at session start
    %   save(fileloc, 'Data', 'Info')
    %
    % or, for a save function that would rather build it itself:
    %
    %   Info = epsych.SessionSnapshot.capture(RUNTIME, i);
    %
    % ep_TimerFcn_Start captures it once per subject and puts it BOTH on the
    % runtime and into the crash-recovery file's info record, so a session that
    % ended in a crash and was rebuilt by epsych.TrialJournal.recover is just as
    % reviewable as one that saved normally.
    %
    % Reading it back goes through fromInfo, which also accepts the two shapes
    % that predate this class -- a flat EPsychInfo.meta struct (what
    % cl_SaveDataFcn used to write as Info) and no Info at all -- and reports
    % what it could not supply rather than guessing.
    %
    % Methods
    %   forSubject - The snapshot a saving function should write. Use this one.
    %   capture    - Build the snapshot for one subject of a live runtime.
    %   fromInfo   - Normalize whatever a file carries as Info into a snapshot.
    %   isSnapshot - Whether a struct is a snapshot rather than legacy metadata.
    %
    % Documentation: documentation/epsych/epsych_ReviewSession.md
    % See also: epsych.ReviewSession, hw.Replay, epsych.TrialJournal

    properties (Constant)
        % Bumped only when an existing field changes meaning. Adding a field is
        % additive: fromInfo fills in what an older file does not carry, so a
        % reader must treat every absent field as "this session did not record
        % it" rather than as a corrupt file.
        FORMAT_VERSION = 1
    end

    methods (Access = private)
        function obj = SessionSnapshot()
            % Not constructible: this is a namespace for two static functions
            % over plain structs. A snapshot has to survive save/load on a
            % machine that may not have this class, so it is never an object.
        end
    end

    methods (Static)
        S = capture(RUNTIME, subjectIdx, trialsStruct) % Build the snapshot for one subject of a live runtime.
        S = fromInfo(info)                % Normalize a file's Info variable into a snapshot struct.

        function S = forSubject(RUNTIME, subjectIdx)
            % S = epsych.SessionSnapshot.forSubject(RUNTIME, subjectIdx)
            % The snapshot a saving function should write. One line, no
            % failure mode:
            %
            %   Data = RUNTIME.TRIALS(i).DATA;
            %   Info = epsych.SessionSnapshot.forSubject(RUNTIME, i);
            %   save(fileloc, 'Data', 'Info')
            %
            % Normally this is a field read -- ep_TimerFcn_Start captured the
            % snapshot at session start, which is what makes the crash-recovery
            % file reviewable too. A scripted session that filled TRIALS itself,
            % or one started by a custom Start function predating the snapshot,
            % has none, and is described from the runtime as it stands now.
            %
            % It never throws. A file with no usable Info reviews as a legacy
            % file, which is what it is; losing the session over describing it
            % would be the worse trade.
            arguments
                RUNTIME (1,1) epsych.Runtime
                subjectIdx (1,1) double {mustBeInteger,mustBePositive} = 1
            end

            try
                T = RUNTIME.TRIALS(subjectIdx);
                if isfield(T, 'SessionInfo') && ~isempty(T.SessionInfo)
                    S = T.SessionInfo;
                else
                    S = epsych.SessionSnapshot.capture(RUNTIME, subjectIdx);
                end

                % Notes are the one part of the snapshot that cannot be
                % captured at session start: they are typed DURING the run.
                % Folding them in here is what puts them in every saving
                % function's Info without any of them being edited.
                S = epsych.SessionSnapshot.withNotes(S, RUNTIME, subjectIdx);
                return
            catch ME
                vprintf(0, 1, ME)
                vprintf(0, 1, ['epsych.SessionSnapshot: could not describe this session; ' ...
                    'the data still saves, but it will review without parameter controls'])
                S = epsych.SessionSnapshot.fromInfo([]);
            end
        end

        function S = withNotes(S, RUNTIME, subjectIdx)
            % S = epsych.SessionSnapshot.withNotes(S, RUNTIME, subjectIdx)
            % Fold this session's operator notes into a snapshot.
            %
            % Separate from capture() because the notes are the one thing a
            % start-of-session snapshot cannot hold: they are typed while the
            % session runs. forSubject calls this at save time; a custom
            % saving function that builds its own snapshot with capture()
            % should call it too.
            %
            % Three fields go in, and which is authoritative depends on what
            % the operator did: NotesText is the log as it stood, and once
            % NotesEdited is true it is what the operator hand-edited and
            % therefore the record; Notes is the structured form, re-parsed
            % from that text in the edited case.
            %
            % Never throws: notes must not be able to cost a session its file.
            arguments
                S (1,1) struct
                RUNTIME (1,1) epsych.Runtime
                subjectIdx (1,1) double {mustBeInteger,mustBePositive} = 1
            end

            S.Notes       = epsych.SessionNotes.emptyRecords();
            S.NotesText   = '';
            S.NotesEdited = false;

            try
                N = RUNTIME.NOTES;
                if isempty(N) || ~isvalid(N), return; end

                S.Notes       = N.forSubject(subjectIdx);
                S.NotesEdited = N.IsEdited;
                if N.IsEdited
                    S.NotesText = N.Text;
                else
                    S.NotesText = char(strjoin(N.render(Subject=subjectIdx), newline));
                end
            catch ME
                vprintf(0, 1, ME)
                vprintf(0, 1, 'epsych.SessionSnapshot: session notes could not be recorded with this file')
            end
        end

        function tf = isSnapshot(info)
            % tf = epsych.SessionSnapshot.isSnapshot(info)
            % Whether info is a snapshot rather than legacy metadata.
            %
            % The discriminator is FormatVersion, which no pre-2026-08 Info
            % carried: cl_SaveDataFcn wrote EPsychInfo().meta flat, and
            % ep_SaveDataFcn wrote no Info at all.
            tf = isstruct(info) && isscalar(info) && isfield(info, 'FormatVersion');
        end
    end
end
