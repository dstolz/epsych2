function tf = hasVersion(filename, version)
    % tf = epsych.Protocol.hasVersion(filename, version)
    %
    % True when a protocol file can produce this version: either its current
    % content is that version, or the version sits in the file's embedded
    % archive (see writeProtocolFile) and restoreVersion can bring it back.
    %
    % Never throws, and reads only the file's small variables — this is asked
    % per history entry every time a subject list repaints.
    %
    % Parameters:
    %   filename - .eprot/.prot protocol file
    %   version  - version string such as 'v3.260814'
    %
    % Returns:
    %   tf - logical
    %
    % See also: epsych.Protocol.versionOnDisk, epsych.Protocol.listVersions,
    %   epsych.Protocol.restoreVersion

    arguments
        filename (1,:) char = ''
        version (1,:) char = ''
    end

    tf = false;
    if isempty(filename) || isempty(version) || ~isfile(filename), return, end

    try
        if strcmp(epsych.Protocol.versionOnDisk(filename), version)
            tf = true;
            return
        end

        vars = {whos('-file', filename).name};
        if ismember('historyIndex', vars)
            S = builtin('load', filename, '-mat', 'historyIndex');
            hi = S.historyIndex;
            tf = isstruct(hi) && ~isempty(hi) && isfield(hi, 'Version') ...
                && any(strcmp({hi.Version}, version));
        elseif ismember('history', vars)
            % Index missing but an archive present: a hand-edited file.
            S = builtin('load', filename, '-mat', 'history');
            h = S.history;
            tf = isstruct(h) && ~isempty(h) && isfield(h, 'Version') ...
                && any(strcmp({h.Version}, version));
        end
    catch ME
        vprintf(3, 'Could not check the version archive of "%s": %s', filename, ME.message);
        tf = false;
    end
end
