function refreshParameterTable(obj)
    filterIndex = obj.selectedFilterIndex();
    [tableData, parameterHandles] = obj.getParameterTableData(filterIndex, obj.getSelectedModuleRow());
    obj.ParameterHandles = parameterHandles;
    obj.TableParams.Data = tableData;
    obj.SelectedParamRow = 0;
    obj.applyExpressionErrorStyles();
end

