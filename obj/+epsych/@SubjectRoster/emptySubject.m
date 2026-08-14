function s = emptySubject()
% s = epsych.SubjectRoster.emptySubject()
% Canonical empty subject record: 0x0 struct with every field present.
%
% Concatenation is how records are appended ([arr, rec]), and MATLAB rejects
% that when the two operands disagree on fields — so the empty value must carry
% the full field set, not be [] or struct(). Derived from blankSubject_ so the
% field list lives in exactly one place.
%
% Returns:
%   s - 0x0 struct with the subject field set.
%
% See also: epsych.SubjectRoster.blankSubject_, epsych.SubjectRoster.emptyProject

s = epsych.SubjectRoster.blankSubject_();
s(1) = [];
