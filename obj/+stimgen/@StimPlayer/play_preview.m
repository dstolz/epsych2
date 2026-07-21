function play_preview(obj, src, ~)
% play_preview(obj) - Play the currently selected stimulus through the computer speakers.
% Flashes the Play button green during playback.

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
    stimgen.util.vprintf(1, 'StimPlayer: no stimulus selected for preview.');
    obj.show_gui_message_("Select a stimulus before previewing it.", ...
        "Nothing To Preview", "warning");
    return
end

stimObj = sp.CurrentStimObj;
btn = [];
if nargin >= 2 && ~isempty(src) && isvalid(src) && isprop(src, 'BackgroundColor')
    btn = src;
elseif isfield(obj.handles, 'PlayBtn') && ~isempty(obj.handles.PlayBtn) && isvalid(obj.handles.PlayBtn)
    btn = obj.handles.PlayBtn;
end

if ~isempty(btn)
    prevColor = btn.BackgroundColor;
    cleanupObj = onCleanup(@() restore_button_color_(btn, prevColor));
else
    cleanupObj = onCleanup(@() []);
end

try
    if isempty(stimObj.Signal)
        stimObj.update_signal;
    end

    if ~isempty(btn)
        btn.BackgroundColor = [0.2 1.0 0.2];
    end
    drawnow;

    stimgen.util.vprintf(1, 'StimPlayer: playing "%s" via speakers...', sp.Name);
    obj.set_status_("Previewing: " + string(sp.Name));
    stimObj.play;
catch ME
    obj.report_gui_error_(ME, "Preview Error", ...
        "StimPlayer could not preview the selected stimulus.");
end

clear cleanupObj;
end


function restore_button_color_(btn, colorValue)
if ~isempty(btn) && isvalid(btn)
    btn.BackgroundColor = colorValue;
end
end
