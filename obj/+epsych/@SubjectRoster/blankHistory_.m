function h = blankHistory_()
% h = epsych.SubjectRoster.blankHistory_()
% Scalar protocol-history entry with every field at its default.
%
% Returns:
%   h - (1,1) struct.
%
% See also: epsych.SubjectRoster.emptyHistory_, epsych.SubjectRoster.pushHistory_

h = struct( ...
    'File',    '', ...   % full path to the .eprot
    'Version', '', ...   % its protocolVersion when recorded
    'Stamp',   NaT);     % when it was recorded
