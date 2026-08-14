function m = blankMembership_()
% m = epsych.SubjectRoster.blankMembership_()
% Scalar membership record with every field at its default.
%
% Membership is the join between subjects and projects. It carries its own
% attributes, which is why it is a table rather than a list of IDs on either
% side: the same animal can be active in one study and retired from another,
% running a different protocol in each.
%
% Returns:
%   m - (1,1) struct.
%
% See also: epsych.SubjectRoster.emptyMembership, epsych.SubjectRoster.normalize_

m = struct( ...
    'SubjectID',    '', ...
    'ProjectID',    '', ...
    'Active',       true, ... % the per-project archive flag
    'LastProtocol', '', ...   % .eprot this subject last ran in this project
    'LastBoxID',    NaN, ...  % NaN when never run
    'Added',        NaT, ...
    'Modified',     NaT);
