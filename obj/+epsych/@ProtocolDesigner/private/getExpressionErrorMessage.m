function message = getExpressionErrorMessage(obj, parameter)
    message = '';
    userData = obj.TableParams.UserData;
    if isempty(userData) || ~isstruct(userData) || ~isfield(userData, 'ExpressionErrors')
        return
    end

    errorEntries = userData.ExpressionErrors;
    for idx = 1:numel(errorEntries)
        if isequal(errorEntries(idx).parameter, parameter)
            message = errorEntries(idx).message;
            return
        end
    end
end

