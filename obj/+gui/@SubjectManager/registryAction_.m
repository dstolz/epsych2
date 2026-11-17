function out = registryAction_(self, action, varargin)
% out = registryAction_(self, action, ...)
% Everything the Subjects & Projects window does with the lab's subject
% registry (epsych.SubjectRegistry). Every roster change goes through
% epsych.SubjectRoster, so these are only the questions and the wiring.
%
% Actions:
%   'settings'          - the registry's own settings window
%   'link'              - link the SELECTED row's subject to a registry animal
%   'linkContext'       - the same for the row the context menu was opened on
%   'unlink'            - clear the selected subject's link
%   'import'            - registry animals into the selected project
%   'linkProject'       - link the selected project to a registry project
%   'refresh'           - re-read the registry's status for the linked subjects
%   'retireEndpointed'  - retire, in this project, members with an endpoint
%   'guard', ids        - before Add to Session: warn about endpoints and low
%                         weights; OUT true to go ahead
%
% Nothing here contacts the registry during a session: a lookup then is told
% to stay with what the registry already holds (CacheOnly), and Refresh says
% why it will not. The two questions an operator is asked go through
% RegistryPickerFcn and RegistryConfirmFcn, so a test can answer them.
%
% See also: gui.SubjectManager.updateRegistryView_, epsych.SubjectRoster.importSubjects

out = [];
reg = epsych.SubjectRegistry.current();
if ~reg.isEnabled()
    if strcmp(action, 'guard'), out = true; end
    return
end
label = char(reg.label());
fig = self.H.figure;
running = gui.SessionBrowser.sessionIsRunning(self.RunExpt);

