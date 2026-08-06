function [ok, msg] = sendProgramBlock(obj, lines)
% [ok, msg] = sendProgramBlock(obj, lines)
% Upload a compiled trial-contingency program to the board.
%
% The program is a state table produced by teensy.Compiler. Each line is a
% single record, and the firmware acknowledges every line individually with
% OK or ERR. Acking per line preserves the one-reply-per-command invariant
% the rest of this class depends on, and it reports the exact record that
% failed instead of only that the block as a whole was rejected.
%
% Written against the protected transport seam rather than the private
% transaction helpers, so tmp/Teensy_Mock exercises this path unchanged.
%
% Parameters
%   lines - Cell array of char, or a string array, of wire-program records.
%       PROG BEGIN / PROG END framing is added when absent.
%
% Returns:
%   ok  - True when the board accepted the whole program.
%   msg - Human-readable result, naming the offending record on failure.
%
% See also: teensy.Compiler, hw.Teensy.readProgramBlock,
%           documentation/hw/hw_Teensy_Program_Protocol.md

arguments
    obj
    lines (1,:) cell
end

ok = false;

if ~obj.IsConnected
    msg = 'Not connected to a Teensy board.';
    vprintf(0, 1, 'Teensy: cannot upload a program: %s', msg);
    return
end

lines = cellfun(@(s) char(string(s)), lines, UniformOutput = false);
lines = lines(~cellfun(@isempty, strtrim(lines)));

if isempty(lines)
    msg = 'Program is empty.';
    vprintf(0, 1, 'Teensy: cannot upload a program: %s', msg);
    return
end

if ~strcmp(strtrim(lines{1}), 'PROG BEGIN')
    lines = [{'PROG BEGIN'}, lines];
end
if ~strcmp(strtrim(lines{end}), 'PROG END')
    lines = [lines, {'PROG END'}];
end

overlong = find(cellfun(@numel, lines) > obj.MAX_LINE_LENGTH, 1);
if ~isempty(overlong)
    msg = sprintf('Record %d is %d characters; the firmware accepts %d.', ...
        overlong, numel(lines{overlong}), obj.MAX_LINE_LENGTH);
    vprintf(0, 1, 'Teensy: cannot upload a program: %s', msg);
    return
end

% Any coalesced parameter writes must land before the program replaces the
% state table, otherwise they would be applied against the old table.
obj.flushWrites();

vprintf(2, 'Teensy: uploading a %d-record program', numel(lines) - 2);

reply = '';
for i = 1:numel(lines)
    % Inlined rather than factored into a local function: local functions in a
    % method file are not class methods, so they cannot reach the protected
    % transport seam.
    try
        obj.writeLine_(lines{i});
        reply = obj.readLine_();
    catch ME
        vprintf(0, 1, ME);
        reply = '';
    end

    if isempty(reply)
        msg = sprintf('No reply to record %d of %d ("%s").', i, numel(lines), lines{i});
        vprintf(0, 1, 'Teensy: program upload failed: %s', msg);
        return
    end

    if ~startsWith(reply, 'OK')
        msg = sprintf('Record %d of %d ("%s") was rejected: %s', ...
            i, numel(lines), lines{i}, reply);
        vprintf(0, 1, 'Teensy: program upload failed: %s', msg);
        return
    end
end

% The final OK carries the accepted state count, which is the board's own
% confirmation that it parsed the table rather than merely echoing acks.
nStates = sscanf(reply, 'OK %d');
if isempty(nStates)
    nStates = NaN;
end

ok = true;
msg = sprintf('Board accepted %d record(s), %d state(s).', numel(lines) - 2, nStates);
vprintf(1, 'Teensy: %s', msg);

% A new program invalidates every cached read, including the state index.
obj.snapshotInvalidate();
end
