function setActive(self, subjectId, projectId, tf)
% setActive(self, subjectId, projectId, tf)
% Retire a subject from one project, or restore it.
%
% Per-membership, not global: an animal finished in one study stays active in
% another. Retired subjects are hidden from the picker by default but keep
% their protocol memory, which is what makes this reversible in one click and
% deleteSubject a last resort.
%
% Parameters:
%   subjectId - SubjectID or subject Name.
%   projectId - ProjectID or project Name.
%   tf        - true to make active, false to retire.
%
% Throws:
%   epsych:SubjectRoster:NoSuchMembership
%
% See also: epsych.SubjectRoster.subjectsInProject, epsych.SubjectRoster.unassign
arguments
    self
    subjectId (1,:) char
    projectId (1,:) char
    tf (1,1) logical
end

[rec, idx] = self.findMembership(subjectId, projectId);
if isempty(idx)
    error('epsych:SubjectRoster:NoSuchMembership', ...
        'Subject "%s" is not in project "%s".', subjectId, projectId);
end

sid = rec.SubjectID;
pid = rec.ProjectID;

% Resolve display names before mutating: callers pass IDs, and a log line
% naming 'S_20260814T103018_8c006d' tells an operator nothing.
sName = localName(self.findSubject(sid), sid);
pName = localName(self.findProject(pid), pid);

self.mutate_(@applySetActive);

if tf
    vprintf(1, 'Restored subject "%s" in project "%s".', sName, pName);
else
    vprintf(1, 'Retired subject "%s" from project "%s".', sName, pName);
end

    function applySetActive(r)
        [~, k] = r.findMembership(sid, pid);
        if isempty(k)
            error('epsych:SubjectRoster:NoSuchMembership', ...
                'The membership was removed by another session.');
        end
        r.Memberships(k).Active   = tf;
        r.Memberships(k).Modified = datetime('now');
    end

end

% -----------------------------------------------------------------------
function n = localName(rec, fallback)
% Display name of a found record, or the key when the lookup missed.
n = fallback;
if ~isempty(rec)
    n = rec.Name;
end
end