try
    % Act on the roster as it is now, not as this window last read it: a link
    % made from another rig decides what Import asks the registry for.
    if ~any(strcmp(action, {'settings', 'guard'})) && ~isempty(self.Roster) && self.Roster.IsBound
        self.Roster.reload();
    end

    switch action
        case 'settings'
            reg.openSettings();

        case {'link', 'linkContext'}
            rec = rowFor(strcmp(action, 'linkContext'));
            if isempty(rec), return, end
            T = reg.findSubjects(struct('CacheOnly', running));
            if height(T) == 0
                alert(sprintf('The %s returned no animals to link to%s.', label, offlineNote()));
                return
            end
            others = string({self.Roster.Subjects.RegistryID});
            others = others(others ~= "" & others ~= string(rec.RegistryID));
            k = self.RegistryPickerFcn(T, Title = sprintf('Link %s to %s', rec.Name, label), ...
                Prompt = sprintf(['Choose the animal in the %s that roster subject "%s" is. ' ...
                    'Its sex and species are copied from there; its sessions and weighings ' ...
                    'are recorded under it.'], label, rec.Name), ...
                NearName = string(rec.Name), Exclude = others, AcceptText = "Link", Parent = fig);
            if isempty(k), return, end
            row = T(k(1), :);
            S = struct('RegistryID', char(row.RegistryID));
            if strlength(row.Sex) > 0, S.Sex = char(row.Sex); end
            if strlength(row.Species) > 0, S.Species = char(row.Species); end
            self.Roster.updateSubject(rec.SubjectID, S);
            self.setStatus_(sprintf('Linked "%s" to %s %s.', rec.Name, label, row.RegistryID));
            self.refresh();

        case 'unlink'
            rec = rowFor(false);
            if isempty(rec), return, end
            if isempty(rec.RegistryID)
                self.setStatus_(sprintf('"%s" is not linked to the %s.', rec.Name, label));
                return
            end
            self.Roster.updateSubject(rec.SubjectID, struct('RegistryID', ''));
            self.setStatus_(sprintf('Unlinked "%s" from %s %s.', rec.Name, label, rec.RegistryID));
            self.refresh();

        case 'import'
            pid = self.selectedProject_();
            if isempty(pid), return, end
            p = self.Roster.findProject(pid);
            filter = struct('CacheOnly', running);
            if ~isempty(p.RegistryID), filter.Project = string(p.RegistryID); end
            T = reg.findSubjects(filter);
            if height(T) == 0
                alert(sprintf('The %s returned no animals%s%s.', label, ...
                    projectNote(p), offlineNote()));
                return
            end
            k = self.RegistryPickerFcn(T, Title = sprintf('Import from %s', label), ...
                Prompt = sprintf(['Tick the animals to bring into "%s"%s. An animal already in ' ...
                    'the roster is linked rather than added twice, and keeps its settings.'], ...
                    p.Name, projectNote(p)), ...
                Multi = true, AcceptText = "Import", Parent = fig);
            if isempty(k), return, end
            rep = self.Roster.importSubjects(table2struct(T(k, :)), ProjectID = pid);
            acts = [rep.Action];
            msg = sprintf('Imported from %s: %d added, %d linked, %d updated, %d unchanged, %d skipped.', ...
                label, nnz(acts == "added"), nnz(acts == "linked"), nnz(acts == "updated"), ...
                nnz(acts == "unchanged"), nnz(acts == "skipped"));
            self.setStatus_(msg);
            skipped = rep(acts == "skipped");
            if ~isempty(skipped)
                lines = compose("%s: %s", [skipped.RegistryID]', [skipped.Reason]');
                alert(sprintf('%s\n\n%s', msg, strjoin(lines, newline)), 'info');
            end
            self.refresh();

        case 'linkProject'
            pid = self.selectedProject_();
            if isempty(pid), return, end
            p = self.Roster.findProject(pid);
            P = reg.projects();
            if height(P) == 0
                alert(sprintf('The %s returned no projects%s.', label, offlineNote()));
                return
            end
            items = P.Name;
            items(~P.IsActive) = items(~P.IsActive) + " (inactive)";
            initial = find(P.RegistryID == string(p.RegistryID), 1);
            if isempty(initial), initial = find(strcmpi(P.Name, p.Name), 1); end
            if isempty(initial), initial = 1; end
            k = gui.selectFromList(items, Title = sprintf('Link Project to %s', label), ...
                Prompt = sprintf(['The %s project roster project "%s" belongs to. Import ' ...
                    'then lists that project''s animals first.'], label, p.Name), ...
                Initial = initial, AcceptText = "Link", Parent = fig);
            if isempty(k), return, end
            self.Roster.updateProject(pid, struct('RegistryID', char(P.RegistryID(k))));
            self.setStatus_(sprintf('Linked project "%s" to %s project "%s".', p.Name, label, P.Name(k)));
            self.refresh();

        case 'refresh'
            if running
                self.setStatus_(sprintf(['Not while a session runs: refreshing reads the %s ' ...
                    'on the thread the trial loop runs on.'], label));
                return
            end
            ids = string({self.Roster.Subjects.RegistryID});
            ids = unique(ids(ids ~= ""));
            if isempty(ids)
                self.setStatus_(sprintf('No subject is linked to the %s.', label));
                return
            end
            self.setStatus_(sprintf('Reading %d subject(s) from the %s...', numel(ids), label));
            drawnow limitrate
            rep = reg.refreshStatus(ids);
            self.refresh(Reload = false);
            self.setStatus_(char(rep.Message));

        case 'retireEndpointed'
            pid = self.selectedProject_();
            if isempty(pid), return, end
            recs = self.Roster.subjectsInProject(pid);
            if isempty(recs), return, end
            recs = recs(~cellfun(@isempty, {recs.RegistryID}));
            if isempty(recs)
                self.setStatus_(sprintf('No member of this project is linked to the %s.', label));
                return
            end
            T = reg.subjectStatus(string({recs.RegistryID}));
            gone = recs(T.Endpointed);
            if isempty(gone)
                self.setStatus_(sprintf('No active member of this project has an endpoint in the %s%s.', ...
                    label, asOfNote(T)));
                return
            end
            names = string({gone.Name});
            choice = self.RegistryConfirmFcn(fig, sprintf( ...
                'The %s records an endpoint for %d active member(s) of this project%s:\n\n%s\n\nRetire them here?', ...
                label, numel(gone), asOfNote(T), strjoin(names, ', ')), 'Retire Endpointed Subjects', ...
                'Options', {'Retire', 'Cancel'}, 'DefaultOption', 2, 'CancelOption', 2, 'Icon', 'warning');
            if ~strcmp(choice, 'Retire'), return, end
            for i = 1:numel(gone)
                self.Roster.setActive(gone(i).SubjectID, pid, false);
            end
            self.setStatus_(sprintf('Retired %d endpointed subject(s): %s.', numel(gone), strjoin(names, ', ')));
            self.refresh();

        case 'guard'
            out = true;
            ids = varargin{1};
            found = cell(1, numel(ids));
            for i = 1:numel(ids)
                found{i} = self.Roster.findSubject(ids{i});
            end
            recs = [found{:}];
            W = reg.sessionWarnings(recs);
            if isempty(W), return, end
            msg = sprintf('%s\n\n', W.Message);
            choice = self.RegistryConfirmFcn(fig, sprintf('%sAdd them to the session anyway?', msg), ...
                sprintf('%s: check these animals', label), ...
                'Options', {'Add Anyway', 'Cancel'}, 'DefaultOption', 2, 'CancelOption', 2, ...
                'Icon', 'warning');
            out = strcmp(choice, 'Add Anyway');
            if out
                % The session's notes do not exist yet; the log is the record
                % that the operator saw this and went ahead.
                vprintf(0, 'Added to the session despite the %s: %s', label, strjoin([W.Message], ' '));
            else
                self.setStatus_('Not added: see the warnings about these animals.');
            end

        otherwise
            error('gui:SubjectManager:UnknownRegistryAction', 'Unknown registry action "%s".', action);
    end
catch ME
    vprintf(0, 1, ME);
    if strcmp(action, 'guard')
        out = true;   % a broken registry must not stop a session being assembled
    end
    alert(ME.message);
end

    function rec = rowFor(fromContext)
        rec = [];
        if fromContext && ~isempty(self.ContextRow_) && self.ContextRow_ <= numel(self.Rows_)
            rec = self.Rows_(self.ContextRow_);
        end
        if isempty(rec)
            rec = self.selectedRow_();
        end
    end

    function alert(msg, icon)
        if nargin < 2, icon = 'warning'; end
        if isgraphics(fig)
            uialert(fig, msg, label, 'Icon', icon);
        end
    end

    function s = offlineNote()
        s = '';
        if running
            s = ' (a session is running, so only what is already on this computer was read)';
        end
    end

    function s = projectNote(p)
        s = '';
        if ~isempty(p.RegistryID)
            s = sprintf(' from its linked %s project', label);
        end
    end
end

% -----------------------------------------------------------------------
function s = asOfNote(T)
s = '';
a = T.AsOf(~isnat(T.AsOf));
if ~isempty(a)
    s = sprintf(' (as of %s)', char(string(min(a), 'yyyy-MM-dd HH:mm')));
end
end
