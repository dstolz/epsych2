function s = blankSubject_()
% s = epsych.SubjectRoster.blankSubject_()
% Scalar subject record with every field at its default.
%
% This is the single authority for the subject field set: emptySubject derives
% the 0x0 form from it, and normalize_ uses it to fill fields a file written by
% an older build is missing.
%
% Returns:
%   s - (1,1) struct.
%
% See also: epsych.SubjectRoster.emptySubject, epsych.SubjectRoster.normalize_

s = struct( ...
    'SubjectID',    '', ...  % minted, immutable; see epsych.SubjectRoster.newId
    'Name',         '', ...  % mutable, but see the rename block in updateSubject
    'Sex',          '', ...
    'Species',      '', ...
    'Weight',       NaN, ... % NaN = not measured, matching epsych.Subject
    'Notes',        '', ...
    'NameHistory',  {strings(1,0)}, ... % every prior Name, appended on rename
    'Retired',      false, ...          % global; distinct from per-project Active
    'ImportedFrom', '', ...             % source .ecfg when created by importFromConfig
    'Created',      NaT, ...
    'Modified',     NaT);
