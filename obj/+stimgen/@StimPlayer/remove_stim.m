function remove_stim(obj, ~, ~)
% remove_stim(obj) - Remove the currently selected bank item.
% Deletes the corresponding StimPlay from StimPlayObjs,
% refreshes the listbox, and clears the tab group.

h = obj.handles;

if isempty(h.BankList.ItemsData) || isempty(h.BankList.Value)
    return
end

idx = h.BankList.Value;
if idx < 1 || idx > numel(obj.StimPlayObjs)
    return
end

name = obj.StimPlayObjs(idx).Name;
obj.StimPlayObjs(idx) = [];

obj.refresh_listbox_;

% Clear tab group back to placeholder
obj.clear_tabs_;

vprintf(2, 'StimPlayer: removed bank item "%s"', name);
