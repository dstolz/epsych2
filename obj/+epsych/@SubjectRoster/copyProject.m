function newId = copyProject(self, id, newName, options)
% newId = copyProject(self, id, newName)
% newId = copyProject(self, id, newName, IncludeSubjects = true)
% newId = copyProject(self, id, newName, DefaultProtocol = ..., ...)
% Create a new project carrying another one's configuration.
%
% A study's second phase, a cohort's replication, a rig's sister experiment:
% each wants the same saving function, timer period, recording roots, behavior
% GUI, and protocol as one that already runs, and re-entering eleven fields by
% hand is how two projects end up subtly different. The copy is the whole
% configuration by default; any field may be overridden in the same call, which
% is what lets gui.SubjectManager show the operator the copy in its edit dialog
% before anything is written.
%
% Subjects are NOT copied unless asked for, because the two reasons to copy a
% project pull opposite ways: a new cohort wants the settings and none of the
% animals, a second phase wants both. IncludeSubjects covers the second, and
% the source keeps its members either way -- membership is many-to-many, so a
% subject is simply in both projects.
%
% Parameters:
%   id      - ProjectID or Name of the project to copy.
%   newName - name for the copy; must be filename-safe and not already in use.
%
% Options:
%   IncludeSubjects    - also enroll the source's members (default false)
%   IncludeRetired     - bring retired members too, still retired (default false)
%   CopyProtocolMemory - copied members keep the protocol, version, and box
%                        they last used in the source (default true)
%   Notes, Investigator, IACUCProtocol, DefaultProtocol, DefaultDataPath,
%   SavingFcn, TimerStartFcn, TimerRunTimeFcn, TimerStopFcn, TimerErrorFcn,
%   TimerPeriod, VideoRootDir, IntanRootDir, IntanSettingsFile,
%   BehaviorGUI, Links, Archived
%                      - override the source's value for that field. Each has
%                        no default, so "not stated" and "stated as empty" stay
%                        distinguishable and only the former follows the source.
%
% Archived is the one field the copy does not inherit: a project is copied to
% start work, and a hidden copy would look like nothing happened. Pass it
% explicitly to clone an archived project as archived.
%
% ProtocolHistory is never copied even when CopyProtocolMemory is true. The
% history answers "put this membership back the way it was", and a membership
% created a moment ago has no way it was; the pointer it starts on is a
% starting point, not a change to undo.
%
% Returns:
%   newId - the minted ProjectID.
%
% Throws:
%   epsych:SubjectRoster:NoSuchProject
%   epsych:SubjectRoster:InvalidName
%   epsych:SubjectRoster:DuplicateName
%   epsych:SubjectRoster:UnsafeLink
%   epsych:SubjectRoster:InvalidTimerPeriod
%
% The project is created first and its members enrolled second, so a copy
% interrupted between the two leaves an empty project rather than rolling back.
% That is the recoverable half: the settings are the part that cannot be
% reconstructed by clicking, and "Add to Project" finishes the job.
%
% Example:
%   p2 = R.copyProject('Tone Detection', 'Tone Detection Phase 2', ...
%       IncludeSubjects = true, DefaultProtocol = phase2File);
%
% See also: epsych.SubjectRoster.addProject, epsych.SubjectRoster.assign,
%   gui.SubjectManager
arguments
    self
    id (1,:) char
    newName (1,:) char
    options.IncludeSubjects (1,1) logical = false
    options.IncludeRetired (1,1) logical = false
    options.CopyProtocolMemory (1,1) logical = true
    options.Notes (1,:) char
    options.Investigator (1,:) char
    options.IACUCProtocol (1,:) char
    options.DefaultProtocol (1,:) char
    options.DefaultDataPath (1,:) char
    options.SavingFcn (1,:) char
    options.TimerStartFcn (1,:) char
    options.TimerRunTimeFcn (1,:) char
    options.TimerStopFcn (1,:) char
    options.TimerErrorFcn (1,:) char
    options.TimerPeriod (1,1) double
    options.VideoRootDir (1,:) char
    options.IntanRootDir (1,:) char
    options.IntanSettingsFile (1,:) char
    options.BehaviorGUI (1,:) char
    options.Links
    options.Archived (1,1) logical
end

src = self.findProject(id);
if isempty(src)
    error('epsych:SubjectRoster:NoSuchProject', 'No project matches "%s".', id);
end

% Everything the source configures, unless the caller said otherwise. Built as
% a struct and expanded rather than validated here: addProject owns what a
% legal name, link, and timer period are, and a second copy of those rules
% would be the copy that drifts.
A = struct();
for f = ["Notes" "Investigator" "IACUCProtocol" "DefaultProtocol" ...
         "DefaultDataPath" "SavingFcn" ...
         "TimerStartFcn" "TimerRunTimeFcn" "TimerStopFcn" "TimerErrorFcn" ...
         "TimerPeriod" "VideoRootDir" ...
         "IntanRootDir" "IntanSettingsFile" "BehaviorGUI" "Links"]
    if isfield(options, f)
        A.(f) = options.(f);
    else
        A.(f) = src.(f);
    end
end
if isfield(options, 'Archived')
    A.Archived = options.Archived;
end

args  = namedargs2cell(A);
newId = self.addProject(newName, args{:});

if ~options.IncludeSubjects
    vprintf(1, 'Copied project "%s" to "%s".', src.Name, newName);
    return
end

srcId  = src.ProjectID;
copied = 0;
self.mutate_(@applyCopyMembers);

vprintf(1, 'Copied project "%s" to "%s" with %d subject(s).', ...
    src.Name, newName, copied);

    function applyCopyMembers(r)
        % Read the memberships inside the mutation rather than before it: the
        % lock is held and the file has just been re-read, so what is enrolled
        % is what the other rig left behind, not what this one last saw.
        [~, k] = r.findProject(newId);
        if isempty(k)
            error('epsych:SubjectRoster:NoSuchProject', ...
                'Project "%s" was removed by another session.', newId);
        end

        if isempty(r.Memberships), return, end

        take = strcmp({r.Memberships.ProjectID}, srcId);
        if ~options.IncludeRetired
            take = take & [r.Memberships.Active];
        end
        source = r.Memberships(take);
        if isempty(source), return, end

        now_ = datetime('now');
        add  = repmat(epsych.SubjectRoster.blankMembership_(), 1, numel(source));
        keep = true(1, numel(source));

        for i = 1:numel(source)
            % Only reachable if another session enrolled someone in a project
            % created seconds ago, but a duplicate join record has no owner and
            % nothing later would remove it.
            if ~isempty(r.findMembership(source(i).SubjectID, newId))
                keep(i) = false;
                continue
            end

            m = add(i);
            m.SubjectID = source(i).SubjectID;
            m.ProjectID = newId;
            m.Active    = source(i).Active;

            % Stamp from the NEW project's template, never from the source
            % memberships: a copy starts a study's next phase on agreed
            % settings, and carrying per-subject divergence forward would
            % seed the commit-time mismatch refusal into a project that has
            % never run.
            for sf = epsych.SubjectRoster.SESSION_FIELDS
                m.(sf{1}) = r.Projects(k).(sf{1});
            end

            if options.CopyProtocolMemory
                m.LastProtocol        = source(i).LastProtocol;
                m.LastProtocolVersion = source(i).LastProtocolVersion;
                m.LastBoxID           = source(i).LastBoxID;
            end

            m.Added    = now_;
            m.Modified = now_;
            add(i)     = m;
        end

        add = add(keep);
        r.Memberships = [r.Memberships, add];
        copied = numel(add);
    end

end
