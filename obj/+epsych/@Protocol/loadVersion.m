function [obj, S] = loadVersion(filename, version)
    % obj = epsych.Protocol.loadVersion(filename, version)
    % [obj, S] = epsych.Protocol.loadVersion(...)
    %
    % Load one version of a protocol file — the current content or any entry
    % in the file's embedded archive — as a live epsych.Protocol.
    %
    % Parameters:
    %   filename - .eprot/.prot protocol file
    %   version  - version string such as 'v3.260814'. Empty loads the
    %              current version, same as epsych.Protocol.load.
    %
    % Returns:
    %   obj - reconstructed epsych.Protocol instance
    %   S   - the stored struct the instance was built from
    %
    % Errors with epsych:Protocol:VersionNotFound when the file holds no such
    % version; the message lists what it does hold.
    %
    % See also: epsych.Protocol.listVersions, epsych.Protocol.restoreVersion,
    %   epsych.Protocol.load

    arguments
        filename (1,:) char
        version (1,:) char = ''
    end

    if ~isfile(filename)
        error('epsych:Protocol:FileNotFound', 'File not found: %s', filename);
    end

    [~, ~, ext] = fileparts(filename);
    if strcmpi(ext, '.json')
        cur = epsych.Protocol.versionOnDisk(filename);
        if ~isempty(version) && ~strcmp(version, cur)
            error('epsych:Protocol:VersionNotFound', ...
                'JSON protocol files keep no version history; %s holds only %s.', ...
                filename, localOrUnknown(cur));
        end
        obj = epsych.Protocol.load(filename);
        S = obj.toStruct();
        return
    end

    [P, H] = epsych.Protocol.readRaw_(filename);
    if isempty(P)
        error('epsych:Protocol:InvalidFile', ...
            'MAT file does not contain expected protocol data: %s', filename);
    end

    cur = '';
    if isfield(P, 'protocolVersion'), cur = char(string(P.protocolVersion)); end

    if isempty(version) || strcmp(version, cur)
        S = P;
    else
        hit = [];
        if ~isempty(H)
            hit = find(strcmp({H.Version}, version), 1);
        end
        if isempty(hit)
            avail = [{cur}, {H.Version}];
            avail = avail(~cellfun(@isempty, avail));
            error('epsych:Protocol:VersionNotFound', ...
                'No version "%s" in %s. Available: %s', ...
                version, filename, strjoin(avail, ', '));
        end
        S = H(hit).Protocol;
    end

    obj = epsych.Protocol();
    obj.fromStruct(S);
end

% -----------------------------------------------------------------------
function s = localOrUnknown(version)
    s = version;
    if isempty(s), s = 'an unknown version'; end
end
