function v = versionOnDisk(filename)
    % v = epsych.Protocol.versionOnDisk(filename)
    %
    % Read a protocol file's stored protocolVersion without reconstructing the
    % Protocol object graph.
    %
    % load() rebuilds every hw.Interface, hw.Module and hw.Parameter in the
    % file, which is far too expensive for a question asked once per subject
    % every time a subject list repaints. This reads the one metadata field and
    % nothing else.
    %
    % Never throws: a missing, unreadable, or foreign file simply has no
    % version. Callers treat '' as "unknown", never as "older than".
    %
    % Parameters:
    %   filename (char) - .eprot (MAT) or .json protocol file
    %
    % Returns:
    %   v - version string such as 'v3.260814', or '' when there is none
    %
    % See also: epsych.Protocol.versionNumber, epsych.Protocol.load

    arguments
        filename (1,:) char = ''
    end

    v = '';
    if isempty(filename) || ~isfile(filename), return, end

    try
        [~, ~, ext] = fileparts(filename);
        if strcmpi(ext, '.json')
            S = jsondecode(fileread(filename));
            if isfield(S, 'protocolVersion')
                v = char(S.protocolVersion);
            end
            return
        end

        S = load(filename, '-mat');
        if isfield(S, 'protocol') && isstruct(S.protocol) && isfield(S.protocol, 'protocolVersion')
            v = char(S.protocol.protocolVersion);
        elseif isfield(S, 'protocol_struct') && isfield(S.protocol_struct, 'protocolVersion')
            v = char(S.protocol_struct.protocolVersion);
        end
    catch ME
        vprintf(3, 'Could not read a protocol version from "%s": %s', filename, ME.message);
        v = '';
    end
end
