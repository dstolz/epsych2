function refreshParameterTable(obj)
    filterIndex = obj.selectedFilterIndex();
    [tableData, parameterHandles] = obj.getParameterTableData(filterIndex, obj.getSelectedModuleRow());
    obj.ParameterHandles = parameterHandles;
    obj.TableParams.ColumnFormat = {'char', 'char', 'char', obj.getTypeOptions(), 'char', obj.getPairDropdownOptions(), 'char', 'numeric', 'numeric', 'logical', obj.getAccessOptions(), 'char', 'logical', 'logical', 'char'};
    obj.TableParams.Data = tableData;
    obj.SelectedParamRow = 0;
    obj.applyExpressionErrorStyles();
end

