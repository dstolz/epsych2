function update_buffer(obj)
% update_buffer(obj) - Write the current stimulus signal to the hardware buffer.
% Uses double-buffering: TrigBufferID alternates 0/1 based on trialCount_.
% No-op if hardware parameters are not available.

if ~obj.HardwareAvailable
    return
end

sp = obj.CurrentSPObj;
if isempty(sp)
    return
end

obj.TrigBufferID = mod(obj.trialCount_, 2);
bid = obj.TrigBufferID;

% Zero-pad first and last sample (required by RPvds SerSource components)
buffer = [0, sp.Signal, 0];
nSamps = numel(buffer);

try
    obj.PARAMS.("BufferSize_" + string(bid)).Value = nSamps;
    obj.PARAMS.("BufferData_" + string(bid)).Value = buffer;
catch ME
    vprintf(0, 1, 'StimPlayer:update_buffer: failed to write buffer %d', bid);
    vprintf(0, 1, ME);
end

vprintf(4, 'StimPlayer:update_buffer: slot=%d  nSamps=%d', bid, nSamps);
end
