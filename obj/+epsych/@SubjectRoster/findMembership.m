function [rec, idx] = findMembership(self, subjectId, projectId)
% [rec, idx] = findMembership(self, subjectId, projectId)
% Look up the join record tying one subject to one project.
%
% Both keys are resolved through findSubject/findProject first, so a Name works
% as well as an ID.
%
% Parameters:
%   subjectId - SubjectID or subject Name.
%   projectId - ProjectID or project Name.
%
% Returns:
%   rec - the matching record, or a 0x0 struct when there is no match.
%   idx - index into Memberships, or [] when there is no match.
%
% See also: epsych.SubjectRoster.assign, epsych.SubjectRoster.setActive
arguments
    self
    subjectId (1,:) char
    projectId (1,:) char
end

rec = epsych.SubjectRoster.emptyMembership();
idx = [];

s = self.findSubject(subjectId);
p = self.findProject(projectId);
if isempty(s) || isempty(p) || isempty(self.Memberships), return, end

hit = find(strcmp({self.Memberships.SubjectID}, s.SubjectID) & ...
           strcmp({self.Memberships.ProjectID}, p.ProjectID), 1);
if isempty(hit), return, end

idx = hit;
rec = self.Memberships(hit);
