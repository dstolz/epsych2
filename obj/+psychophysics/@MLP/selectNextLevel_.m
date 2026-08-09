function level = selectNextLevel_(obj, sweetPoints, responses)
% level = selectNextLevel_(obj, sweetPoints, responses)
% Select the signal strength for the next trial from the set of sweet points
% using the configured SweetPointRule. The "Random" rule draws uniformly from
% all sweet points on every trial. The "UpDown" rule implements a generalized
% N-down M-up staircase that cycles through sweet points ordered from low to
% high signal strength: N consecutive correct responses step down to the next
% lower sweet point; M consecutive incorrect responses step up to the next
% higher sweet point.
%
% UpDown state (sweetPointIdx_, correctStreak_, incorrectStreak_,
% lastResponseCount_) is maintained as private object properties and persists
% across calls. The state is updated only when new responses have arrived
% since the last call, preventing spurious updates on manual refresh() calls.
%
% Parameters:
%   sweetPoints - Column vector of sweet-point signal strengths (ascending).
%   responses   - (1 x nTrials) binary response vector from the active trial window.
%
% Returns:
%   level - Signal strength to present on the next trial.

nSP = numel(sweetPoints);

switch obj.SweetPointRule
    case "Random"
        level = sweetPoints(randi(nSP));

    case "UpDown"
        nDown = obj.UpDownRule(1);
        nUp   = obj.UpDownRule(2);

        % Clamp index to [1, nSP] to handle PsychometricFunction changes
        obj.sweetPointIdx_ = min(max(obj.sweetPointIdx_, 1), nSP);

        nResp = numel(responses);
        if nResp > obj.lastResponseCount_
            lastResp = responses(end);

            if lastResp == 1  % correct
                obj.correctStreak_   = obj.correctStreak_ + 1;
                obj.incorrectStreak_ = 0;
                if obj.correctStreak_ >= nDown
                    % N correct: step down to next lower sweet point
                    obj.sweetPointIdx_ = max(1, obj.sweetPointIdx_ - 1);
                    obj.correctStreak_ = 0;
                end
            else  % incorrect or lapse
                obj.incorrectStreak_ = obj.incorrectStreak_ + 1;
                obj.correctStreak_   = 0;
                if obj.incorrectStreak_ >= nUp
                    % M incorrect: step up to next higher sweet point
                    obj.sweetPointIdx_ = min(nSP, obj.sweetPointIdx_ + 1);
                    obj.incorrectStreak_ = 0;
                end
            end
        end

        obj.lastResponseCount_ = nResp;
        level = sweetPoints(obj.sweetPointIdx_);
end
