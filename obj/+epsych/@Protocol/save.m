function save(obj, filename, options)
    % save(obj, filename)
    % save(obj, filename, IncrementVersion=tf)
    %
    % Serialize protocol to an .eprot MAT file or a .json file.
    %
    % Parameters:
    %   filename (char) - Output filename (.eprot or .json)
    %   IncrementVersion (logical) - Whether to increment the version number
    %       before saving. Default true.
    %
    % For .json files, delegates to toJSON(). For all other extensions,
    % writes a MAT file through epsych.Protocol.writeProtocolFile, which
    % archives the superseded version inside the file (so earlier versions
    % can be listed, loaded, and restored — see listVersions, loadVersion,
    % restoreVersion), writes atomically, and clears the phase cache. JSON
    % files keep no version history.

    arguments
        obj
        filename (1,:) char
        options.IncrementVersion (1,1) logical = true
    end

    [~, ~, ext] = fileparts(filename);
    if strcmpi(ext, '.json')
        obj.toJSON(filename);
        return
    end

    % Update modification time
    obj.meta.lastModified = datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss');

    % Increment protocol version: vN.YYMMDD. Mint past the file on disk as
    % well as this object: a stale in-memory protocol saved over a file that
    % has moved on must not re-mint a version the file already holds, or the
    % version string would stop identifying content.
    if options.IncrementVersion
        dateTag = char(datetime('now', 'Format', 'yyMMdd'));
        nMem  = epsych.Protocol.versionNumber(obj.meta.protocolVersion);
        nDisk = epsych.Protocol.versionNumber(epsych.Protocol.versionOnDisk(filename));
        n = max([nMem, nDisk, 0], [], 'omitnan');
        obj.meta.protocolVersion = sprintf('v%d.%s', n + 1, dateTag);
    end

    % Serialize to a version-stable struct and save; the writer archives the
    % file's superseded version and makes the write atomic.
    protocol = obj.toStruct();
    epsych.Protocol.writeProtocolFile(filename, protocol, Origin='save');
    vprintf(1, 'Protocol saved to: %s (%s)', filename, obj.meta.protocolVersion);
end
