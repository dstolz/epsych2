function [rec, idx] = findByRegistryID(self, registryId)
% [rec, idx] = findByRegistryID(self, registryId)
% Look up the subject linked to an animal in the lab's subject registry.
%
% Kept apart from findSubject on purpose: findSubject resolves what an
% operator typed (an ID or a Name), and folding registry ids into it would let
% a new subject's name collide with another subject's link. The match is exact
% and case-sensitive, as registry ids are.
%
% Parameters:
%   registryId - the registry's id for the animal (e.g. 'SUBJ-ID-421').
%
% Returns:
%   rec - the matching record, or a 0x0 struct when none is linked to it.
%   idx - index into Subjects, or [] when none is linked to it.
%
% See also: epsych.SubjectRoster.findSubject, epsych.SubjectRegistry
arguments
    self
    registryId
end

rec = epsych.SubjectRoster.emptySubject();
idx = [];

registryId = strtrim(char(string(registryId)));
if isempty(self.Subjects) || isempty(registryId), return, end

hit = find(strcmp({self.Subjects.RegistryID}, registryId), 1);
if isempty(hit), return, end

idx = hit;
rec = self.Subjects(hit);
