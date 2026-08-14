classdef SubjectManager < handle
    % gui.SubjectManager
    % obj = gui.SubjectManager()
    % obj = gui.SubjectManager(runExpt)
    % Browse subjects by project and put several of them into a session at once.
    %
    % This is the operator's entry point for session subjects. Pick a project,
    % tick the animals running today, and commit them in one action: each gets
    % a free box and the protocol it last ran, so the common case takes two
    % clicks instead of one dialog and one file browser per animal.
    %
    % It is also where the roster is maintained -- creating projects, moving
    % subjects between them, retiring finished animals, and importing subjects
    % out of existing .ecfg files.
    %
    % All state lives in epsych.SubjectRoster; this class only lays out controls
    % and renders what the engine returns. Opening it with no session window is
    % supported: the roster is fully browsable, and only "Add Checked to
    % Session" needs a session.
    %
    % Properties:
    %   Roster  - the epsych.SubjectRoster being displayed
    %   RunExpt - the session subjects are committed into, or [] when standalone
    %   H       - struct of graphics handles
    %
    % Methods:
    %   refresh(obj)              - re-read the roster and repopulate the window
    %   addToSession(obj)         - commit the checked rows into RunExpt.CONFIG
    %   revealSubject(obj, name)  - select a subject, switching project if needed
    %
    % Examples:
    %   gui.SubjectManager                 % standalone; finds any open session
    %   gui.SubjectManager(runExpt)        % bound to a specific session
    %
    %   m = gui.SubjectManager;
    %   m.revealSubject('M001');
    %
    % See also: documentation/gui/gui_SubjectManager.md, epsych.SubjectRoster,
    %   epsych.RunExpt.OpenSubjectManager

    properties (SetAccess = private)
        Roster              % epsych.SubjectRoster backing this window
        RunExpt             % epsych.RunExpt to commit into, or []
        H = struct()        % graphics handles
    end

    properties (Access = private)
        Rows_ = []          % subject records currently shown, one per table row
        Checked_ = {}       % SubjectIDs ticked, preserved across a refresh
        BoxOverrides_       % containers.Map SubjectID -> box, cleared on commit
        ProtocolOverrides_  % containers.Map SubjectID -> .eprot, cleared on commit
        Refreshing_ (1,1) logical = false  % guards callbacks fired by repopulation
        PendingProject_ (1,:) char = ''    % project to select once refresh builds the list

        % In-flight filter text while the operator is typing. A 0x0 string means
        % "not typing", so the committed H.filter.Value applies; "" means the
        % operator has typed the field empty. Writing the keystrokes here rather
        % than back into H.filter.Value is what keeps live search whole: setting
        % Value from inside ValueChangingFcn re-renders the field mid-edit and
        % drops characters, so a filter typed as '123' would search only '1'.
        LiveFilter_ = string.empty
    end

    properties (Constant, Access = private)
        FIGURE_TAG (1,:) char = 'EPsychSubjectManager'
        PREF_TAG   (1,:) char = 'epsych2_gui_SubjectManager'
        PREF_GROUP (1,:) char = 'ep_RunExpt_Subjects'

        % Pinned first in the project list. Not a project: it shows every
        % subject regardless of membership, which is both the empty state for a
        % fresh roster and the way to find a subject whose project you forgot.
        ALL_SUBJECTS (1,:) char = '<All Subjects>'

        DEFAULT_POSITION (1,4) double = [100 100 1120 640]
    end

    % -----------------------------------------------------------------------
    methods

        function self = SubjectManager(runExpt)
            % self = gui.SubjectManager()
            % self = gui.SubjectManager(runExpt)
            % Open the manager, replacing any window already open.
            %
            % Parameters:
            %   runExpt - epsych.RunExpt to commit subjects into. Defaults to
            %             the live session, or [] when none is open.
            arguments
                runExpt = epsych.SelfTest.findActiveRunExpt()
            end

            self.RunExpt = runExpt;
            self.BoxOverrides_      = containers.Map('KeyType','char','ValueType','any');
            self.ProtocolOverrides_ = containers.Map('KeyType','char','ValueType','any');

            % One window at a time. Detach UserData and CloseRequestFcn first
            % so deleting it cannot re-enter this object's own teardown.
            existing = findall(groot, 'Type','figure', 'Tag', self.FIGURE_TAG);
            for i = 1:numel(existing)
                if ~isgraphics(existing(i)), continue, end
                prior = existing(i).UserData;
                existing(i).UserData = [];
                existing(i).CloseRequestFcn = '';
                delete(existing(i));
                if isobject(prior) && isvalid(prior)
                    delete(prior);
                end
            end

            try
                self.Roster = epsych.SubjectRoster();
            catch ME
                % A roster that cannot even be constructed must still leave a
                % usable window, so the operator can re-point the file.
                vprintf(0, 1, ME);
                self.Roster = [];
            end

            self.buildUI();
            self.restoreProject_();
            self.refresh();

            if nargout == 0
                clear self
            end
        end

        function delete(self)
            % delete(self)
            % Tear down the window, saving its position.
            try
                if isfield(self.H,'figure') && isgraphics(self.H.figure)
                    gui.BoxGUI.saveFigurePosition(self.PREF_TAG, self.H.figure.Position);
                    self.H.figure.UserData = [];
                    self.H.figure.CloseRequestFcn = '';
                    delete(self.H.figure);
                end
            catch ME
                vprintf(2, ME);
            end
        end

        refresh(self)
        addToSession(self)
        revealSubject(self, name)

    end

    % -----------------------------------------------------------------------
    % Substantial private behaviour lives in its own file; the small callbacks
    % below stay here, following gui.SelfTest.
    % -----------------------------------------------------------------------
    methods (Access = private)
        buildUI(self)
        P = projectDialog_(self, seed)
        onImportFromConfig_(self)
    end

    % -----------------------------------------------------------------------
    methods (Access = private)

        function id = selectedProject_(self)
            % ProjectID of the current selection, or '' for All Subjects.
            id = '';
            if isfield(self.H,'projectList') && isgraphics(self.H.projectList)
                id = self.H.projectList.Value;
            end
            if isempty(id), id = ''; end
        end

        function recs = visibleSubjects_(self)
            % Subject records for the current project, filter, and retired toggle.
            projectId = self.selectedProject_();
            showRetired = self.H.showRetired.Value;

            if isempty(projectId)
                recs = self.Roster.Subjects;
                if ~isempty(recs)
                    [~, order] = sort(lower(string({recs.Name})));
                    recs = recs(order);
                end
                if ~showRetired && ~isempty(recs)
                    recs = recs(~self.retiredEverywhere_(recs));
                end
            else
                recs = self.Roster.subjectsInProject(projectId, IncludeRetired = showRetired);
            end

            needle = self.filterText_();
            if isempty(needle) || isempty(recs), return, end

            % Plain case-insensitive contains anywhere in the text, never a
            % regex and never anchored: 'M(1' must narrow the list rather than
            % raise, and '123' must find 'SUBJ-ID-1231' as readily as '123ab'.
            hay = lower(string({recs.Name}) + " " + string({recs.Species}) + ...
                " " + string({recs.Notes}));
            recs = recs(contains(hay, lower(needle)));
        end

        function needle = filterText_(self)
            % The text to filter on, trimmed.
            %
            % While the operator is typing, the keystrokes have not reached
            % H.filter.Value yet, so the in-flight text wins; otherwise the
            % committed value does.
            if isempty(self.LiveFilter_)
                needle = strtrim(self.H.filter.Value);
            else
                needle = strtrim(char(self.LiveFilter_));
            end
        end

        function clearFilter_(self)
            % The Clear button. Setting Value fires no callback of its own, so
            % the in-flight text has to be dropped here too.
            self.setFilterText_('');
            self.refresh(Reload = false);
        end

        function setFilterText_(self, txt)
            % Set the filter programmatically, discarding any in-flight text.
            arguments
                self
                txt (1,:) char = ''
            end
            self.LiveFilter_ = string.empty;
            self.H.filter.Value = txt;
        end

        function tf = retiredEverywhere_(self, recs)
            % True for subjects with no active membership anywhere. A subject in
            % no project at all counts as active: it has not been retired, it
            % has just not been filed yet, and hiding it would lose it.
            tf = false(1, numel(recs));
            if isempty(self.Roster.Memberships), return, end

            for i = 1:numel(recs)
                mine = self.Roster.Memberships( ...
                    strcmp({self.Roster.Memberships.SubjectID}, recs(i).SubjectID));
                if isempty(mine), continue, end
                tf(i) = ~any([mine.Active]);
            end
        end

        function ids = checkedIds_(self)
            % SubjectIDs ticked in the table right now.
            ids = {};
            if isempty(self.Rows_) || isempty(self.H.table.Data), return, end

            flags = cell2mat(self.H.table.Data(:,1));
            n = min(numel(flags), numel(self.Rows_));
            ids = {self.Rows_(flags(1:n)).SubjectID};
        end

        function setStatus_(self, message)
            % Post one line to the footer.
            if isfield(self.H,'status') && isgraphics(self.H.status)
                self.H.status.Text = message;
            end
        end

        function restoreProject_(self)
            % Re-select the project this roster was last left on.
            %
            % Keyed by roster path, so re-pointing the roster file cannot
            % restore a project ID belonging to a different roster.
            if isempty(self.Roster), return, end
            if ~ispref(self.PREF_GROUP,'LastProject'), return, end

            try
                saved = getpref(self.PREF_GROUP,'LastProject');
                key = matlab.lang.makeValidName(self.Roster.FilePath);
                if ~isstruct(saved) || ~isfield(saved, key), return, end

                id = saved.(key);
                if isempty(self.Roster.findProject(id))
                    vprintf(2, 'Remembered project no longer exists; showing all subjects.');
                    return
                end

                % The listbox has no items until refresh builds it, so the
                % choice is parked here for refresh to apply.
                self.PendingProject_ = id;
            catch ME
                vprintf(2, ME);
            end
        end

        function rememberProject_(self)
            % Persist the selected project, keyed by roster path.
            %
            % Called only from the listbox callback, never from a programmatic
            % selection: a script driving this window must not overwrite what
            % the operator chose.
            if isempty(self.Roster), return, end

            try
                saved = struct();
                if ispref(self.PREF_GROUP,'LastProject')
                    prior = getpref(self.PREF_GROUP,'LastProject');
                    if isstruct(prior), saved = prior; end
                end
                saved.(matlab.lang.makeValidName(self.Roster.FilePath)) = ...
                    self.selectedProject_();
                setpref(self.PREF_GROUP,'LastProject',saved);
            catch ME
                vprintf(2, ME);
            end
        end

        function updateProjectSummary_(self)
            % Show what the selected project will apply to its members.
            id = self.selectedProject_();
            if isempty(id)
                self.H.projectSummary.Text = ...
                    'Every subject in the roster, in any project or none.';
                return
            end

            p = self.Roster.findProject(id);
            if isempty(p)
                self.H.projectSummary.Text = '';
                return
            end

            lines = {};
            if ~isempty(p.Notes), lines{end+1} = p.Notes; end
            if isempty(p.DefaultProtocol)
                lines{end+1} = 'Default protocol: (none)';
            else
                [~, pn, pe] = fileparts(p.DefaultProtocol);
                lines{end+1} = sprintf('Default protocol: %s%s', pn, pe);
            end
            if ~isempty(p.DefaultDataPath)
                lines{end+1} = sprintf('Data path: %s', p.DefaultDataPath);
            end
            % Named even when unset: this is where the box GUI is configured
            % now, so the summary has to say so rather than stay silent.
            if isempty(p.BoxGUI)
                lines{end+1} = 'Box GUI: (session default)';
            elseif strcmpi(p.BoxGUI, epsych.SubjectRoster.BOXGUI_NONE)
                lines{end+1} = 'Box GUI: (none)';
            else
                lines{end+1} = sprintf('Box GUI: %s', p.BoxGUI);
            end

            self.H.projectSummary.Text = lines;
            self.H.projectSummary.Tooltip = p.DefaultProtocol;
        end

        function txt = emptyStateText_(self)
            % The right "nothing to show" sentence for the current situation.
            needle = self.filterText_();
            if ~isempty(needle)
                txt = sprintf('No subjects match "%s".', needle);
                return
            end

            if isempty(self.Roster.Subjects)
                txt = sprintf(['No subjects yet. The roster will be created at\n%s\n' ...
                    'when you add the first one.'], self.Roster.FilePath);
                return
            end

            id = self.selectedProject_();
            if isempty(id)
                txt = 'No subjects to show.';
                return
            end

            p = self.Roster.findProject(id);
            name = id;
            if ~isempty(p), name = p.Name; end
            txt = sprintf(['No subjects in "%s". Choose %s and use ' ...
                'Add to Project to enrol one.'], name, self.ALL_SUBJECTS);
        end

        function showEmptyState_(self, message)
            % Put a centred explanation where the table would be.
            self.H.table.Data = {};
            self.H.table.Visible = 'off';
            self.H.emptyState.Text = message;
            self.H.emptyState.Visible = 'on';
        end

        function updateEnableStates_(self)
            % Enable only what makes sense for the current selection.
            hasRoster   = ~isempty(self.Roster) && isvalid(self.Roster);
            writable    = hasRoster && self.Roster.IsWritable && ~self.Roster.IsReadOnly;
            inProject   = ~isempty(self.selectedProject_());
            hasRows     = ~isempty(self.Rows_);
            hasChecked  = hasRows && ~isempty(self.checkedIds_());
            hasSelection = hasRows && ~isempty(self.H.table.Selection);
            hasSession  = ~isempty(self.RunExpt) && isa(self.RunExpt,'epsych.RunExpt') ...
                && isvalid(self.RunExpt);

            onoff = @(tf) matlab.lang.OnOffSwitchState(tf);

            self.H.btnNewSubject.Enable  = onoff(writable);
            self.H.mnu_new_subject.Enable = onoff(writable);
            self.H.btnEditSubject.Enable = onoff(writable && hasSelection);
            self.H.mnu_edit_subject.Enable = onoff(writable && hasSelection);
            self.H.mnu_delete_subject.Enable = onoff(writable && hasSelection);

            self.H.btnAddToProject.Enable = onoff(writable && inProject && hasChecked);
            self.H.mnu_add_to_project.Enable = self.H.btnAddToProject.Enable;
            self.H.btnRemoveFromProject.Enable = onoff(writable && inProject && hasChecked);
            self.H.mnu_remove_from_project.Enable = self.H.btnRemoveFromProject.Enable;

            self.H.btnRetire.Enable = onoff(writable && inProject && hasChecked);
            self.H.mnu_retire.Enable = self.H.btnRetire.Enable;

            self.H.btnEditProject.Enable   = onoff(writable && inProject);
            self.H.mnu_edit_project.Enable = self.H.btnEditProject.Enable;
            self.H.btnDeleteProject.Enable = onoff(writable && inProject);
            self.H.mnu_delete_project.Enable = self.H.btnDeleteProject.Enable;

            self.H.btnAddToSession.Enable = onoff(hasSession && hasChecked);
            self.H.mnu_add_to_session.Enable = self.H.btnAddToSession.Enable;
            self.H.mnu_set_protocol.Enable = onoff(hasChecked);

            if ~inProject
                self.H.btnAddToProject.Tooltip = ...
                    'Select a project on the left to add subjects to it.';
                self.H.btnRemoveFromProject.Tooltip = ...
                    'Select a project on the left to remove subjects from it.';
            else
                self.H.btnAddToProject.Tooltip = '';
                self.H.btnRemoveFromProject.Tooltip = '';
            end

            if ~hasSession
                self.H.btnAddToSession.Tooltip = ...
                    'No session window is open. Start epsych.RunExpt first.';
            else
                self.H.btnAddToSession.Tooltip = '';
            end

            % Retire and Restore are the same button; the label follows what
            % ticking those rows would actually do.
            if hasChecked && inProject && self.checkedAreRetired_()
                self.H.btnRetire.Text = 'Restore';
                self.H.mnu_retire.Text = 'Res&tore';
            else
                self.H.btnRetire.Text = 'Retire';
                self.H.mnu_retire.Text = 'Re&tire';
            end
        end

        function tf = checkedAreRetired_(self)
            % True when every checked subject is retired from this project.
            tf = false;
            ids = self.checkedIds_();
            projectId = self.selectedProject_();
            if isempty(ids) || isempty(projectId), return, end

            flags = false(1, numel(ids));
            for i = 1:numel(ids)
                rec = self.Roster.findMembership(ids{i}, projectId);
                flags(i) = ~isempty(rec) && ~rec.Active;
            end
            tf = all(flags);
        end

        function pfn = resolveProtocol_(self, subjectId)
            % Protocol proposed for one subject: an override the operator set
            % in this window, else what the engine remembers.
            if self.ProtocolOverrides_.isKey(subjectId)
                pfn = self.ProtocolOverrides_(subjectId);
                return
            end
            pfn = self.Roster.lastProtocol(subjectId, self.selectedProject_());
        end

        % ---- table and filter plumbing ---------------------------------

        function onCellEdit_(self, evt)
            % Handle a tick or a box number typed into the grid.
            if self.Refreshing_, return, end

            row = evt.Indices(1);
            col = evt.Indices(2);
            if row > numel(self.Rows_), return, end
            id = self.Rows_(row).SubjectID;

            switch col
                case 1
                    if evt.NewData
                        self.Checked_ = union(self.Checked_, {id});
                    else
                        self.Checked_ = setdiff(self.Checked_, {id});
                    end

                case 3
                    box = evt.NewData;
                    if isempty(box) || (isnumeric(box) && isnan(box))
                        if self.BoxOverrides_.isKey(id)
                            self.BoxOverrides_.remove(id);
                        end
                    elseif ~isnumeric(box) || box < 1 || box > 16 || box ~= fix(box)
                        % Put the old value back rather than storing nonsense.
                        self.H.table.Data{row, col} = evt.PreviousData;
                        self.setStatus_('Box must be a whole number from 1 to 16, or blank to assign one automatically.');
                        return
                    else
                        self.BoxOverrides_(id) = box;
                    end
            end

            self.updateEnableStates_();
            nChecked = numel(self.checkedIds_());
            self.H.countLabel.Text = sprintf('%d of %d shown \x00B7 %d checked', ...
                numel(self.Rows_), numel(self.Roster.Subjects), nChecked);
        end

        function onProjectChanged_(self)
            % Operator picked a project: remember it, then repopulate.
            if self.Refreshing_, return, end
            self.rememberProject_();
            self.refresh();
        end

        function onFilterChanged_(self, liveValue)
            % Re-filter as the operator types.
            %
            % Called with the in-flight text from ValueChangingFcn on every
            % keystroke, and with nothing from ValueChangedFcn once the edit
            % commits. The keystrokes are stashed instead of assigned back to
            % the field -- see LiveFilter_ -- so nothing interrupts the edit in
            % progress and the whole typed string is searched.
            arguments
                self
                liveValue (1,:) char = ''
            end
            if self.Refreshing_, return, end

            if nargin > 1
                self.LiveFilter_ = string(liveValue);
            else
                self.LiveFilter_ = string.empty;
            end

            % No disk read on a keystroke: re-filtering is a view change over
            % records already in memory, and a roster on a network drive would
            % otherwise be re-read once per character typed.
            self.refresh(Reload = false);
        end

        function onKeyPress_(self, evt)
            % Window-level shortcuts.
            mods = evt.Modifier;
            hasCtrl  = any(strcmp(mods,'control'));
            hasShift = any(strcmp(mods,'shift'));

            switch evt.Key
                case 'f'
                    if hasCtrl, focus(self.H.filter); end
                case 'n'
                    if hasCtrl && hasShift
                        self.onNewProject_();
                    elseif hasCtrl
                        self.onNewSubject_();
                    end
                case 'f5'
                    self.refresh();
                case 'delete'
                    % Deliberately the reversible action: deleting from the
                    % roster is menu-only and confirmed.
                    self.onRemoveFromProject_();
                case 'escape'
                    delete(self);
            end
        end

        % ---- subject actions -------------------------------------------

        function onNewSubject_(self)
            % Create a subject through whichever dialog the session is
            % configured to use, so a lab's custom AddSubjectFcn still applies.
            reserved = {};
            if ~isempty(self.Roster.Subjects)
                reserved = {self.Roster.Subjects.Name};
            end

            try
                if ~isempty(self.RunExpt) && isvalid(self.RunExpt)
                    % Tell the dialog which boxes are still free so it can mark
                    % the rest; every box stays selectable, and the operator's
                    % answer seeds the Box column rather than being discarded.
                    boxids = self.freeSessionBoxes_();
                    S = self.RunExpt.dispatchAddSubjectFcn_(struct(), boxids, reserved);
                else
                    S = epsych.DefaultSubject.open(struct(), 1:16, 'ReservedNames', reserved);
                end
            catch ME
                vprintf(0, 1, ME);
                uialert(self.H.figure, ME.message, 'New Subject', 'Icon','error');
                return
            end

            if isempty(S), return, end

            try
                id = self.Roster.addSubject(S);
            catch ME
                vprintf(0, 1, ME);
                uialert(self.H.figure, ME.message, 'New Subject', 'Icon','error');
                return
            end

            % The dialog's box answer is session state, not roster state, so it
            % is carried as an override rather than stored on the record.
            if isa(S,'epsych.Subject') && ~isempty(S.BoxID)
                self.BoxOverrides_(id) = S.BoxID;
            end

            projectId = self.selectedProject_();
            if ~isempty(projectId)
                try
                    self.Roster.assign(id, projectId);
                catch ME
                    vprintf(0, 1, ME);
                end
            end

            self.Checked_ = union(self.Checked_, {id});
            self.refresh();
            self.setStatus_(sprintf('Added subject "%s".', S.Name));
        end

        function onEditSubject_(self)
            % Edit the selected subject's details.
            rec = self.selectedRow_();
            if isempty(rec), return, end

            reserved = {};
            if ~isempty(self.Roster.Subjects)
                names = {self.Roster.Subjects.Name};
                reserved = names(~strcmp(names, rec.Name));
            end

            seed = self.Roster.toSubject(rec.SubjectID);

            try
                if ~isempty(self.RunExpt) && isvalid(self.RunExpt)
                    S = self.RunExpt.dispatchAddSubjectFcn_(seed, 1:16, reserved);
                else
                    S = epsych.DefaultSubject.open(seed, 1:16, 'ReservedNames', reserved);
                end
            catch ME
                vprintf(0, 1, ME);
                uialert(self.H.figure, ME.message, 'Edit Subject', 'Icon','error');
                return
            end

            if isempty(S), return, end

            try
                self.Roster.updateSubject(rec.SubjectID, S);
            catch ME
                vprintf(0, 1, ME);
                uialert(self.H.figure, ME.message, 'Edit Subject', 'Icon','error');
                return
            end

            self.refresh();
            self.setStatus_(sprintf('Updated subject "%s".', S.Name));
        end

        function onDeleteSubject_(self)
            % Delete a subject from the roster, after naming what is lost.
            rec = self.selectedRow_();
            if isempty(rec), return, end

            if self.isInSession_(rec.Name)
                uialert(self.H.figure, sprintf( ...
                    ['"%s" is in the current session and cannot be deleted from the ' ...
                     'roster. Remove it from the session first.'], rec.Name), ...
                    'Delete Subject', 'Icon','warning');
                return
            end

            projects = self.Roster.projectsForSubject(rec.SubjectID);
            msg = sprintf('Delete "%s" from the roster?', rec.Name);
            if ~isempty(projects)
                msg = sprintf('%s\n\nIt will be removed from: %s.', msg, ...
                    strjoin({projects.Name}, ', '));
            end
            msg = sprintf(['%s\n\nSaved experiment data is not affected. This cannot ' ...
                'be undone -- consider Retire instead.'], msg);

            answer = uiconfirm(self.H.figure, msg, 'Delete Subject', ...
                'Options', {'Delete','Cancel'}, ...
                'DefaultOption','Cancel', 'CancelOption','Cancel', 'Icon','warning');
            if ~strcmp(answer,'Delete'), return, end

            try
                self.Roster.deleteSubject(rec.SubjectID);
            catch ME
                vprintf(0, 1, ME);
                uialert(self.H.figure, ME.message, 'Delete Subject', 'Icon','error');
                return
            end

            self.Checked_ = setdiff(self.Checked_, {rec.SubjectID});
            self.refresh();
            self.setStatus_(sprintf('Deleted "%s" from the roster.', rec.Name));
        end

        function onToggleRetired_(self)
            % Retire the checked subjects from this project, or restore them.
            ids = self.checkedIds_();
            projectId = self.selectedProject_();
            if isempty(ids) || isempty(projectId), return, end

            makeActive = self.checkedAreRetired_();

            for i = 1:numel(ids)
                try
                    self.Roster.setActive(ids{i}, projectId, makeActive);
                catch ME
                    vprintf(0, 1, ME);
                end
            end

            self.refresh();
            if makeActive
                self.setStatus_(sprintf('Restored %d subject(s).', numel(ids)));
            else
                self.setStatus_(sprintf(['Retired %d subject(s). Tick "Show retired" ' ...
                    'and press Restore to undo.'], numel(ids)));
            end
        end

        function onAddToProject_(self)
            % Enrol the checked subjects in the selected project.
            ids = self.checkedIds_();
            projectId = self.selectedProject_();
            if isempty(ids) || isempty(projectId), return, end

            for i = 1:numel(ids)
                try
                    self.Roster.assign(ids{i}, projectId);
                catch ME
                    vprintf(0, 1, ME);
                end
            end

            self.refresh();
            self.setStatus_(sprintf('Added %d subject(s) to the project.', numel(ids)));
        end

        function onRemoveFromProject_(self)
            % Take the checked subjects out of the selected project.
            ids = self.checkedIds_();
            projectId = self.selectedProject_();
            if isempty(ids) || isempty(projectId), return, end

            p = self.Roster.findProject(projectId);
            pName = projectId;
            if ~isempty(p), pName = p.Name; end

            answer = uiconfirm(self.H.figure, sprintf( ...
                ['Remove %d subject(s) from "%s"?\n\nThey stay in the roster and in ' ...
                 'their other projects.'], numel(ids), pName), ...
                'Remove from Project', ...
                'Options', {'Remove','Cancel'}, ...
                'DefaultOption','Cancel', 'CancelOption','Cancel', 'Icon','question');
            if ~strcmp(answer,'Remove'), return, end

            for i = 1:numel(ids)
                try
                    self.Roster.unassign(ids{i}, projectId);
                catch ME
                    vprintf(0, 1, ME);
                end
            end

            self.refresh();
            self.setStatus_(sprintf('Removed %d subject(s) from "%s".', numel(ids), pName));
        end

        function onSetProtocol_(self, allChecked)
            % Point one row, or every checked row, at a protocol file.
            if allChecked
                ids = self.checkedIds_();
            else
                rec = self.selectedRow_();
                ids = {};
                if ~isempty(rec), ids = {rec.SubjectID}; end
            end
            if isempty(ids)
                self.setStatus_('Select or tick a subject first.');
                return
            end

            start = getpref('ep_RunExpt_Setup','PDir',cd);
            if ~isfolder(start), start = cd; end

            [fn, pn] = uigetfile( ...
                {'*.eprot;*.prot','Protocol Files (*.eprot, *.prot)'; '*.*','All Files (*.*)'}, ...
                'Select Protocol', start);
            if isequal(fn, 0), return, end

            setpref('ep_RunExpt_Setup','PDir', pn);
            pfn = fullfile(pn, fn);

            for i = 1:numel(ids)
                self.ProtocolOverrides_(ids{i}) = pfn;
            end

            self.refresh();
            self.setStatus_(sprintf('Protocol set for %d subject(s): %s', numel(ids), fn));
        end

        % ---- project actions -------------------------------------------

        function onNewProject_(self)
            P = self.projectDialog_(struct('Name','', 'Notes','', ...
                'DefaultProtocol','', 'DefaultDataPath','', 'BoxGUI',''));
            if isempty(P), return, end

            try
                id = self.Roster.addProject(P.Name, Notes = P.Notes, ...
                    DefaultProtocol = P.DefaultProtocol, ...
                    DefaultDataPath = P.DefaultDataPath, ...
                    BoxGUI = P.BoxGUI);
            catch ME
                vprintf(0, 1, ME);
                uialert(self.H.figure, ME.message, 'New Project', 'Icon','error');
                return
            end

            self.refresh();
            % Programmatic selection, so rememberProject_ is called explicitly
            % rather than through the listbox callback.
            self.H.projectList.Value = id;
            self.rememberProject_();
            self.refresh();
            self.setStatus_(sprintf('Created project "%s".', P.Name));
        end

        function onEditProject_(self)
            id = self.selectedProject_();
            if isempty(id), return, end

            seed = self.Roster.findProject(id);
            if isempty(seed), return, end

            P = self.projectDialog_(seed);
            if isempty(P), return, end

            try
                self.Roster.updateProject(id, P);
            catch ME
                vprintf(0, 1, ME);
                uialert(self.H.figure, ME.message, 'Edit Project', 'Icon','error');
                return
            end

            self.refresh();
            self.setStatus_(sprintf('Updated project "%s".', P.Name));
        end

        function onDeleteProject_(self)
            id = self.selectedProject_();
            if isempty(id), return, end

            p = self.Roster.findProject(id);
            if isempty(p), return, end

            n = numel(self.Roster.subjectsInProject(id, IncludeRetired = true));
            answer = uiconfirm(self.H.figure, sprintf( ...
                ['Delete the project "%s"?\n\nIts %d subject(s) stay in the roster; ' ...
                 'only their membership in this project is removed.'], p.Name, n), ...
                'Delete Project', ...
                'Options', {'Delete','Cancel'}, ...
                'DefaultOption','Cancel', 'CancelOption','Cancel', 'Icon','warning');
            if ~strcmp(answer,'Delete'), return, end

            try
                self.Roster.deleteProject(id);
            catch ME
                vprintf(0, 1, ME);
                uialert(self.H.figure, ME.message, 'Delete Project', 'Icon','error');
                return
            end

            self.H.projectList.Value = '';
            self.rememberProject_();
            self.refresh();
            self.setStatus_(sprintf('Deleted project "%s"; its subjects were kept.', p.Name));
        end

        % ---- file actions ----------------------------------------------

        function onChooseRosterFile_(self)
            current = epsych.SubjectRoster.configuredFile();
            ext = epsych.SubjectRoster.FILE_EXTENSION;

            [fn, pn] = uiputfile( ...
                {['*' ext], ['Subject Roster (*' ext ')']; '*.*','All Files (*.*)'}, ...
                'Select or Name a Subject Roster', current);
            if isequal(fn, 0), return, end

            ffn = fullfile(pn, fn);

            try
                epsych.SubjectRoster.setConfiguredFile(ffn);
                self.Roster = epsych.SubjectRoster(ffn);
            catch ME
                vprintf(0, 1, ME);
                uialert(self.H.figure, ME.message, 'Roster File', 'Icon','error');
                return
            end

            self.Checked_ = {};
            self.BoxOverrides_.remove(self.BoxOverrides_.keys);
            self.ProtocolOverrides_.remove(self.ProtocolOverrides_.keys);
            self.H.projectList.Value = '';

            self.restoreProject_();
            self.refresh();
            self.setStatus_(sprintf('Roster: %s', ffn));
        end

        function onExportCsv_(self)
            if isempty(self.Roster.Subjects)
                self.setStatus_('There is nothing to export.');
                return
            end

            [~, base] = fileparts(self.Roster.FilePath);
            [fn, pn] = uiputfile({'*.csv','Comma-Separated Values (*.csv)'}, ...
                'Export Roster', [base '.csv']);
            if isequal(fn, 0), return, end

            try
                writetable(self.Roster.exportTable(), fullfile(pn, fn));
            catch ME
                vprintf(0, 1, ME);
                uialert(self.H.figure, ME.message, 'Export CSV', 'Icon','error');
                return
            end

            self.setStatus_(sprintf('Exported to %s', fullfile(pn, fn)));
        end

        % ---- shared helpers ---------------------------------------------

        function rec = selectedRow_(self)
            % Subject record under the table selection, or [].
            rec = [];
            sel = self.H.table.Selection;
            if isempty(sel) || isempty(self.Rows_)
                self.setStatus_('Select a subject first.');
                return
            end
            row = sel(1);
            if row > numel(self.Rows_), return, end
            rec = self.Rows_(row);
        end

        function tf = isInSession_(self, name)
            % True when a subject of this name is in the open session.
            tf = false;
            if isempty(self.RunExpt) || ~isvalid(self.RunExpt), return, end
            C = self.RunExpt.CONFIG;
            if isempty(C) || ~isa(C(1).SUBJECT,'epsych.Subject'), return, end
            tf = any(strcmpi(name, arrayfun(@(c) c.SUBJECT.Name, C, 'uni', 0)));
        end

        function boxids = freeSessionBoxes_(self)
            % Boxes the open session has not already claimed.
            boxids = 1:16;
            if isempty(self.RunExpt) || ~isvalid(self.RunExpt), return, end
            C = self.RunExpt.CONFIG;
            if isempty(C) || ~isa(C(1).SUBJECT,'epsych.Subject'), return, end
            boxids = setdiff(boxids, arrayfun(@(c) c.SUBJECT.BoxID, C));
            if isempty(boxids), boxids = 1:16; end
        end

    end

end
