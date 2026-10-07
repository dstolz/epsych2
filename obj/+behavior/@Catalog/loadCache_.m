function [records, state] = loadCache_(obj)
% [records, state] = loadCache_(obj)
%
% The cached per-file descriptions for this Root, and the CacheState that
% describes where they came from. A cache that cannot be used is not an error:
% it is rebuilt by the scan that asked for it, and state says why.
%
% Returns:
%   records - (:,1) struct: Key (lowered on Windows), Bytes, Modified
%             (dir datenum), Summary (epsych.SessionFiles.summarize row).
%   state   - "new" | "loaded" | "rebuilt (<why>)".
%
% See also: behavior.Catalog.saveCache_

records = repmat(struct('Key', "", 'Bytes', 0, 'Modified', 0, 'Summary', []), 0, 1);

if ~isfile(obj.CacheFile)
    state = "new";
    return
end

try
    C = load(obj.CacheFile, '-mat');
catch ME
    vprintf(2, 'behavior.Catalog: cache "%s" is unreadable: %s', obj.CacheFile, ME.message)
    state = "rebuilt (unreadable)";
    return
end

% A file in the cache folder is ours, but not necessarily this version's or
% this root's: two roots whose lowered paths collide in eight hex digits, or a
% cache written before the record format changed.
try
    version = C.CacheVersion;
    root = string(C.Root);
    stored = C.Records;
catch
    state = "rebuilt (unreadable)";
    return
end

if ~isequal(version, obj.CacheVersion)
    state = sprintf("rebuilt (cache version %g)", version);
    return
end
if ~strcmpi(root, obj.Root)
    state = "rebuilt (another root)";
    return
end

if ~isempty(stored)
    records = reshape(stored, [], 1);
end
state = "loaded";

end
