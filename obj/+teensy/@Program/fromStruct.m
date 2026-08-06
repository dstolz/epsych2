function obj = fromStruct(S)
% obj = teensy.Program.fromStruct(S)
% Rebuild a program from the struct produced by toStruct.
%
% Tolerates a struct saved by an older version: every field falls back to the
% constructor default when absent, and both the cell-wrapped shape written by
% toStruct and the bare shape jsondecode produces are accepted.
%
% Parameters
%   S - Struct from teensy.Program.toStruct, or from jsondecode of one.
%
% Returns:
%   obj - A new teensy.Program. Its Dirty flag is cleared, because a program
%       just loaded from a snapshot has no unsaved changes.
%
% See also: teensy.Program.toStruct, teensy.Program.load

arguments
    S (1,1) struct
end

obj = teensy.Program();

obj.Name = string(teensy.getFieldOr(S, 'Name', "Untitled"));
obj.Description = string(teensy.getFieldOr(S, 'Description', ""));
obj.Author = string(teensy.getFieldOr(S, 'Author', ""));
obj.BoxID = double(teensy.getFieldOr(S, 'BoxID', 1));
obj.StartState = string(teensy.getFieldOr(S, 'StartState', ""));

board = teensy.getFieldOr(S, 'Board', []);
if isstruct(board) && ~isempty(board)
    obj.Board = teensy.BoardProfile.fromStruct(board);
end

channels = localUnwrap_(teensy.getFieldOr(S, 'Channels', []));
if ~isempty(channels)
    obj.Channels = teensy.Channel.fromStruct(channels);
end

variables = localUnwrap_(teensy.getFieldOr(S, 'Variables', []));
if ~isempty(variables)
    obj.Variables = teensy.Variable.fromStruct(variables);
end

states = localUnwrap_(teensy.getFieldOr(S, 'States', []));
if ~isempty(states)
    obj.States = teensy.State.fromStruct(states);
end

obj.GlobalTimers = localRebuildAux_( ...
    localUnwrap_(teensy.getFieldOr(S, 'GlobalTimers', [])), ...
    {'Name', 'DurationMs'}, {"", 1000});

obj.Counters = localRebuildAux_( ...
    localUnwrap_(teensy.getFieldOr(S, 'Counters', [])), ...
    {'Name', 'Channel', 'Edge'}, {"", "", "Rising"});

% Created/Modified are SetAccess=protected; this is a method of the class, so
% it may write them directly and preserve the original authoring times.
obj.Created = localParseTime_(teensy.getFieldOr(S, 'Created', ''));
obj.Modified = localParseTime_(teensy.getFieldOr(S, 'Modified', ''));
obj.clearDirty();
end


function A = localUnwrap_(value)
% A = localUnwrap_(value)
% Accept the cell-wrapped shape toStruct writes and the bare shape jsondecode
% returns, and hand back a plain struct array either way.
A = value;
if iscell(A)
    if isempty(A)
        A = [];
        return
    end
    A = A{1};
end
if ~isstruct(A)
    A = [];
    return
end
A = reshape(A, 1, []);
end


function T = localRebuildAux_(A, fields, defaults)
% T = localRebuildAux_(A, fields, defaults)
% Rebuild an auxiliary struct array with a fixed field order.
args = [fields; repmat({{}}, 1, numel(fields))];
T = struct(args{:});

for i = 1:numel(A)
    entry = struct();
    for f = 1:numel(fields)
        value = teensy.getFieldOr(A(i), fields{f}, defaults{f});
        if isstring(defaults{f}) || ischar(defaults{f})
            value = string(value);
        end
        entry.(fields{f}) = value;
    end
    T(end + 1) = entry;
end
end


function t = localParseTime_(value)
% t = localParseTime_(value)
% Parse an ISO-8601 timestamp, falling back to now on anything unparseable.
t = datetime('now');
if isempty(value)
    return
end

try
    t = datetime(string(value), InputFormat = 'yyyy-MM-dd''T''HH:mm:ss');
catch
    % A timestamp written by a different locale or version is not worth
    % failing a load over.
end
end
