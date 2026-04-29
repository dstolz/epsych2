function warningText = getTrialFunctionPathWarning(~, trialFuncName)
    trialFuncName = strtrim(char(string(trialFuncName)));
    if isempty(trialFuncName)
        warningText = '';
        return
    end

    if isempty(which(trialFuncName))
        warningText = sprintf('Warning: trial function "%s" is not currently on the MATLAB path.', trialFuncName);
    else
        warningText = '';
    end
end
