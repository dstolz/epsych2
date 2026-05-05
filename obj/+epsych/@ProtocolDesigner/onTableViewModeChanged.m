function onTableViewModeChanged(obj)
% onTableViewModeChanged(obj)
% Save the selected parameter table view mode and refresh the table.
    mode = char(obj.DropDownTableView.Value);
    obj.saveGuiPreference('TableViewMode', mode);
    obj.refreshParameterTable();
    obj.setStatus(sprintf('%s parameter view selected', mode), ...
        'Use Ctrl+Shift+D to open details for the selected parameter.');
end