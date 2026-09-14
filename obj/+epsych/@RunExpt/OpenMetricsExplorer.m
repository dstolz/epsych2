function OpenMetricsExplorer(self)
% OpenMetricsExplorer(self)
% Open the psychophysics metrics explorer.
%
% A reference window rather than a session tool: it maps d', criterion and the
% rest of psychophysics.Metrics over the whole hit-rate/false-alarm plane, which
% is what answers "is that d' plausible?" or "which way does c go?" without
% anyone re-deriving the formula. It reads no hardware and holds no runtime, so
% it stays available at every program state, including mid-run.
%
% RunExpt keeps no handle: the explorer owns its own window and lifecycle.
%
% See also: gui.MetricsExplorer, psychophysics.Metrics,
%   documentation/gui/gui_MetricsExplorer.md
arguments
    self
end

% The window is not modal and can outlive an always-on-top main figure, which
% would otherwise cover it.
self.AlwaysOnTop(false);

try
    gui.MetricsExplorer;
catch ME
    vprintf(0, 1, ME);
    uialert(self.H.figure1, ...
        sprintf('The metrics explorer could not be opened:\n\n%s', ME.message), ...
        'EPsych', 'Icon', 'error');
end
