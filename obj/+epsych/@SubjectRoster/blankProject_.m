function p = blankProject_()
% p = epsych.SubjectRoster.blankProject_()
% Scalar project record with every field at its default.
%
% Single authority for the project field set; see blankSubject_ for why.
%
% Returns:
%   p - (1,1) struct.
%
% See also: epsych.SubjectRoster.emptyProject, epsych.SubjectRoster.normalize_

p = struct( ...
    'ProjectID',       '', ...
    'Name',            '', ...
    'Notes',           '', ...
    'DefaultProtocol', '', ...  % .eprot applied to members that have none
    'DefaultDataPath', '', ...
    'BoxGUI',          '', ...  % '' inherits the session default; see BOXGUI_NONE
    'Created',         NaT, ...
    'Modified',        NaT);
