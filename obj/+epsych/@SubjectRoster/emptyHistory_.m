function h = emptyHistory_()
% h = epsych.SubjectRoster.emptyHistory_()
% Canonical empty protocol-history array: 1x0 struct with every field present.
%
% One entry per protocol a membership has been pointed at, most recent first,
% capped at PROTOCOL_HISTORY_LIMIT. It is what makes "revert to the previous
% protocol" answerable — the roster is the only thing that ever knew which file
% and version a subject was on, since saving an .eprot overwrites it in place.
%
% Returns:
%   h - (1,0) struct with the history field set.
%
% See also: epsych.SubjectRoster.blankHistory_, epsych.SubjectRoster.rememberProtocol,
%   epsych.SubjectRoster.revertProtocol

h = epsych.SubjectRoster.blankHistory_();
h(1) = [];
