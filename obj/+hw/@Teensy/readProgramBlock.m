function lines = readProgramBlock(obj)
% lines = readProgramBlock(obj)
% Read back the trial-contingency program currently held by the board.
%
% The reply is the same record stream sendProgramBlock uploaded, framed as
% PROG BEGIN / PROG END. teensy.Compiler.decompile turns it back into a
% teensy.Program, which is how the designer answers "what is actually
% running on this board right now" rather than "what is in this file".
%
% Returns:
%   lines - Cell array of char records between the framing markers. Empty
%       when the board holds no program or is not connected.
%
% See also: hw.Teensy.sendProgramBlock, teensy.Compiler.decompile,
%           documentation/hw/hw_Teensy_Program_Protocol.md

lines = {};

if ~obj.IsConnected
    vprintf(2, 'Teensy: cannot read a program back while disconnected');
    return
end

obj.flushWrites();

lines = obj.transactBlock_('PROG?', 'PROG');

vprintf(2, 'Teensy: read back a %d-record program', numel(lines));
end
