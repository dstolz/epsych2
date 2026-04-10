function setStatus(obj, message, nextStep)
% setStatus(obj, message, nextStep)
% Update the footer status label with the latest action and suggested next step.
%
% Parameters:
% 	message	- Primary status text shown first in the footer.
% 	nextStep	- Suggested next action (default: state-dependent hint).
    if nargin < 2
        message = 'Ready';
    end

    message = strtrim(char(string(message)));
    if nargin < 3 || strlength(strtrim(string(nextStep))) == 0
        nextStep = obj.suggestNextStep();
    else
        nextStep = strtrim(char(string(nextStep)));
    end

    if isempty(message)
        message = 'Ready';
    end

    if isempty(nextStep)
        obj.LabelStatus.Text = message;
    else
        obj.LabelStatus.Text = sprintf('%s  Next: %s', message, nextStep);
    end

    [backgroundColor, fontColor] = localGetStatusColors_(message, nextStep);
    obj.LabelStatus.BackgroundColor = backgroundColor;
    obj.LabelStatus.FontColor = fontColor;
end

function [backgroundColor, fontColor] = localGetStatusColors_(message, nextStep)
    statusText = lower(strtrim(char(join(string({message, nextStep}), ' '))));
    errorPatterns = {
        'error', ...
        'failed', ...
        'compile failed', ...
        'not found', ...
        'invalid', ...
        'mismatch', ...
        'cannot', ...
        'must ', ...
        'no interface selected', ...
        'no module selected', ...
        'no parameter selected', ...
        'no target module selected', ...
        'no writable parameters', ...
        'no interfaces defined', ...
        'not accessible', ...
        'fix the ', ...
        'resolve the ', ...
        'outside bounds', ...
        'read-only'};

    isError = any(cellfun(@(pattern) contains(statusText, pattern), errorPatterns));
    if isError
        backgroundColor = [1.00 0.90 0.90];
        fontColor = [0.56 0.10 0.10];
    else
        backgroundColor = [0.90 0.97 0.90];
        fontColor = [0.12 0.34 0.18];
    end
end