function [rec, idx] = findSubject(self, key)
% [rec, idx] = findSubject(self, key)
% Look up a subject by SubjectID or by Name.
%
% ID is tried first and exactly; Name second and case-insensitively. Callers
% that hold an ID therefore never risk hitting a same-named record, while
% callers that only know what the operator typed still resolve.
%
% Parameters:
%   key - SubjectID or Name.
%
% Returns:
%   rec - the matching record, or a 0x0 struct when there is no match.
%   idx - index into Subjects, or [] when there is no match.
%
% See also: epsych.SubjectRoster.findProject, epsych.SubjectRoster.addSubject
arguments
    self
    key (1,:) char
end

rec = epsych.SubjectRoster.emptySubject();
idx = [];

if isempty(self.Subjects) || isempty(key), return, end

hit = find(strcmp({self.Subjects.SubjectID}, key), 1);
if isempty(hit)
    hit = find(strcmpi({self.Subjects.Name}, key), 1);
end
if isempty(hit), return, end

idx = hit;
rec = self.Subjects(hit);
