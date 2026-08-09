function onFindParameterChanged(obj, filterText)
% onFindParameterChanged(obj, filterText)
% Apply the Find box text as a name filter on the parameter table and report the
% match count. Called live while typing, so it only rebuilds the table.
%
% Parameters:
%	filterText	- Text to filter by (default: current Find box value).
    if nargin < 2
        filterText = obj.EditFindParam.Value;
    end

    filterText = strtrim(char(string(filterText)));
    if strcmp(filterText, obj.ParamNameFilter)
        return
    end

    obj.ParamNameFilter = filterText;
    obj.refreshParameterTable();

    matchCount = numel(obj.ParameterHandles);
    if isempty(obj.ParamNameFilter)
        obj.setStatus(sprintf('Showing all %d parameter(s)', matchCount), ...
            'Type in the Find box to narrow the table by parameter name.');
    elseif matchCount == 0
        obj.setStatus(sprintf('Nothing matches "%s"', obj.ParamNameFilter), ...
            'Clear the Find box, or use * and ? as wildcards to widen the search.');
    else
        obj.setStatus(sprintf('%d parameter(s) match "%s"', matchCount, obj.ParamNameFilter), ...
            'Clear the Find box to show every parameter, or press Ctrl+H to rename the matches.');
    end
end
