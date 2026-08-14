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
        rec.Added     = datetime('now');
        rec.Modified  = rec.Added;

        r.Memberships = [r.Memberships, rec];
    end

end
