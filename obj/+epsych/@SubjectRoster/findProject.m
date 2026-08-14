function [rec, idx] = findProject(self, key)
% [rec, idx] = findProject(self, key)
% Look up a project by ProjectID or by Name.
%
% ID first and exactly, Name second and case-insensitively — same rule as
% findSubject.
%
% Parameters:
%   key - ProjectID or Name.
%
% Returns:
%   rec - the matching record, or a 0x0 struct when there is no match.
%   idx - index into Projects, or [] when there is no match.
%
% See also: epsych.SubjectRoster.findSubject, epsych.SubjectRoster.addProject
arguments
    self
    key (1,:) char
end

rec = epsych.SubjectRoster.emptyProject();
idx = [];

if isempty(self.Projects) || isempty(key), return, end

hit = find(strcmp({self.Projects.ProjectID}, key), 1);
if isempty(hit)
    hit = find(strcmpi({self.Projects.Name}, key), 1);
end
if isempty(hit), return, end

idx = hit;
rec = self.Projects(hit);
