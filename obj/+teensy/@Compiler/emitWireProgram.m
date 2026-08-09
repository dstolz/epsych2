function [lines, iss] = emitWireProgram(obj, program)
% [lines, iss] = emitWireProgram(obj, program)
% Emit the wire records for a program.
%
% Assumes the program has already passed validation; compile() is the entry
% point that guarantees that. Emitting separately is what lets the designer
% show a preview of what would be sent.
%
% Indices on the wire are 1-based positions in the matching program array,
% matching what teensy.Condition.toPostfix and teensy.Action.toArgs resolve.
%
% Parameters
%   program - teensy.Program to emit.
%
% Returns:
%   lines - Cellstr of records, framed by PROG BEGIN / PROG END.
%   iss   - Issues raised while emitting, chiefly over-long records.
%
% See also: teensy.Compiler.compile, documentation/hw/hw_Teensy_Program_Protocol.md

arguments
    obj (1,1) teensy.Compiler
    program (1,1) teensy.Program
end

iss = teensy.issue();
rec = strings(0, 1);

% --- Header ---------------------------------------------------------------

rec(end+1) = sprintf("V %d %d %d %d %d %d", ...
    obj.FORMAT_VERSION, numel(program.States), numel(program.Channels), ...
    numel(program.Variables), numel(program.GlobalTimers), numel(program.Counters));

% --- Channels -------------------------------------------------------------

for i = 1:numel(program.Channels)
    c = program.Channels(i);

    if c.Direction == "Input"
        dir = "IN";
    else
        dir = "OUT";
    end

    if c.Kind == "Digital"
        kind = "DIG";
    else
        kind = "ANA";
    end

    flags = 0;
    if c.ActiveHigh,             flags = bitor(flags, 1); end
    if c.PullMode == "PullUp",   flags = bitor(flags, 2); end
    if c.PullMode == "PullDown", flags = bitor(flags, 4); end
    if c.IdleState == 1,         flags = bitor(flags, 8); end

    p = localChannelParams_(c);

    rec(end+1) = sprintf("C %d %s %s %s %d %d %s %s %s %s", ...
        i, c.Name, dir, kind, c.Pin, flags, p(1), p(2), p(3), p(4));
end

% --- Variables ------------------------------------------------------------

for i = 1:numel(program.Variables)
    v = program.Variables(i);

    switch v.Type
        case "Integer", typeCode = "I";
        case "Boolean", typeCode = "B";
        otherwise,      typeCode = "F";
    end

    rec(end+1) = sprintf("K %d %s %s %s %s %s", i, v.Name, typeCode, ...
        teensy.Compiler.wireValue(v.Value, program), ...
        localBound_(v.Min), localBound_(v.Max));
end

% --- Global timers --------------------------------------------------------

for i = 1:numel(program.GlobalTimers)
    T = program.GlobalTimers(i);
    rec(end+1) = sprintf("G %d %s %s", i, T.Name, ...
        teensy.Compiler.wireValue(T.DurationMs, program));
end

% --- Counters -------------------------------------------------------------

for i = 1:numel(program.Counters)
    C = program.Counters(i);
    switch C.Edge
        case "Falling", edgeCode = 1;
        case "Either",  edgeCode = 2;
        otherwise,      edgeCode = 0;
    end
    rec(end+1) = sprintf("N %d %s %d %d", i, C.Name, ...
        program.channelIndex(C.Channel), edgeCode);
end

% --- States, then their actions and transitions ---------------------------

startIdx = program.stateIndex(program.StartState);

for i = 1:numel(program.States)
    S = program.States(i);

    flags = 0;
    if S.IsTerminal, flags = bitor(flags, 1); end
    if i == startIdx, flags = bitor(flags, 2); end

    rec(end+1) = sprintf("S %d %s %s %d %u", i, S.Name, ...
        teensy.Compiler.wireValue(S.DurationMs, program), flags, S.respMask());
end

