function row = session(obj, key)
% row = session(obj, key)
% The Sessions row for one key.
%
% Parameters:
%   key - Session key (see keyFor), compared with keyEquals.
%
% Returns:
%   row - One-row table with the Sessions columns.
%
% See also: behavior.Catalog.keysFor

arguments
    obj
    key (1,1) string
end

k = find(behavior.Catalog.keyEquals(obj.Sessions.Key, key), 1);
if isempty(k)
    error('behavior:Catalog:UnknownSession', 'No session "%s" under "%s".', key, obj.Root);
end
row = obj.Sessions(k, :);

end
