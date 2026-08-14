function p = emptyProject()
% p = epsych.SubjectRoster.emptyProject()
% Canonical empty project record: 0x0 struct with every field present.
%
% See emptySubject for why the empty value carries the full field set.
%
% Returns:
%   p - 0x0 struct with the project field set.
%
% See also: epsych.SubjectRoster.blankProject_, epsych.SubjectRoster.emptySubject

p = epsych.SubjectRoster.blankProject_();
p(1) = [];
