function onToggleTableView(obj)
% onToggleTableView(obj)
% Toggle the parameter table between Simple and Detailed views.
    currentMode = char(obj.DropDownTableView.Value);
    if strcmp(currentMode, 'Simple')
        nextMode = 'Detailed';
    else
        nextMode = 'Simple';
    end

    obj.DropDownTableView.Value = nextMode;
    obj.saveGuiPreference('TableViewMode', nextMode);
    obj.refreshParameterTable();
    obj.setStatus(sprintf('Switched to %s parameter view', nextMode), ...
        'Use Ctrl+Shift+D to open details for the selected parameter.');
end