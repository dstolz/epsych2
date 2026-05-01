function update_signal_plot(obj)
% update_signal_plot(obj) - Refresh the signal plot with the current bank item.
% Developer guide: documentation/stimgen/stimgen_StimPlayer.md
% Uses the listbox selection when idle; falls back to CurrentSPObj during playback.

h = obj.handles;
if ~isfield(h, 'SignalLine') || ~isvalid(h.SignalLine)
    return
end

% Prefer the GUI-selected item; fall back to playback cursor
sp = [];
if isfield(h, 'BankList') && isvalid(h.BankList) && ~isempty(h.BankList.Value)
    idx = h.BankList.Value;
    if idx >= 1 && idx <= numel(obj.StimPlayObjs)
        sp = obj.StimPlayObjs(idx);
    end
end
if isempty(sp)
    sp = obj.CurrentSPObj;
end

if isempty(sp)
    set(h.SignalLine, 'XData', nan, 'YData', nan);
    return
end

stimObj = sp.CurrentStimObj;
if isempty(stimObj.Signal)
    stimObj.update_signal;
end

if ~isempty(stimObj.Signal)
    set(h.SignalLine, 'XData', stimObj.Time, 'YData', stimObj.Signal);
else
    set(h.SignalLine, 'XData', nan, 'YData', nan);
end
end
