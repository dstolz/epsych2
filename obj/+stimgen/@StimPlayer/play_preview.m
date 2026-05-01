function play_preview(obj, ~, ~)
% play_preview(obj) - Play the currently selected stimulus through the computer speakers.
% Flashes the Play Stim button green during playback.

sp = obj.CurrentSPObj;
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
