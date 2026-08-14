function L = blankLink_()
% L = epsych.SubjectRoster.blankLink_()
% Scalar project-link record with every field at its default.
%
% A link is a label and an address and nothing more. Deliberately not a
% "resource" with a type, an owner, and a date: the roster's job is to remember
% where a project's lab notebook lives, not to become one.
%
% Returns:
%   L - (1,1) struct.
%
% See also: epsych.SubjectRoster.emptyLink, epsych.SubjectRoster.isSafeUrl,
%   epsych.SubjectRoster.normalizeLinks_

L = struct( ...
    'Label', '', ...   % what the operator sees; auto-filled from URL when blank
    'URL',   '');      % normalized by isSafeUrl before it is ever stored
