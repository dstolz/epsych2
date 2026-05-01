function timer_stopfcn(obj, ~, ~)
% timer_stopfcn(obj) - Called when the playback timer stops.
% Resets button states and updates the counter.

obj.update_counter_;

h = obj.handles;
if isfield(h, 'RunBtn') && isvalid(h.RunBtn)
    h.RunBtn.Text = 'Run';
end
if isfield(h, 'PauseBtn') && isvalid(h.PauseBtn)
    h.PauseBtn.Enable = 'off';
    h.PauseBtn.Text   = 'Pause';
end

vprintf(2, 'StimPlayer timer stopped. %d presentations logged.', numel(obj.StimOrder));
end
