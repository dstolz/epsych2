function r = responseBits(responseCodes, bits)
% r = epsych.BitMask.responseBits(responseCodes)
% r = epsych.BitMask.responseBits(responseCodes, bits)
% The one outcome each response code was scored as, for labelling and
% colouring a trial by it.
%
% A code may carry several flags (Hit with Reward, a TrialType bit); this
% picks the trial's outcome out of them. Each trial gets the LAST member of
% BITS that its code carries, or Undefined when it carries none -- a trial
% nobody answered in a forced choice, or one never scored.
%
% This is the rule psychophysics.Psych.responseBits applies and
% gui.components.History labels its rows by. It lives here so that an
% analysis object which provides response codes but is not a Psych
% (psychophysics.Detection) gets the same labels from the same rule.
%
% Parameters:
%   responseCodes - uint32-compatible array of epsych.BitMask codes.
%   bits          - epsych.BitMask outcomes to look for, in increasing
%                   priority. Default epsych.BitMask.getResponses (Hit,
%                   Miss, CorrectReject, FalseAlarm, Abort).
%
% Returns:
%   r - Row of epsych.BitMask values, one per code.
%
% See also epsych.BitMask.decode, epsych.BitMask.getResponses

arguments
    responseCodes
    bits (1,:) epsych.BitMask = epsych.BitMask.getResponses
end

if isempty(responseCodes)
    r = epsych.BitMask.empty(1,0);
    return
end

decoded = epsych.BitMask.decode(uint32(responseCodes));
r = repmat(epsych.BitMask(0), size(responseCodes));
for bm = bits
    ind = decoded.(char(bm));
    if any(ind(:))
        r(ind) = bm;
    end
end
r = reshape(r, 1, []);
end
