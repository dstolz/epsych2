function warningText = getTrialFunctionPathWarning(~, trialFuncName)
% warningText = getTrialFunctionPathWarning(~, trialFuncName)
% Return a warning message when the selected trial function is not on the MATLAB path.
%
% Parameters:
%	trialFuncName	- Trial function name to validate.
%
% Returns:
%	warningText	- Empty text when the function is resolvable, otherwise a warning message.
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
