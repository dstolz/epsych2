function setStatus(self, message, nextStep)
% setStatus(self, message)
% setStatus(self, message, nextStep)
% Post a message to the session window's status bar.
%
% Parameters:
%	message		- What the program just did, in plain language.
%	nextStep	- Optional hint, appended as "Next: <nextStep>".
%
% Messages containing any gui.StatusBar.ErrorPatterns term are styled red;
% everything else is green.
%
% Never throws: the status bar is an aid, so a window that is mid-teardown
% must not take down the action that was reporting its progress.
%
% See also: gui.StatusBar, epsych.RunExpt.UpdateGUIstate
arguments
    self
    message  (1,:) char
    nextStep (1,:) char = ''
end

if ~isfield(self.H,'statusBar'), return, end
sb = self.H.statusBar;
if isempty(sb) || ~isvalid(sb), return, end

try
    sb.setStatus(message, nextStep);
    % The actions worth reporting (compiling, connecting hardware, saving)
    % block the event loop for seconds, so the label is painted here;
    % otherwise the operator only ever sees the last message of the sequence.
    drawnow limitrate
catch ME
    vprintf(3, 1, ME)
end
