function setParameterNameFilter(obj, filterText)
% setParameterNameFilter(obj, filterText)
% Set the parameter table Find filter programmatically and sync the Find box.
% Does not refresh the table; callers refresh as part of their own update.
%
% Parameters:
%	filterText	- New filter text; empty shows every parameter.
    obj.ParamNameFilter = strtrim(char(string(filterText)));

    if isempty(obj.EditFindParam) || ~isvalid(obj.EditFindParam)
        return
    end
    obj.EditFindParam.Value = obj.ParamNameFilter;
end
