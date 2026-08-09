function OpenSelfTest(self)
% OpenSelfTest(self)
% Open the pre-flight self-test window for this session.
%
% Unlike the other dialogs, this one is available while a session is running:
% the read-only checks are exactly what an operator wants when something is
% behaving oddly mid-experiment, and the checks that would touch live state
% refuse to run in that case.
%
% See also: gui.SelfTest, epsych.SelfTest,
%   documentation/overviews/RunExpt_SelfTest.md
arguments
    self
end

% The window is not modal and can outlive an always-on-top main figure, which
% would otherwise cover it.
self.AlwaysOnTop(false);

try
    gui.SelfTest(self);
catch ME
    vprintf(0, 1, ME);
    uialert(self.H.figure1, ...
        sprintf('The self-test window could not be opened:\n\n%s', ME.message), ...
        'EPsych', 'Icon', 'error');
end
