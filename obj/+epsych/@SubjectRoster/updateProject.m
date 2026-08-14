function updateProject(self, id, P)
% updateProject(self, id, P)
% Edit a project record in place.
%
% Only the fields present in P are touched. ProjectID and Created are
% engine-owned and ignored if supplied. A project has no data folder of its
% own, so unlike a subject it can always be renamed.
%
% Parameters:
%   id - ProjectID or current Name.
%   P  - struct carrying the fields to change.
%
% Throws:
%   epsych:SubjectRoster:NoSuchProject
%   epsych:SubjectRoster:InvalidName
%   epsych:SubjectRoster:DuplicateName
%
% See also: epsych.SubjectRoster.addProject, epsych.SubjectRoster.deleteProject
arguments
    self
    id (1,:) char
    P (1,1) struct
end

[rec, idx] = self.findProject(id);
if isempty(idx)
    error('epsych:SubjectRoster:NoSuchProject', 'No project matches "%s".', id);
end

if isfield(P, 'Name')
    newName = char(string(P.Name));
    if ~strcmp(newName, rec.Name)
        [ok, why] = epsych.SubjectRoster.isNameSafe(newName);
        if ~ok
            error('epsych:SubjectRoster:InvalidName', '%s', why);
        end
        other = self.findProject(newName);
        if ~isempty(other) && ~strcmp(other.ProjectID, rec.ProjectID)
            error('epsych:SubjectRoster:DuplicateName', ...
                'A project named "%s" already exists.', newName);
        end
    end
end

projectId = rec.ProjectID;
self.mutate_(@applyUpdate);

vprintf(2, 'Updated project "%s".', rec.Name);

    function applyUpdate(r)
        [cur, k] = r.findProject(projectId);
        if isempty(k)
            error('epsych:SubjectRoster:NoSuchProject', ...
                'Project "%s" was removed by another session.', projectId);
        end

        for f = ["Name" "Notes" "DefaultProtocol" "DefaultDataPath" "BoxGUI"]
            if isfield(P, f)
                cur.(f) = char(string(P.(f)));
            end
        end
        cur.Modified = datetime('now');

        r.Projects(k) = cur;
    end

end
