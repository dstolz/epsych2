function OpenSessionForReview(self, datafile)
% OpenSessionForReview(self, datafile)
% Reopen a saved session in its behavior GUI, with a trial scrubber.
%
% Available in every program state, and while a session is running: a review
% reads a file, attaches hw.Replay backends to a runtime of its own, and never
% touches this session's CONFIG, hardware or timer. An operator wanting to
% compare today's run against yesterday's should not have to stop today's.
%
% The behavior GUI is resolved by epsych.ReviewSession -- this session's
% FUNCS.BehaviorGUI first, since the operator set up for this paradigm is
% usually the one reviewing it -- so nothing needs to be passed on.
%
% RunExpt keeps no handle: the review owns its own windows and lifecycle, and
% closing them ends it.
%
% Parameters:
%   self     - epsych.RunExpt.
%   datafile - Session .mat, crash-recovery .mat, or .epj. Omitted opens a
%              picker rooted at this rig's data path.
%
% See also: epsych.ReviewSession, gui.ReviewTransport,
%   documentation/epsych/epsych_ReviewSession.md

arguments
    self
    datafile (1,:) char = ''
end

% Neither the picker nor the review is modal, and an always-on-top main window
% would sit over both.
self.AlwaysOnTop(false);

if isempty(datafile)
    datafile = epsych.ReviewSession.pickFile(localStartPath(self));
    if isempty(datafile)
        return
    end
end

try
    epsych.ReviewSession(datafile);
catch ME
    vprintf(0, 1, ME);
    uialert(self.H.figure1, ...
        sprintf('This session could not be opened for review:\n\n%s', ME.message), ...
        'EPsych', 'Icon', 'error');
end

end




function p = localStartPath(self)
% p = localStartPath(self)
%
% Where the file picker opens: this rig's data path, which is where sessions
% are written. Returned with a trailing separator so uigetfile treats it as a
% folder to open rather than a filename to preselect.

p = '';

try
    root = char(self.DefaultDataPath);
    if ~isempty(root) && isfolder(root)
        p = [root filesep];
    end
catch ME
    vprintf(3, 'epsych.RunExpt: no default data path to start the review picker in (%s)', ME.message)
end

end
