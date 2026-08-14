function OpenParameterDebugger(self)
% OpenParameterDebugger(self)
% Open the parameter debugger for this session.
%
% Like the self-test window, this one stays available while a session is
% running -- reading a parameter off the hardware mid-run is exactly what an
% operator wants when a paradigm is behaving oddly, and the window never reads
% anything on its own, so having it open changes nothing.
%
% It is also useful with a config merely loaded: the protocol's interfaces
% exist from that point on, and the debugger lists them whether or not they are
% connected.
%
% RunExpt keeps no handle: the debugger owns its own window and lifecycle.
%
% See also: gui.ParameterDebugger, hw.Parameter,
%   documentation/gui/gui_ParameterDebugger.md
arguments
    self
end

% The window is not modal and can outlive an always-on-top main figure, which
% would otherwise cover it.
self.AlwaysOnTop(false);

try
    gui.ParameterDebugger(self);
catch ME
    vprintf(0, 1, ME);
    uialert(self.H.figure1, ...
        sprintf('The parameter debugger could not be opened:\n\n%s', ME.message), ...
        'EPsych', 'Icon', 'error');
end
