function setConfiguredFile(filePath)
% epsych.SubjectRoster.setConfiguredFile(filePath)
% Point this workstation at a roster file.
%
% Pass '' to clear the preference and fall back to the per-user file. The file
% need not exist: it is created on the first mutation, which is what lets an
% operator name a new shared roster before there is anything to put in it.
%
% Parameters:
%   filePath - full path to a .esub file, or '' to clear.
%
% See also: epsych.SubjectRoster.configuredFile, epsych.RunExpt.DefineRosterFile
arguments
    filePath (1,:) char
end

if isempty(strtrim(filePath))
    if ispref('ep_RunExpt_Subjects', 'RosterFile')
        rmpref('ep_RunExpt_Subjects', 'RosterFile');
    end
    vprintf(1, 'Subject roster path cleared; using the per-user file.');
    return
end

setpref('ep_RunExpt_Subjects', 'RosterFile', filePath);
vprintf(1, 'Subject roster file set to: %s', filePath);
