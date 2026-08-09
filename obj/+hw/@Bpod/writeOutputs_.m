function writeOutputs_(obj, options)
% writeOutputs_(obj, Force=false)
% Emit the absolute state of the output shadow to the device.
%
% Sends, in order and only for the groups that changed:
%   ['O' 'V' valveMask]        valves 1-8, channel n is bit n-1
%   ['O' 'P' pwm1 ... pwm8]    port LED PWM duty, one byte per port
%   ['O' 'B' bncMask]          BNC outputs 1-2
%   ['O' 'W' wireMask]         wire outputs 1-4
%
% None of these produce a reply (firmware manualOverrideOutputs), so nothing is
% read back here. Reading after them would consume the first byte of whatever
% the device pushes next.
%
% The mask layout is transcribed from Bpod's ManualOverride.m, which builds the
% valve byte as bin2dec(num2str(Valves(8:-1:1))) and the wire byte to match
% SetWireOutputLines' bitRead(WireState, x) for x = 0..3: channel 1 is the LSB.
%
% Deferral: while a state matrix is running the FSM drives every one of these
% lines at each transition (setStateOutputs), so an override written now is
% clobbered within 100 us. The shadow is left updated and the write is skipped.
% The last-written record is dropped at the same time, because the firmware
% zeroes all four groups when the matrix ends - so the first write after a
% trial must be unconditional.
%
% Parameters:
%   obj            - hw.Bpod instance.
%   options.Force  - logical (default=false). Write every group even when it
%                    matches the last write. Does not override the mid-matrix
%                    deferral, which is a hardware fact rather than a policy.
%
% See also: hw.Bpod.flushOutputs, hw.Bpod.resetShadow_, documentation/hw/hw_Bpod.md

arguments
    obj
    options.Force (1,1) logical = false
end

% Offline: the shadow is still the authoritative model, it simply has nowhere
% to go. ProtocolDesigner edits an unconnected interface all the time. Forget
% the last-written masks on the way out - a board that is reconnected has
% rebooted with every line low, so nothing may be assumed about it afterwards.
if ~obj.linkReady_ || isempty(obj.HW)
    local_forgetRecord(obj);
    return
end

if obj.matrixRunning_ || obj.awaitingEpilogue_
    local_forgetRecord(obj);
    return
end

valveMask = local_mask(obj.valves_);
bncMask   = local_mask(obj.bncOut_);
wireMask  = local_mask(obj.wireOut_);
pwmBytes  = uint8(min(255, max(0, round(obj.pwm_(:).'))));

rec = local_record(obj);

% A trial that ran since the last write left the device's lines low, whatever
% the record says. trialNum_ advances once per matrix, so comparing it catches
% the case where no writeOutputs_ call happened during the trial to notice.
force = options.Force || ~isequal(rec.T, obj.trialNum_);

sent = true;

if force || ~isequal(rec.V, valveMask)
    sent = local_emit(obj, [uint8('O') uint8('V') valveMask]) && sent;
    rec.V = valveMask;
end

if force || ~isequal(rec.P, pwmBytes)
    sent = local_emit(obj, [uint8('O') uint8('P') pwmBytes]) && sent;
    rec.P = pwmBytes;
end

if force || ~isequal(rec.B, bncMask)
    sent = local_emit(obj, [uint8('O') uint8('B') bncMask]) && sent;
    rec.B = bncMask;
end

if force || ~isequal(rec.W, wireMask)
    sent = local_emit(obj, [uint8('O') uint8('W') wireMask]) && sent;
    rec.W = wireMask;
end

if sent
    rec.T = obj.trialNum_;
    local_storeRecord(obj, rec);
else
    % One of the writes did not reach the device, so what the lines are doing
    % is no longer known. Drop the record entirely and let the next call send
    % all four groups again.
    local_forgetRecord(obj);
end

end


function m = local_mask(lines)
% m = local_mask(lines)
% Pack a shadow row vector into an output bitmask; channel n is bit n-1.
m = uint8(0);
active = lines(:).' ~= 0;
for k = 1:numel(active)
    if active(k)
        m = bitset(m, k);
    end
end
end


function ok = local_emit(obj, bytes)
% ok = local_emit(obj, bytes)
% Write one override command. A transport failure degrades to a logged
% warning: writeOutputs_ runs from delete() and from trial boundaries, where
% throwing would take the session down with it.
ok = false;
try
    obj.write_(uint8(bytes));
    ok = true;
catch ME
    vprintf(0, 1, 'Bpod: writing an output override failed: %s', ME.message);
end
end


function rec = local_record(obj)
% rec = local_record(obj)
% Last-written masks, or NaN placeholders when nothing is on record.
%
% The record lives in a reserved field of inputCache_ because the classdef
% pins the property list and has no slot for it. readInput_ keys that struct
% by channel ('P1', 'B2', 'W4', ...), so there is no collision, and any code
% that resets inputCache_ merely forces one redundant - and harmless, since
% these writes are absolute and idempotent - refresh of all four groups.
rec = struct('V', NaN, 'P', NaN, 'B', NaN, 'W', NaN, 'T', NaN);
if ~isstruct(obj.inputCache_) || ~isfield(obj.inputCache_, 'lastOutputWrite_')
    return
end
stored = obj.inputCache_.lastOutputWrite_;
if isstruct(stored) && isscalar(stored) && all(isfield(stored, {'V', 'P', 'B', 'W', 'T'}))
    rec = stored;
end
end


function local_storeRecord(obj, rec)
% local_storeRecord(obj, rec)
% Persist the last-written masks.
if ~isstruct(obj.inputCache_)
    obj.inputCache_ = struct();
end
obj.inputCache_.lastOutputWrite_ = rec;
end


function local_forgetRecord(obj)
% local_forgetRecord(obj)
% Drop the last-written masks so the next write is unconditional.
if isstruct(obj.inputCache_) && isfield(obj.inputCache_, 'lastOutputWrite_')
    obj.inputCache_ = rmfield(obj.inputCache_, 'lastOutputWrite_');
end
end
