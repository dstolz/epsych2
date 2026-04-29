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

    % Load MAT file using builtin load function
    S = builtin('load', filename, '-mat');

    % Struct-based format (current and legacy)
    if isfield(S, 'protocol') && isstruct(S.protocol)
        struct_in = S.protocol;
    elseif isfield(S, 'protocol_struct')
        struct_in = S.protocol_struct;
    elseif isfield(S, 'protocol') && isa(S.protocol, 'epsych.Protocol')
        % Legacy: file saved as a live handle object before struct migration
        obj = S.protocol;
        fprintf('[INFO] Protocol loaded from: %s\n', filename);
        return
    else
        error('epsych:Protocol:InvalidFile', 'MAT file does not contain expected protocol data');
    end

    obj = epsych.Protocol();
    obj.fromStruct(struct_in);
    fprintf('[INFO] Protocol loaded from: %s\n', filename);
end
