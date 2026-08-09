function v = readInput_(obj, kind, index)
% v = readInput_(obj, kind, index)
% Read one digital input line, subject to the mid-trial 'I' interlock.
%
% THE INTERLOCK IS THE POINT OF THIS FUNCTION. The firmware answers 'I' with a
% BARE, UNFRAMED byte written from the same 100 us ISR that streams framed
% [1 nEvents ev...] messages. An 'I' issued while a matrix is live therefore
% drops a naked byte into the middle of the event stream, where the pump reads
% it as an opcode. The protocol carries no CRC, sequence number, or resync
% marker, so the whole trial - every event and every timestamp after that point
% - is unrecoverable. While matrixRunning_ or awaitingEpilogue_ is set, this
% serves the cache and puts nothing on the wire.
%
% Outside a trial, reads are still served from cache for SnapshotInterval. That
% keeps the runtime's per-tick sweep over the input parameters from turning
% into one blocking USB round-trip per channel per tick.
%
% Polarity is transcribed from the firmware's own event detector so that a read
% can never disagree with the event stream:
%   'P' port  - HIGH is "in". Line 387 raises PortNIn on a LOW->HIGH edge; the
%               INPUT_PULLUP holds the line HIGH when the phototransistor stops
%               conducting, i.e. when the beam is broken.
%   'W' wire  - HIGH is "high" (line 413).
%   'B' BNC   - build-dependent. The firmware sets BNCHighLevel = 1 for builds
%               below 7 and 0 at 7 and above, because Bpod 0.7's optoisolator
%               inverts (lines 63-64, 144-146). FirmwareBuild is 0 until the
%               'F' handshake, which gives the 0.5/0.6 sense by default.
%
% Parameters:
%   obj   - hw.Bpod instance.
%   kind  - 'P' port, 'B' BNC, or 'W' wire.
%   index - One-based channel number; sent zero-based.
%
% Returns:
%   v - logical. True when the line is active in the sense above. Offline, or
%       whenever the device cannot be asked, the cached value is returned (or
%       false for a line never yet read). Never throws.
%
% See also: hw.Bpod.pump, hw.Bpod.get_parameter, documentation/hw/hw_Bpod.md

arguments
    obj
    kind (1,1) char {mustBeMember(kind, {'P', 'B', 'W'})}
    index (1,1) double {mustBeInteger, mustBePositive}
end

field = sprintf('%s%d', kind, index);

% Cached value, with "inactive" as the safe default for a never-read line.
v = false;
haveCache = isstruct(obj.inputCache_) && isfield(obj.inputCache_, field);
if haveCache
    v = obj.inputCache_.(field);
end

% --- Interlock -----------------------------------------------------------
if obj.matrixRunning_ || obj.awaitingEpilogue_
    return
end

% --- Reasons to stay on the cache ----------------------------------------
if ~obj.linkReady_ || isempty(obj.HW)
    return
end

if index > local_channelCount(kind)
    vprintf(0, 1, 'Bpod: input line %s does not exist on this device', field);
    return
end

if ~isempty(obj.rxBuf_)
    % Unparsed bytes mean a framed message is still in flight, which is the
    % same desynchronization hazard as reading during a trial.
    vprintf(2, 'Bpod: %d unparsed byte(s) pending, serving %s from cache', ...
        numel(obj.rxBuf_), field);
    return
end

if haveCache && local_cacheAge(obj, field) < obj.SnapshotInterval
    return
end

% --- Device read ---------------------------------------------------------
try
    obj.write_(uint8([double('I') double(kind) index - 1]));
    raw = obj.readExactly_(1, obj.Timeout);
catch ME
    vprintf(0, 1, 'Bpod: reading input line %s failed: %s', field, ME.message);
    return
end

if isempty(raw)
    % The reply may still be in flight and would then be read as the answer to
    % the NEXT request, or as an opcode by the pump. Nothing else is expected
    % on the wire here - no matrix is running and rxBuf_ is empty - so dropping
    % whatever arrives late is the safe move.
    vprintf(0, 1, 'Bpod: timed out reading input line %s, serving the cached value', field);
    try
        obj.flushInput_();
    catch ME
        vprintf(0, 1, ME);
    end
    return
end

v = local_lineActive(obj, kind, double(raw(1)));

if ~isstruct(obj.inputCache_)
    obj.inputCache_ = struct();
end
obj.inputCache_.(field) = v;

if ~isstruct(obj.inputCacheTic_)
    % Per-channel TTLs. inputCacheTic_ starts as [] and is reset to [] by the
    % connection lifecycle, so its type is checked rather than assumed.
    obj.inputCacheTic_ = struct();
end
obj.inputCacheTic_.(field) = tic;

end


function n = local_channelCount(kind)
% n = local_channelCount(kind)
% Number of channels the hardware has for this input type.
switch kind
    case 'P'
        n = 8;
    case 'B'
        n = 2;
    otherwise
        n = 4;
end
end


function age = local_cacheAge(obj, field)
% age = local_cacheAge(obj, field)
% Seconds since this channel was last read from the device; Inf when unknown.
age = Inf;
if ~isstruct(obj.inputCacheTic_) || ~isfield(obj.inputCacheTic_, field)
    return
end
try
    age = toc(obj.inputCacheTic_.(field));
catch
    % Not a tic handle, e.g. after a lifecycle reset parked something else
    % there. Treat as stale.
end
end


function tf = local_lineActive(obj, kind, raw)
% tf = local_lineActive(obj, kind, raw)
% Map a raw pin reading onto the active sense the firmware's event detector
% uses. Every polarity decision in this backend lives here.
if kind == 'B'
    bncHighLevel = 1;
    if obj.FirmwareBuild >= 7
        bncHighLevel = 0;  % inverting optoisolator, Bpod 0.7 and later
    end
    tf = raw == bncHighLevel;
else
    tf = raw ~= 0;
end
end
