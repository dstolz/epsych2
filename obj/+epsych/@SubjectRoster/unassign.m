function unassign(self, subjectId, projectId)
% unassign(self, subjectId, projectId)
% Take a subject out of a project.
%
% The subject record itself is untouched, as is its membership in every other
% project. This drops the join record and with it that project's protocol
% memory for the subject; setActive is the non-destructive alternative.
%
% Parameters:
%   subjectId - SubjectID or subject Name.
%   projectId - ProjectID or project Name.
%
% See also: epsych.SubjectRoster.assign, epsych.SubjectRoster.setActive
arguments
    self
    subjectId (1,:) char
    projectId (1,:) char
end

[rec, idx] = self.findMembership(subjectId, projectId);
if isempty(idx)
    vprintf(2, 'unassign: "%s" is not in "%s"; nothing to do.', subjectId, projectId);
    return
end

sid = rec.SubjectID;
pid = rec.ProjectID;

% Callers pass IDs; resolve names so the log line is readable.
s = self.findSubject(sid);
p = self.findProject(pid);
sName = sid; if ~isempty(s), sName = s.Name; end
pName = pid; if ~isempty(p), pName = p.Name; end

self.mutate_(@applyUnassign);

vprintf(1, 'Removed subject "%s" from project "%s".', sName, pName);

    function applyUnassign(r)
        [~, k] = r.findMembership(sid, pid);
        if isempty(k), return, end
        r.Memberships(k) = [];
    end

end
