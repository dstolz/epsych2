function ShowSubjectInManager(self, idx)
% ShowSubjectInManager(self, idx)
% Open the Subjects & Projects manager with this session subject selected.
%
% Makes the two windows navigable in both directions: the manager puts
% subjects into the session, and this brings the operator back the other way to
% see an animal's projects, notes, and history.
%
% A subject not in the roster is not an error — the manager opens on All
% Subjects and the status line says why.
%
% Parameters:
%   idx - row index; uses the selected row when omitted or NaN.
%
% See also: epsych.RunExpt.OpenSubjectManager, gui.SubjectManager.revealSubject
arguments
    self
    idx double = NaN
end

if isnan(idx)
    selection = self.H.subject_list.Selection;
    if isempty(selection)
        uialert(self.H.figure1, 'Select a subject first.', 'EPsych', 'Icon', 'info');
        return
    end
    idx = selection(1);
end

if isempty(idx) || idx > numel(self.CONFIG), return, end
if ~isa(self.CONFIG(idx).SUBJECT, 'epsych.Subject'), return, end

name = self.CONFIG(idx).SUBJECT.Name;

self.AlwaysOnTop(false);

try
    mgr = gui.SubjectManager(self);
    mgr.revealSubject(name);
catch ME
    vprintf(0, 1, ME);
    uialert(self.H.figure1, ...
        sprintf('The Subjects & Projects window could not be opened:\n\n%s', ME.message), ...
        'EPsych', 'Icon', 'error');
end
