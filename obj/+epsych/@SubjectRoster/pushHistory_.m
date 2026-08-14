function h = pushHistory_(history, file, version)
% h = epsych.SubjectRoster.pushHistory_(history, file, version)
% Put one protocol at the head of a membership's history.
%
% Most recent first, de-duplicated on file+version, and capped at
% PROTOCOL_HISTORY_LIMIT. De-duplication is what keeps the list a list of
% *distinct* protocols a subject has been on: bouncing between two files for a
% week must leave both offered, not one of them twenty times.
%
% Parameters:
%   history - existing (1,:) history struct array, possibly empty or malformed.
%   file    - full path to the .eprot being pushed.
%   version - its protocolVersion, or '' when unknown.
%
% Returns:
%   h - (1,:) history struct array.
%
% See also: epsych.SubjectRoster.emptyHistory_, epsych.SubjectRoster.revertProtocol
arguments
    history
    file (1,:) char
    version (1,:) char = ''
end

h = epsych.SubjectRoster.normalize_(history, epsych.SubjectRoster.blankHistory_());

if isempty(file), return, end

entry = struct('File', file, 'Version', version, 'Stamp', datetime('now'));

if ~isempty(h)
    dupe = strcmp({h.File}, file) & strcmp({h.Version}, version);
    h = h(~dupe);
end

h = [entry, h];

limit = epsych.SubjectRoster.PROTOCOL_HISTORY_LIMIT;
if numel(h) > limit
    h = h(1:limit);
end
