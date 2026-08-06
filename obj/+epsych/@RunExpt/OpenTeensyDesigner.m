function OpenTeensyDesigner(self)
% OpenTeensyDesigner(self)
% Open the Teensy Trial Designer, bound to this session when one is loaded.
%
% With a RUNTIME available the designer attaches to it and enters live
% monitor mode: it follows the session's mode changes and highlights the
% state the board is currently in. That is the view an operator wants when a
% paradigm is behaving oddly mid-experiment, so the window is available while
% a session runs -- editing locks itself while the session is in Preview or
% Record, rather than the window being unavailable.
%
% Without a RUNTIME it opens on a blank program, which is the ordinary
% design-time entry point.
%
% See also: teensy.TrialDesigner, teensy.Program,
%   documentation/teensy/teensy_TrialDesigner_UserGuide.md

arguments
    self
end

% The designer is not modal and can outlive an always-on-top main figure,
% which would otherwise cover it.
self.AlwaysOnTop(false);

try
    if isempty(self.RUNTIME) || ~isvalid(self.RUNTIME)
        teensy.TrialDesigner();
    else
        teensy.TrialDesigner(self.RUNTIME);
    end
catch ME
    vprintf(0, 1, ME);
    uialert(self.H.figure1, ...
        sprintf('The Teensy Trial Designer could not be opened:\n\n%s', ME.message), ...
        'EPsych', 'Icon', 'error');
end
