function c = responseCodeColors_(obj, responseCodes)
% c = responseCodeColors_(obj, responseCodes)
% Map response codes to hex colors for staircase point markers.
%
% Parameters:
%   obj — psychophysics.Staircase instance
%   responseCodes — numeric vector of encoded response codes
%
% Returns:
%   c — Nx1 string array of hex colors

n = numel(responseCodes);
c = repmat(obj.NeutralColor, n, 1);

if n == 0
    return
end

decoded = epsych.BitMask.decode(responseCodes);

c(decoded.Hit) = obj.HitColor;
c(decoded.Miss) = obj.MissColor;
c(decoded.Abort) = obj.AbortColor;
c(decoded.CorrectReject) = obj.CorrectRejectionColor;
c(decoded.FalseAlarm) = obj.FalseAlarmColor;