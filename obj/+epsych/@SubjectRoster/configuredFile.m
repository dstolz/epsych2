function f = configuredFile()
% f = epsych.SubjectRoster.configuredFile()
% The roster file this workstation is pointed at, or '' when none is set.
%
% There is deliberately no default. Where a lab's animal records live is a
% decision only the lab can make -- one shared file on a network drive, or a
% private one per workstation -- and a guess would put the only copy somewhere
% nobody looks. So the empty string is a real answer, meaning "ask", and the
% first thing that would write to the roster does exactly that; see
% gui.SubjectManager.ensureRoster_.
%
% Returns:
%   f - full path to the .esub file (which need not exist yet), or ''.
%
% See also: epsych.SubjectRoster.setConfiguredFile, epsych.SubjectRoster.isConfigured

f = '';
if ispref('ep_RunExpt_Subjects', 'RosterFile')
    f = char(getpref('ep_RunExpt_Subjects', 'RosterFile'));
end

f = strtrim(f);
