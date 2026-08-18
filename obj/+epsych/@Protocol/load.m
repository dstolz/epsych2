function obj = load(filename)
    % obj = epsych.Protocol.load(filename)
    %
    % Deserialize protocol from an .eprot MAT file or a .json file.
    % This is a static method.
    %
    % Parameters:
    %   filename (char) - File to load (.eprot, .prot, or .json)
    %
    % Returns:
    %   obj - Deserialized epsych.Protocol instance

    arguments
        filename (1,:) char
    end

    if ~isfile(filename)
        error('epsych:Protocol:FileNotFound', 'File not found: %s', filename);
    end

    [~, ~, ext] = fileparts(filename);
    if strcmpi(ext, '.json')
        obj = epsych.Protocol.fromJSON(filename);
        return
    end

    % Load only the protocol variable: a file written with embedded version
    % history (see writeProtocolFile) also carries the archive of every
    % earlier version, which nothing here needs. The whole-file load remains
    % as the fallback for foreign layouts so the error path below still
    % decides what an unrecognized file is.
    try
        vars = {whos('-file', filename).name};
    catch
        vars = {};
    end
    if ismember('protocol', vars)
        S = builtin('load', filename, '-mat', 'protocol');
    elseif ismember('protocol_struct', vars)
        S = builtin('load', filename, '-mat', 'protocol_struct');
    else
        S = builtin('load', filename, '-mat');
    end

    % Struct-based format
    if isfield(S, 'protocol') && isstruct(S.protocol)
        struct_in = S.protocol;
    else
        error('epsych:Protocol:InvalidFile', 'MAT file does not contain expected protocol data');
    end

    obj = epsych.Protocol();
    obj.fromStruct(struct_in);
    fprintf('[INFO] Protocol loaded from: %s\n', filename);
end
