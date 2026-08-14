classdef SubjectRoster < handle
    % epsych.SubjectRoster
    % R = epsych.SubjectRoster()
    % R = epsych.SubjectRoster(filePath)
    % Persistent, shareable roster of subjects organized by project.
    %
    % A roster answers "which animals exist, which study is each one in, and
    % what did it last run" — none of which a .ecfg file records. It is the
    % headless engine behind gui.SubjectManager: every query, mutation, and the
    % batch commit into epsych.RunExpt.CONFIG live here, so all of it is
    % testable with no figure open.
    %
    % Membership is many-to-many and carries its own attributes (a per-project
    % active/retired flag and the protocol that subject last ran in that
    % project), so the model is three flat arrays plus a join table rather than
    % subjects nested under projects. Nesting would duplicate any two-project
    % subject and leave no authoritative copy.
    %
    % Subjects are keyed by a minted SubjectID, never by Name: Name is a
    % filesystem path component (see ExptDispatch) and two projects may
    % legitimately reuse a short animal code.
    %
    % A project also owns the behavior GUI its sessions run (BoxGUI): the GUI
    % belongs to a paradigm, and a paradigm is what a project is, so it is
    % applied by assignToSession rather than configured per rig.
    %
    % The roster never holds an epsych.Subject object — only plain structs with
    % no BoxID field, because a box is a property of a session, not of an
    % animal. A subject is materialized into an epsych.DefaultSubject at the
    % moment it is assigned to a session; see toSubject.
    %
    % Properties (read-only):
    %   FilePath    - Full path to the .esub file backing this roster
    %   Subjects    - (1,:) struct array of subject records
    %   Projects    - (1,:) struct array of project records
    %   Memberships - (1,:) struct array joining subjects to projects
    %   IsWritable  - False when the file could not be written; mutations refuse
    %   IsReadOnly  - True when the file is newer than this build understands
    %   LoadError   - Message from the last failed read, or '' when healthy
    %   LastRead    - datetime of the last successful read
    %
    % Methods:
    %   reload, save                        - lifecycle
    %   addSubject, updateSubject, deleteSubject, findSubject
    %   addProject, updateProject, deleteProject, findProject
    %   assign, unassign, setActive         - membership
    %   subjectsInProject, projectsForSubject
    %   rememberProtocol, lastProtocol      - per-membership protocol memory
    %   toSubject, fromSubject              - the epsych.Subject seam
    %   assignToSession                     - batch commit into RunExpt.CONFIG
    %   importFromConfig, exportTable       - migration
    %
    % Static methods:
    %   defaultFile, configuredFile, setConfiguredFile
    %   newId, isNameSafe
    %   emptySubject, emptyProject, emptyMembership
    %
    % Examples:
    %   R = epsych.SubjectRoster;
    %   p = R.addProject('Tone Detection');
    %   s = R.addSubject(struct('Name','M001','Sex','Male','Species','Mouse'));
    %   R.assign(s, p);
    %   ids = {R.subjectsInProject(p).SubjectID};
    %   R.assignToSession(rx, ids);
    %
    % Concurrency: two rigs may share one file. Every mutation reloads if the
    % file changed underneath it, applies, then writes atomically via a
    % same-directory temp file plus movefile. See documentation/epsych/
    % epsych_SubjectRoster.md for the full contract.
    %
    % See also: documentation/epsych/epsych_SubjectRoster.md, gui.SubjectManager,
    %   epsych.Subject, epsych.DefaultSubject, epsych.RunExpt

    properties (SetAccess = private)
        FilePath    (1,:) char = ''     % Full path to the backing .esub file
        Subjects            struct      % (1,:) subject records
        Projects            struct      % (1,:) project records
        Memberships         struct      % (1,:) subject-to-project join records
        IsWritable  (1,1) logical = true  % False once a write has failed
        IsReadOnly  (1,1) logical = false % True when the file is from a newer build
        LoadError   (1,:) char = ''     % Message from the last failed read
        LastRead              datetime  % Time of the last successful read
    end

    properties (Access = private)
        FileStamp_ = []      % path+mtime+size key; see stamp_
        LockHeld_  (1,:) char = ''  % Path of a lock file currently held
    end

    properties (Constant)
        % Bump only alongside a documented migration. A file whose
        % formatVersion exceeds this opens read-only rather than being
        % silently rewritten without the fields a newer build added.
        FORMAT_VERSION (1,1) double = 1

        FILE_EXTENSION (1,:) char = '.esub'

        % A project's BoxGUI field names the behavior GUI its sessions launch.
        % Empty means "inherit the session default" -- the only meaning an
        % existing roster could have -- so "launch nothing" needs a word of its
        % own rather than a second empty.
        BOXGUI_NONE (1,:) char = 'none'
    end

    properties (Constant, Access = private)
        PREF_GROUP  (1,:) char = 'ep_RunExpt_Subjects'
        LOCK_STALE_SECONDS (1,1) double = 30
    end

    % -----------------------------------------------------------------------
    methods

        function self = SubjectRoster(filePath)
            % self = epsych.SubjectRoster()
            % self = epsych.SubjectRoster(filePath)
            % Open the roster at filePath, or the configured one when omitted.
            % A missing file is not an error: the roster starts empty and the
            % file is created on the first mutation.
            arguments
                filePath (1,:) char = epsych.SubjectRoster.configuredFile()
            end

            self.FilePath    = filePath;
            self.Subjects    = epsych.SubjectRoster.emptySubject();
            self.Projects    = epsych.SubjectRoster.emptyProject();
            self.Memberships = epsych.SubjectRoster.emptyMembership();

            self.reload();
        end

        % Lifecycle
        reload(self)
        tf = save(self)

        % Subjects
        id  = addSubject(self, S)
        updateSubject(self, id, S)
        deleteSubject(self, id)
        [rec, idx] = findSubject(self, key)

        % Projects
        id  = addProject(self, name, options)
        updateProject(self, id, P)
        deleteProject(self, id)
        [rec, idx] = findProject(self, key)

        % Membership
        assign(self, subjectId, projectId)
        unassign(self, subjectId, projectId)
        setActive(self, subjectId, projectId, tf)

        % Queries
        recs = subjectsInProject(self, projectId, options)
        recs = projectsForSubject(self, subjectId)
        [rec, idx] = findMembership(self, subjectId, projectId)

        % Protocol memory
        rememberProtocol(self, subjectId, projectId, protocolFile, boxID)
        pfn = lastProtocol(self, subjectId, projectId)

        % The epsych.Subject seam
        S  = toSubject(self, subjectId, options)
        id = fromSubject(self, S, options)

        % Session commit and migration
        report = assignToSession(self, runExpt, subjectIds, options)
        report = importFromConfig(self, configFile, options)
        T = exportTable(self)

    end

    % -----------------------------------------------------------------------
    methods (Access = private)
        tf = mutate_(self, fcn)
        tf = saveAtomic_(self)
        tf = acquireLock_(self)
        releaseLock_(self)
        reloadIfStale_(self)
        blocker = renameBlocker_(self, oldName)
    end

    % -----------------------------------------------------------------------
    methods (Static)
        f  = defaultFile()
        f  = configuredFile()
        setConfiguredFile(filePath)
        id = newId(prefix)
        [tf, why] = isNameSafe(name)
        s  = emptySubject()
        p  = emptyProject()
        m  = emptyMembership()
    end

    % -----------------------------------------------------------------------
    methods (Static, Access = private)
        k = stamp_(filePath)
        r = normalize_(rec, template)
        s = blankSubject_()
        p = blankProject_()
        m = blankMembership_()
        found = readConfigSubjects_(configFile)
    end

end
