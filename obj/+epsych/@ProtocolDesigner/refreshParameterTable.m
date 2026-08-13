function refreshParameterTable(obj)
% refreshParameterTable(obj)
% Rebuild the parameter table from the current interface and module filters.
    filterIndex = obj.selectedFilterIndex();
    [tableData, parameterHandles] = obj.getParameterTableData(filterIndex, obj.getSelectedModuleRow());
    obj.ParameterHandles = parameterHandles;
    obj.TableParams.ColumnFormat = {'char', 'char', obj.getTypeOptions(), 'char', 'char', 'numeric', 'numeric', 'logical', obj.getPairDropdownOptions(), obj.getAccessOptions(), 'char', 'logical', 'logical', 'logical', 'logical', 'char'};
    obj.TableParams.Data = tableData;
    obj.SelectedParamRow = 0;
    obj.SelectedParamCol = 0;

    % Full column widths: Interface/Module, Name, Type, Expression, Value,
    %   Min, Max, Random, Pair, Access, Unit, Visible, Trigger, Update Every Trial, Set Once, Description
    fullWidths = {186, 138, 92, 178, 128, 58, 58, 66, 92, 96, 64, 58, 58, 100, 66, 190};
    if strcmp(obj.DropDownTableView.Value, 'Simple')
        % Show: Interface/Module(1), Name(2), Type(3), Expression(4), Value(5)
        % Scale widths proportionally to fill the ~1265px usable table width
        obj.TableParams.ColumnWidth = {286, 210, 128, 316, 268, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
    else
        obj.TableParams.ColumnWidth = fullWidths;
    end

    obj.applyExpressionErrorStyles();
end

