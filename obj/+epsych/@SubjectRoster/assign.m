function assign(self, subjectId, projectId)
% assign(self, subjectId, projectId)
% Put a subject in a project.
%
% Idempotent: assigning a subject already in the project reactivates it rather
% than creating a second join record, so "Add to Project" is safe to click
% twice and doubles as an un-retire.
%
% Parameters:
%   subjectId - SubjectID or subject Name.
%   projectId - ProjectID or project Name.
%
% Throws:
%   epsych:SubjectRoster:NoSuchSubject
%   epsych:SubjectRoster:NoSuchProject
%
% See also: epsych.SubjectRoster.unassign, epsych.SubjectRoster.setActive
arguments
    self
    subjectId (1,:) char
    projectId (1,:) char
end

s = self.findSubject(subjectId);
if isempty(s)
    error('epsych:SubjectRoster:NoSuchSubject', 'No subject matches "%s".', subjectId);
end

p = self.findProject(projectId);
if isempty(p)
    error('epsych:SubjectRoster:NoSuchProject', 'No project matches "%s".', projectId);
end

sid = s.SubjectID;
pid = p.ProjectID;

self.mutate_(@applyAssign);

vprintf(1, 'Assigned subject "%s" to project "%s".', s.Name, p.Name);

    function applyAssign(r)
        [~, k] = r.findMembership(sid, pid);
        if ~isempty(k)
            r.Memberships(k).Active   = true;
            r.Memberships(k).Modified = datetime('now');
            return
        end

        rec = epsych.SubjectRoster.blankMembership_();
        rec.SubjectID = sid;
        rec.ProjectID = pid;
        rec.Active    = true;

        % Stamp the project's session-defaults template onto the new
        % membership -- a verbatim copy at join time; later template edits
        % do not reach existing members (reapplyTemplate is the deliberate
        % way to push them). Read from r rather than the pre-lock p: the
        % lock is held and the file has just been re-read, so this is the
        % template as another rig last left it.
        tpl = r.findProject(pid);
        if isempty(tpl)
            error('epsych:SubjectRoster:NoSuchProject', ...
                'Project "%s" was removed by another session.', pid);
        end
        for f = epsych.SubjectRoster.SESSION_FIELDS
            rec.(f{1}) = tpl.(f{1});
        end

        rec.Added     = datetime('now');
        rec.Modified  = rec.Added;

        r.Memberships = [r.Memberships, rec];
    end

end
