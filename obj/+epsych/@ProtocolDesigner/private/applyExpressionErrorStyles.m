function applyExpressionErrorStyles(obj)
    try
        removeStyle(obj.TableParams);
    catch
    end

    userData = obj.TableParams.UserData;
    if isempty(userData) || ~isstruct(userData) || ~isfield(userData, 'ExpressionErrors')
        return
    end

    errorEntries = userData.ExpressionErrors;
    if isempty(errorEntries)
        return
    end

    errorRows = [];
    for rowIdx = 1:numel(obj.ParameterHandles)
        parameter = obj.ParameterHandles{rowIdx};
        if ~isempty(obj.getExpressionErrorMessage(parameter))
            errorRows(end + 1) = rowIdx; %#ok<AGROW>
        end
    end

    if isempty(errorRows)
        return
    end

    style = uistyle('BackgroundColor', [1.0 0.88 0.88], 'FontColor', [0.60 0.00 0.00]);
    addStyle(obj.TableParams, style, 'row', errorRows);
end

