function refreshParameterTable(obj)
    filterIndex = obj.selectedFilterIndex();
    [tableData, parameterHandles] = obj.getParameterTableData(filterIndex, obj.getSelectedModuleRow());
    obj.ParameterHandles = parameterHandles;
    obj.TableParams.ColumnFormat = {'char', 'char', 'char', obj.getTypeOptions(), 'char', obj.getPairDropdownOptions(), 'char', 'numeric', 'numeric', 'logical', obj.getAccessOptions(), 'char', 'logical', 'logical', 'char'};
    obj.TableParams.Data = tableData;
    obj.SelectedParamRow = 0;
    obj.SelectedParamCol = 0;

    % Full column widths: Interface, Module, Name, Type, Expression, Pair,
    %   Value, Min, Max, Random, Access, Unit, Visible, Trigger, Description
    fullWidths = {88, 132, 112, 78, 148, 84, 104, 58, 58, 66, 88, 64, 58, 58, 170};
    if strcmp(obj.DropDownTableView.Value, 'Simple')
        % Show: Interface(1), Module(2), Name(3), Type(4), Expression(5), Value(7)
        % Scale widths proportionally to fill the ~860px usable table width
        obj.TableParams.ColumnWidth = {114, 171, 146, 101, 192, 0, 136, 0, 0, 0, 0, 0, 0, 0, 0};
    else
        obj.TableParams.ColumnWidth = fullWidths;
    end

    obj.applyExpressionErrorStyles();
end

