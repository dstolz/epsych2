function tf = isConfigured()
% tf = epsych.SubjectRoster.isConfigured()
% Has a roster file been chosen on this workstation?
%
% The file itself need not exist: naming a roster before there is anything to
% put in it is the normal way to start one. What this answers is whether the
% operator has made the choice, which is the thing that has no default.
%
% Returns:
%   tf - true when a roster path is recorded in the preferences.
%
% See also: epsych.SubjectRoster.configuredFile, epsych.SubjectRoster.setConfiguredFile

tf = ~isempty(epsych.SubjectRoster.configuredFile());
