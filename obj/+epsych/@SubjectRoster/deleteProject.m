function deleteProject(self, id)
% deleteProject(self, id)
% Remove a project and the memberships pointing at it.
%
% Subjects are never deleted with a project. Deleting the study an animal
% happened to be enrolled in must not delete the animal — it may well be in
% another project, and its saved data outlives both.
%
% Parameters:
%   id - ProjectID or Name.
%
% Throws:
%   epsych:SubjectRoster:NoSuchProject
%
% See also: epsych.SubjectRoster.deleteSubject, epsych.SubjectRoster.unassign
arguments
    self
    id (1,:) char
end

[rec, idx] = self.findProject(id);
if isempty(idx)
    error('epsych:SubjectRoster:NoSuchProject', 'No project matches "%s".', id);
end

projectId = rec.ProjectID;
name      = rec.Name;

self.mutate_(@applyDelete);

vprintf(1, 'Deleted project "%s"; its subjects were kept.', name);

    function applyDelete(r)
        [~, k] = r.findProject(projectId);
        if isempty(k), return, end

        r.Projects(k) = [];

        if ~isempty(r.Memberships)
            drop = strcmp({r.Memberships.ProjectID}, projectId);
            r.Memberships(drop) = [];
        end
    end

end
