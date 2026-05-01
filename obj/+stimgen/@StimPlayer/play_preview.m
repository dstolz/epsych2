function play_preview(obj, ~, ~)
% play_preview(obj) - Play the currently selected stimulus through the computer speakers.
% Flashes the Play Stim button green during playback.

h = obj.handles;

% Use the listbox-selected item, not the playback cursor
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
    vprintf(1, 'StimPlayer: no stimulus selected for preview.');
    return
end

stimObj = sp.CurrentStimObj;
if isempty(stimObj.Signal)
    stimObj.update_signal;
end

h = obj.handles.PlayStimBtn;
prevColor = h.BackgroundColor;
h.BackgroundColor = [0.2 1.0 0.2];
drawnow;

vprintf(1, 'StimPlayer: playing "%s" via speakers...', sp.Name);
stimObj.play;

h.BackgroundColor = prevColor;
end
