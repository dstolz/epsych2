function L = emptyLink()
% L = epsych.SubjectRoster.emptyLink()
% Canonical empty link array: 0x0 struct with every field present.
%
% See emptySubject for why the empty value carries the full field set.
%
% Returns:
%   L - 0x0 struct with the link field set.
%
% See also: epsych.SubjectRoster.blankLink_, epsych.SubjectRoster.makeLink

L = epsych.SubjectRoster.blankLink_();
L(1) = [];
