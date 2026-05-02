function setStatus(obj, message, nextStep)
% setStatus(obj, message, nextStep)
% Update the footer status bar with the latest action and suggested next step.
%
% Parameters:
% 	message	 - Primary status text shown in the footer.
% 	nextStep - Suggested next action (default: state-dependent hint).
    if nargin < 2
        message = 'Ready';
    end

    if nargin < 3 || strlength(strtrim(string(nextStep))) == 0
        nextStep = obj.suggestNextStep();
    end

    obj.StatusBar.setStatus(char(string(message)), char(string(nextStep)));
end