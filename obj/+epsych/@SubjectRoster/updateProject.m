function updateProject(self, id, P)
% updateProject(self, id, P)
% Edit a project record in place.
%
% Only the fields present in P are touched. ProjectID and Created are
% engine-owned and ignored if supplied. A project has no data folder of its
% own, so unlike a subject it can always be renamed.
%
% Links and Archived are handled apart from the text fields because they are
% not text: char(string(...)) would turn a link array into a character matrix
% and false into the empty string.
%
% Parameters:
%   id - ProjectID or current Name.
%   P  - struct carrying the fields to change. Build a Links change by
%        assigning the field (P.Links = ...); struct('Links', L) would make one
%        struct per link rather than one struct holding them all.
%
% Throws:
%   epsych:SubjectRoster:NoSuchProject
%   epsych:SubjectRoster:InvalidName
%   epsych:SubjectRoster:DuplicateName
%   epsych:SubjectRoster:UnsafeLink
%
% See also: epsych.SubjectRoster.addProject, epsych.SubjectRoster.deleteProject,
%   epsych.SubjectRoster.makeLink
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

% Refused before the file is touched, so a bad address cannot be half-written.
newLinks = [];
if isfield(P, 'Links')
    newLinks = epsych.SubjectRoster.normalizeLinks_(P.Links, Validate = true);
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

        for f = ["Name" "Notes" "Investigator" "IACUCProtocol" ...
                 "DefaultProtocol" "DefaultDataPath" "BoxGUI"]
            if isfield(P, f)
                cur.(f) = char(string(P.(f)));
            end
        end

        if isfield(P, 'Links')
            cur.Links = newLinks;
        end

        if isfield(P, 'Archived')
            cur.Archived = localToLogical(P.Archived);
        end

        cur.Modified = datetime('now');

        r.Projects(k) = cur;
    end

end

% -----------------------------------------------------------------------
function tf = localToLogical(v)
% Accept what a checkbox, a script, or a hand-edited struct is likely to hold.
if ischar(v) || isstring(v)
    tf = any(strcmpi(char(v), {'true','yes','on','1'}));
else
    tf = ~isempty(v) && logical(v(1));
end
end
