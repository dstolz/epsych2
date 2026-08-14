function m = emptyMembership()
% m = epsych.SubjectRoster.emptyMembership()
% Canonical empty membership record: 0x0 struct with every field present.
%
% See emptySubject for why the empty value carries the full field set.
%
% Returns:
%   m - 0x0 struct with the membership field set.
%
% See also: epsych.SubjectRoster.blankMembership_, epsych.SubjectRoster.emptySubject

m = epsych.SubjectRoster.blankMembership_();
m(1) = [];
