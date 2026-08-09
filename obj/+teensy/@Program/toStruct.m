function S = toStruct(obj)
% S = toStruct(obj)
% Serialize the whole program to a plain struct.
%
% The result contains no objects, no handles and no enumerations, so it
% survives both a MAT-file and a jsonencode/jsondecode round trip. That
% property is what the designer's undo stack relies on: a snapshot taken here
% and restored through fromStruct reproduces the program exactly.
%
% Timestamps are stored as ISO-8601 text rather than datetime, because
% jsondecode turns a datetime into an opaque struct.
%
% Returns:
%   S - Struct with fields FormatVersion, Name, Description, Author, Created,
%       Modified, BoxID, Board, Channels, Variables, States, GlobalTimers,
%       Counters and StartState.
%
% See also: teensy.Program.fromStruct, teensy.Program.save

arguments
    obj (1,1) teensy.Program
end

S = struct();
S.FormatVersion = teensy.Program.FORMAT_VERSION;
S.Name = obj.Name;
S.Description = obj.Description;
S.Author = obj.Author;
S.Created = string(obj.Created, 'yyyy-MM-dd''T''HH:mm:ss');
S.Modified = string(obj.Modified, 'yyyy-MM-dd''T''HH:mm:ss');
S.BoxID = obj.BoxID;
S.StartState = obj.StartState;

S.Board = obj.Board.toStruct();

% Function-style calls, not obj.Channels.toStruct(): dot notation on an object
% array invokes the method once per element and yields a comma-separated list,
% which would silently keep only the first channel.
%
% Cell-wrapped so the arrays keep their length through jsondecode, which
% collapses a 1xN struct array of identical fields into an Nx1 and a 1x1 into
% a bare struct. fromStruct unwraps either shape.
S.Channels = {toStruct(obj.Channels)};
S.Variables = {toStruct(obj.Variables)};
S.States = {toStruct(obj.States)};

S.GlobalTimers = {localNormalizeAux_(obj.GlobalTimers, {'Name', 'DurationMs'})};
S.Counters = {localNormalizeAux_(obj.Counters, {'Name', 'Channel', 'Edge'})};
end


function T = localNormalizeAux_(A, fields)
% T = localNormalizeAux_(A, fields)
% Normalize an auxiliary struct array to a fixed field order.
%
% Struct arrays only concatenate when their fields match in order, so pinning
% the order here is what lets a loaded program be appended to at runtime.
if isempty(A)
    args = [fields; repmat({{}}, 1, numel(fields))];
    T = struct(args{:});
    return
end

T = repmat(cell2struct(cell(numel(fields), 1), fields, 1), 1, numel(A));
for i = 1:numel(A)
    for f = 1:numel(fields)
        T(i).(fields{f}) = A(i).(fields{f});
    end
end
end
