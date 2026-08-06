function result = set_parameter(obj, name, value)
% result = set_parameter(obj, name, value)
% Write one or more parameters.
%
% Output writes update an absolute local shadow and are then emitted as a
% full mask by writeOutputs_. Bpod's own ManualOverride is never used: it is
% toggle-based, mutates HardwareState behind your back, disables sibling GUI
% buttons, and reads three of its data bytes out of console edit boxes.
%
% Parameters
%   name  - Parameter name(s), or hw.Parameter handle(s).
%   value - Scalar (expanded across all targets) or per-target values.
%
% Returns:
%   result - True when the write was accepted, deferred, or had no device
%            side (host-side trial configuration and read-only results).
%
% See also: hw.Bpod.get_parameter, hw.Bpod.flushOutputs,
%           documentation/hw/hw_Bpod.md

if isa(name, 'hw.Parameter')
    P = name;
else
    P = obj.find_parameter(name, includeInvisible = true);
end

if isempty(P)
    result = false;
    return
end

if ~iscell(value)
    value = {value};
end
if isscalar(value) && ~isscalar(P)
    value = repmat(value, size(P));
end

result = true;

% Offline writes are a no-op. hw.Parameter.set.Value has already stored the
% value locally, which is what ProtocolDesigner reads back, and there is no
% transport to emit on.
if ~obj.IsConnected
    return
end

outputsTouched = false;

for i = 1:numel(P)
    % Trial results are filled from the event stream. A write is a no-op
    % rather than a failure so that a generic parameter sweep cannot stall
    % the session on a parameter it was never meant to drive.
    if strcmp(P(i).Access, 'Read')
        continue
    end

    wire = hw.Interface.getHardwareParameterName(P(i));
    [kind, idx] = decodeOutputName_(wire);

    switch kind
        case 'valve'
            obj.valves_(idx) = double(toNumber_(value{i}) ~= 0);
            outputsTouched = true;

        case 'pwm'
            obj.pwm_(idx) = clampByte_(toNumber_(value{i}));
            outputsTouched = true;

        case 'bncout'
            obj.bncOut_(idx) = double(toNumber_(value{i}) ~= 0);
            outputsTouched = true;

        case 'wireout'
            obj.wireOut_(idx) = double(toNumber_(value{i}) ~= 0);
            outputsTouched = true;

        case 'serialbyte'
            % Momentary and safe mid-trial: 'H' takes no reply, so it cannot
            % desynchronize the event stream, and the state machine has no
            % serial output state to clobber. Nothing is retained.
            obj.write_(uint8([double('H'), idx, clampByte_(toNumber_(value{i}))]));

        case 'softcode'
            % Also momentary, and deliberately not deferred: a soft code is
            % only useful while the matrix that waits on it is running.
            obj.sendSoftCode(toNumber_(value{i}));

        otherwise
            % Host-side trial configuration consumed by StateMatrixFcn, or a
            % parameter the operator added in ProtocolDesigner. There is
            % nothing to emit; hw.Parameter already holds the value.
            vprintf(4, 'hw.Bpod: "%s" has no device write; value kept host-side', wire);
    end
end

if ~outputsTouched
    return
end

if obj.matrixRunning_ || obj.awaitingEpilogue_
    % Deferred on purpose. An 'O' write mid-trial is safe on the wire (no
    % reply byte to desynchronize the stream), but the state machine
    % rewrites every output line at its next state transition, so the write
    % would land and then silently disappear. The shadow is already correct;
    % trigger's x_ResetTrig_ handler re-asserts it at the trial boundary.
    vprintf(3, 'hw.Bpod: output write deferred to the trial boundary (matrix running)');
    return
end

obj.writeOutputs_();
end


% ------------------------------------------------------------------------
function [kind, idx] = decodeOutputName_(wire)
% [kind, idx] = decodeOutputName_(wire)
% Classify a wire name into a writable Bpod output family and channel.
%
% kind is '' for anything the device cannot be told about, which includes
% every host-side parameter. Only writable families are recognized here;
% the read-side classifier lives in get_parameter.

kind = '';
idx  = 0;

tok = regexp(wire, '^Valve([1-8])$', 'tokens', 'once');
if ~isempty(tok), kind = 'valve'; idx = str2double(tok{1}); return, end

tok = regexp(wire, '^PWM([1-8])$', 'tokens', 'once');
if ~isempty(tok), kind = 'pwm'; idx = str2double(tok{1}); return, end

tok = regexp(wire, '^BNCOut([1-2])$', 'tokens', 'once');
if ~isempty(tok), kind = 'bncout'; idx = str2double(tok{1}); return, end

tok = regexp(wire, '^WireOut([1-4])$', 'tokens', 'once');
if ~isempty(tok), kind = 'wireout'; idx = str2double(tok{1}); return, end

tok = regexp(wire, '^Serial([1-2])Byte$', 'tokens', 'once');
if ~isempty(tok), kind = 'serialbyte'; idx = str2double(tok{1}); return, end

if strcmp(wire, 'SoftCode')
    kind = 'softcode';
end
end


% ------------------------------------------------------------------------
function v = toNumber_(x)
% v = toNumber_(x)
% Coerce a parameter value to a scalar double.
%
% Values arrive from the trial table, from a GUI edit field, or from a
% direct assignment, so char, string, logical, and singleton-cell forms all
% turn up. Anything unusable becomes 0 rather than an error: an exception
% here would propagate out of hw.Parameter.set.Value mid-dispatch.

if iscell(x)
    if isempty(x)
        v = 0;
        return
    end
    x = x{1};
end

if islogical(x) || isnumeric(x)
    if isempty(x)
        v = 0;
    else
        v = double(x(1));
    end
elseif ischar(x) || isstring(x)
    v = str2double(char(x));
    if isnan(v)
        v = 0;
    end
else
    v = 0;
end
end


% ------------------------------------------------------------------------
function b = clampByte_(v)
% b = clampByte_(v)
% Clamp a numeric value into the 0-255 range the firmware accepts.
%
% PWM duty and serial bytes are single unsigned bytes on the wire; an
% out-of-range value would wrap and drive an LED or a module to an
% unintended level.

if isnan(v)
    b = 0;
    return
end

b = round(v);
b = max(0, min(255, b));
end
