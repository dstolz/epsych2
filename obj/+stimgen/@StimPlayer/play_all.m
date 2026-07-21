function play_all(obj, src, ~)
% play_all(obj)
% play_all(obj, src)
% Play all variant combinations for the selected bank stimulus through speakers.
%
% Parameters:
%   src - Optional button handle used to flash active playback state

h = obj.handles;

% Use the listbox-selected item, not the playback cursor.
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
    stimgen.util.vprintf(1, 'StimPlayer: no stimulus selected for play-all preview.');
    obj.show_gui_message_("Select a stimulus before using Play All.", ...
        "Nothing To Preview", "warning");
    return
end

stimObj = sp.CurrentStimObj;
info = stimObj.get_variant_info();
numCombos = info.NumCombinations;
if numCombos < 1
    obj.show_gui_message_("The selected stimulus has no playable combinations.", ...
        "Empty Variants", "warning");
    return
end

activeBtn = [];
if nargin >= 2 && ~isempty(src) && isvalid(src) && isprop(src, 'BackgroundColor')
    activeBtn = src;
elseif isfield(h, 'PlayAllBtn') && ~isempty(h.PlayAllBtn) && isvalid(h.PlayAllBtn)
    activeBtn = h.PlayAllBtn;
end

prevColor = [];
if ~isempty(activeBtn)
    prevColor = activeBtn.BackgroundColor;
    activeBtn.BackgroundColor = [0.2 1.0 0.2];
end

restoreObj = onCleanup(@() restore_play_all_ui_(obj, activeBtn, prevColor));

try
    if isfield(h, 'PlayBtn') && ~isempty(h.PlayBtn) && isvalid(h.PlayBtn)
        h.PlayBtn.Enable = 'off';
    end
    if isfield(h, 'PlayAllBtn') && ~isempty(h.PlayAllBtn) && isvalid(h.PlayAllBtn)
        h.PlayAllBtn.Enable = 'off';
    end

    for comboIdx = 1:numCombos
        stimObj.set_variant_index(comboIdx);
        obj.refresh_combo_controls_;
        obj.update_signal_plot;
        drawnow;

        if isempty(stimObj.Signal)
            stimObj.update_signal;
        end

        if isempty(stimObj.Signal)
            error('StimPlayer:EmptySignal', ...
                'Stimulus combination %d did not produce a signal for preview.', comboIdx);
        end

        obj.set_status_(sprintf('Previewing combo %d of %d.', comboIdx, numCombos));
        stimgen.util.vprintf(1, 'StimPlayer: previewing "%s" combo %d/%d via speakers...', ...
            sp.Name, comboIdx, numCombos);
        stimObj.play;

        if comboIdx < numCombos
            obj.get_isi_;
            pause(obj.currentISI);
        end
    end

    obj.set_status_(sprintf('Finished Play All (%d combinations).', numCombos));
catch ME
    obj.report_gui_error_(ME, "Play All Error", ...
        "StimPlayer could not preview all combinations for the selected stimulus.");
end

clear restoreObj;
end


function restore_play_all_ui_(obj, activeBtn, prevColor)
h = obj.handles;
if isfield(h, 'PlayBtn') && ~isempty(h.PlayBtn) && isvalid(h.PlayBtn)
    h.PlayBtn.Enable = 'on';
end
if isfield(h, 'PlayAllBtn') && ~isempty(h.PlayAllBtn) && isvalid(h.PlayAllBtn)
    h.PlayAllBtn.Enable = 'on';
end
if ~isempty(activeBtn) && isvalid(activeBtn) && ~isempty(prevColor)
    activeBtn.BackgroundColor = prevColor;
end
end
