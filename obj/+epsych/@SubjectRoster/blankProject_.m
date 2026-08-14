function p = blankProject_()
% p = epsych.SubjectRoster.blankProject_()
% Scalar project record with every field at its default.
%
% Single authority for the project field set; see blankSubject_ for why.
%
% Every default here has to mean what an older file implicitly meant, because
% normalize_ fills a missing field from this template rather than migrating:
% no investigator, no links, and not archived are all correct readings of a
% roster written before those fields existed.
%
% Returns:
%   p - (1,1) struct.
%
% See also: epsych.SubjectRoster.emptyProject, epsych.SubjectRoster.normalize_

p = struct( ...
    'ProjectID',       '', ...
    'Name',            '', ...
    'Notes',           '', ...
    'Investigator',    '', ...  % who is responsible for the study
    'IACUCProtocol',   '', ...  % animal-use protocol number, for the record
    'DefaultProtocol', '', ...  % .eprot applied to members that have none
    'DefaultDataPath', '', ...
    'BoxGUI',          '', ...  % '' inherits the session default; see BOXGUI_NONE
    ...                         % Cell-wrapped: struct() replicates a struct-array
    ...                         % value, which would build one project per link.
    'Links',           {epsych.SubjectRoster.emptyLink()}, ...
    'Archived',        false, ...  % hidden from the project list, never deleted
    'Created',         NaT, ...
    'Modified',        NaT);
