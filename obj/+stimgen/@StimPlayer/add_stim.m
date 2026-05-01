function add_stim(obj, ~, ~)
% add_stim(obj) - Create a new StimPlay from the selected type and add to bank.
% Instantiates stimgen.<Type>, wraps in StimPlay with default Reps,
% appends to StimPlayObjs, refreshes the listbox, and selects the new item.

h = obj.handles;

typeName = h.TypeDropdown.Value;

% Create the StimType object
stimObj = stimgen.(typeName)();

% Wrap in StimPlay
sp              = stimgen.StimPlay(stimObj);
sp.Reps         = h.RepsField.Value;
sp.Name         = sprintf('%s_%d', typeName, numel(obj.StimPlayObjs) + 1);
sp.SelectionType = "Serial"; % within-stim selection (single StimObj, irrelevant)

obj.StimPlayObjs(end+1, 1) = sp;

obj.refresh_listbox_;

% Select the newly added item
h.BankList.Value = numel(obj.StimPlayObjs);
obj.on_bank_selection_changed(h.BankList, []);

vprintf(2, 'StimPlayer: added %s as "%s"', typeName, sp.Name);
