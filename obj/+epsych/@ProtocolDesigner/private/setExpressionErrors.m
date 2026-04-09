function setExpressionErrors(obj, errorEntries)
    userData = obj.TableParams.UserData;
    if isempty(userData) || ~isstruct(userData)
        userData = struct();
    end
    userData.ExpressionErrors = errorEntries;
    obj.TableParams.UserData = userData;
end

