function deleteSubject(self, id)
% deleteSubject(self, id)
% Remove a subject from the roster along with all of its memberships.
%
% Deletion is unconditional here; the guard rails belong to the caller. The GUI
% confirms, lists every project the subject will vanish from, and refuses
% outright when the subject is in the live session. Nothing on disk is touched:
% saved experiment data outlives the roster record.
%
% Retiring is almost always what an operator actually wants — see setActive.
%
% Parameters:
%   id - SubjectID or Name.
%
% Throws:
%   epsych:SubjectRoster:NoSuchSubject
%
% See also: epsych.SubjectRoster.setActive, epsych.SubjectRoster.unassign
arguments
    self
    id (1,:) char
end

[rec, idx] = self.findSubject(id);
if isempty(idx)
    error('epsych:SubjectRoster:NoSuchSubject', 'No subject matches "%s".', id);
end

subjectId = rec.SubjectID;
name      = rec.Name;

self.mutate_(@applyDelete);

vprintf(1, 'Deleted subject "%s" from the roster.', name);

    function applyDelete(r)
        [~, k] = r.findSubject(subjectId);
        if isempty(k), return, end   % another session already removed it

        r.Subjects(k) = [];

        if ~isempty(r.Memberships)
            drop = strcmp({r.Memberships.SubjectID}, subjectId);
            r.Memberships(drop) = [];
        end
    end

end
