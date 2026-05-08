function y = trim_response_(obj, y)
% y = trim_response_(obj, y)
% Remove trailing buffer padding and trim leading propagation delay.
% Only contiguous trailing zeros are stripped; mid-signal zeros
% (valid zero crossings) are preserved.
lastNZ = find(y ~= 0, 1, 'last');
if ~isempty(lastNZ)
    y = y(1:lastNZ);
end

% Clip first ~3 ms: acoustic propagation delay at ~343 m/s.
trimSamps = round(3e-3 * obj.Fs);
if numel(y) > trimSamps
    y = y(trimSamps + 1 : end);
end
end
