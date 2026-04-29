function refreshParameterTable(obj)
    filterIndex = obj.selectedFilterIndex();
    [tableData, parameterHandles] = obj.getParameterTableData(filterIndex, obj.getSelectedModuleRow());
    obj.ParameterHandles = parameterHandles;
    obj.TableParams.ColumnFormat = {'char', 'char', obj.getTypeOptions(), 'char', obj.getPairDropdownOptions(), 'char', 'numeric', 'numeric', 'logical', obj.getAccessOptions(), 'char', 'logical', 'logical', 'char'};
    obj.TableParams.Data = tableData;
    obj.SelectedParamRow = 0;
    obj.SelectedParamCol = 0;

    % Full column widths: Interface/Module, Name, Type, Expression, Pair,
    %   Value, Min, Max, Random, Access, Unit, Visible, Trigger, Description
    fullWidths = {154, 112, 78, 148, 84, 104, 58, 58, 66, 88, 64, 58, 58, 170};
    if strcmp(obj.DropDownTableView.Value, 'Simple')
        % Show: Interface/Module(1), Name(2), Type(3), Expression(4), Value(6)
        % Scale widths proportionally to fill the ~860px usable table width
        obj.TableParams.ColumnWidth = {200, 146, 101, 192, 0, 136, 0, 0, 0, 0, 0, 0, 0, 0};
    else
        obj.TableParams.ColumnWidth = fullWidths;
    end

    obj.applyExpressionErrorStyles();
end