for i = 1:numel(program.States)
    S = program.States(i);

    for k = 1:numel(S.EntryActions)
        rec(end+1) = localActionRecord_(S.EntryActions(k), program, i, 0, 0);
    end

    for k = 1:numel(S.ExitActions)
        rec(end+1) = localActionRecord_(S.ExitActions(k), program, i, 1, 0);
    end

    for k = 1:numel(S.Transitions)
        T = S.Transitions(k);

        if strlength(T.Target) == 0
            targetIdx = -1;    % stay here without resetting the state timer
        else
            targetIdx = program.stateIndex(T.Target);
        end

        tokens = T.Condition.toPostfix(program);
        tokenText = strings(1, numel(tokens));
        for n = 1:numel(tokens)
            tokenText(n) = tokens(n).Text;
        end

        rec(end+1) = strtrim(sprintf("T %d %d %d %d %s", ...
            i, k, targetIdx, numel(tokens), strjoin(tokenText, " ")));

        for a = 1:numel(T.Actions)
            rec(end+1) = localActionRecord_(T.Actions(a), program, i, 2, k);
        end
    end
end

% --- Framing and length check --------------------------------------------

% rec(:) forces a column before cellstr, so the transpose below always yields
% a 1xN cell regardless of how the growth loop shaped it.
body = cell(1, 0);
if ~isempty(rec)
    body = reshape(cellstr(rec(:)), 1, []);
end
lines = [{'PROG BEGIN'}, body, {'PROG END'}];

limit = obj.LIMITS.MAX_LINE_CHARS;
overlong = find(cellfun(@numel, lines) > limit);
for k = 1:numel(overlong)
    iss(end+1) = teensy.issue("error", "Record", ...
        sprintf("A record is %d characters; the firmware buffer holds %d.", ...
            numel(lines{overlong(k)}), limit), ...
        Where = sprintf("Record %d", overlong(k)), ...
        Remedy = "Shorten the names it references, or split the condition across two states.");
end
end


function p = localChannelParams_(c)
% p = localChannelParams_(c)
% The four kind-specific channel parameters, as wire strings.
%
% Analog thresholds go out in engineering units and the board converts with
% Scale/Offset, so recalibrating a sensor is a channel edit rather than a
% firmware change.
p = strings(1, 4);

if c.Direction == "Input" && c.Kind == "Digital"
    p(:) = ["" + c.DebounceMs, "0", "0", "0"];
elseif c.Direction == "Input"
    p(:) = ["" + c.ThresholdHigh, "" + c.ThresholdLow, "" + c.Scale, "" + c.Offset];
elseif c.Kind == "Digital"
    p(:) = ["" + c.IdleState, "0", "0", "0"];
else
    switch c.AnalogOutMode
        case "MQS",     modeCode = 1;
        case "SPI_DAC", modeCode = 2;
        otherwise,      modeCode = 0;
    end
    p(:) = ["" + modeCode, "" + c.PwmFrequencyHz, "" + c.PwmResolutionBits, "0"];
end
end


function s = localBound_(value)
% s = localBound_(value)
% Render a Min/Max bound, mapping the infinities onto firmware sentinels.
if isinf(value)
    if value > 0
        s = "1e9";
    else
        s = "-1e9";
    end
else
    s = string(sprintf('%.6g', value));
end
end


function line = localActionRecord_(action, program, stateIdx, when, order)
% line = localActionRecord_(action, program, stateIdx, when, order)
% One A record. a5 carries the transition order when when==2.
[args, refs] = action.toArgs(program);

parts = strings(1, 4);
for i = 1:4
    if refs(i) > 0
        parts(i) = "#" + string(refs(i));
    elseif args(i) == fix(args(i)) && abs(args(i)) < 1e9
        parts(i) = string(sprintf('%d', args(i)));
    else
        parts(i) = string(sprintf('%.6g', args(i)));
    end
end

line = sprintf("A %d %d %d %s %s %s %s %d", stateIdx, when, ...
    teensy.Action.kindCode(action.Kind), parts(1), parts(2), parts(3), parts(4), order);
end
