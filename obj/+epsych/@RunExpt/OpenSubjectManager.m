function OpenSubjectManager(self)
% OpenSubjectManager(self)
% Open the Subjects & Projects manager for this session.
%
% This is the operator's entry point for putting subjects into a session; the
% old one-at-a-time Add Subject dialog is reached from inside it as
% "New Subject...". Like the self-test window it stays available while a
% session is running -- reading an animal's notes mid-run is reasonable, and it
% is the "Add Checked to Session" action, not the window, that refuses.
%
% RunExpt keeps no handle: the manager owns its own window and lifecycle.
%
% See also: gui.SubjectManager, epsych.SubjectRoster,
%   documentation/gui/gui_SubjectManager.md
arguments
    self
end

% The window is not modal and can outlive an always-on-top main figure, which
% would otherwise cover it.
self.AlwaysOnTop(false);

try
    gui.SubjectManager(self);
catch ME
    vprintf(0, 1, ME);
    uialert(self.H.figure1, ...
        sprintf('The Subjects & Projects window could not be opened:\n\n%s', ME.message), ...
        'EPsych', 'Icon', 'error');
end
