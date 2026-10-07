function msg = saveCache_(obj, records)
% msg = saveCache_(obj, records)
%
% Write the per-file descriptions of the scan that just finished. Written to a
% temporary file and moved into place, so a reader never sees half a cache and
% a scan killed mid-write leaves the previous one.
%
% Returns:
%   msg - "" on success, else why the cache could not be written. A cache is
%         a convenience: failing to write one costs the next scan time, never
%         the scan that is running.
%
% See also: behavior.Catalog.loadCache_

msg = "";
if isempty(records)
    records = repmat(struct('Key', "", 'Bytes', 0, 'Modified', 0, 'Summary', []), 0, 1);
end

C = struct( ...
    'CacheVersion', obj.CacheVersion, ...
    'Root',         char(obj.Root), ...
    'Written',      datetime('now'), ...
    'Records',      records);

tmp = obj.CacheFile + ".tmp-" + feature('getpid');
try
    if ~isfolder(obj.CacheFolder)
        mkdir(obj.CacheFolder);
    end
    save(tmp, '-struct', 'C', '-v7');
    [ok, why] = movefile(tmp, obj.CacheFile, 'f');
    if ~ok
        error('behavior:Catalog:CacheMove', '%s', why);
    end
catch ME
    msg = string(ME.message);
    vprintf(1, 'behavior.Catalog: could not write the scan cache "%s": %s', obj.CacheFile, ME.message)
    if isfile(tmp)
        delete(tmp);
    end
end

end
