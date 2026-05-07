function tf = local_test(fcn, val, pat)
    % tf = local_test(fcn, val, pat)
    % Normalize any comparison result to a logical scalar.
    %
    % Parameters:
    %   fcn - Comparison function; e.g. @isequal, @contains, @regexp.
    %   val - Value from the Parameter property.
    %   pat - Pattern or target value passed to fcn.
    %
    % Returns:
    %   tf - True if fcn indicates a match.
    res = fcn(val, pat);
    if islogical(res) && isscalar(res)
        tf = res;
    elseif isnumeric(res)
        % numeric (e.g. regexp indices) -> match if non-empty
        tf = ~isempty(res);
    elseif iscell(res)
        % cell of matches -> match if any non-empty element
        tf = any(~cellfun(@isempty, res));
    else
        tf = ~isempty(res);
    end
end
