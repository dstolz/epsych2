function refuseLinked_(self, registryId, exceptSubjectId)
% refuseLinked_(self, registryId, exceptSubjectId)
% Throw when another subject is already linked to this registry id.
%
% One animal in the registry is one subject here: two roster records sharing a
% link would send each one's sessions and weighings to the same animal, and
% nothing downstream could tell them apart again. An empty id (unlinked) never
% collides.
%
% Parameters:
%   registryId      - the id about to be stored.
%   exceptSubjectId - the subject being edited, which may keep its own link.
%
% Throws:
%   epsych:SubjectRoster:DuplicateRegistryID
%
% See also: epsych.SubjectRoster.findByRegistryID
arguments
    self
    registryId
    exceptSubjectId
end

registryId = strtrim(char(string(registryId)));
if isempty(registryId), return, end

other = self.findByRegistryID(registryId);
if ~isempty(other) && ~strcmp(other.SubjectID, char(string(exceptSubjectId)))
    error('epsych:SubjectRoster:DuplicateRegistryID', ...
        'Registry subject "%s" is already linked to "%s" in the roster.', ...
        registryId, other.Name);
end
