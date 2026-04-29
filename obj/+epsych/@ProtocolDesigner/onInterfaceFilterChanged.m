function onInterfaceFilterChanged(obj)
% onInterfaceFilterChanged(obj)
% Responds to a change in the interface filter dropdown by updating the
% ColorBy default and refreshing the parameter table.
%
% When "All Interfaces" is selected the ColorBy default is "Interface".
% When any individual interface is selected the ColorBy default is "Type".

    if strcmp(obj.DropDownInterfaceFilter.Value, 'All Interfaces')
        obj.DropDownColorBy.Value = 'Interface';
    else
        obj.DropDownColorBy.Value = 'Type';
    end

    obj.refreshParameterTable();
end
