function f = configuredFile()
% f = epsych.SubjectRoster.configuredFile()
% The roster file this workstation is pointed at.
%
% A lab shares one roster by putting it on a network drive and setting this
% preference on each rig. Unset, the per-user fallback is returned so the
% manager still works on a fresh machine.
%
% Returns:
%   f - full path to the .esub file (which need not exist yet).
%
% See also: epsych.SubjectRoster.setConfiguredFile, epsych.SubjectRoster.defaultFile

f = '';
if ispref('ep_RunExpt_Subjects', 'RosterFile')
    f = char(getpref('ep_RunExpt_Subjects', 'RosterFile'));
end

if isempty(strtrim(f))
    f = epsych.SubjectRoster.defaultFile();
end
