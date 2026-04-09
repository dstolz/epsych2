function obj = load(filename)
    % obj = epsych.Protocol.load(filename)
    %
    % Deserialize protocol from .eprot MAT file. This is a static method.
    %
    % Parameters:
    %   filename (char) - MAT file to load (should end in .eprot)
    %
    % Returns:
    %   obj - Deserialized epsych.Protocol instance
    
    arguments
        filename (1,:) char
    end

    if ~isfile(filename)
        error('File not found: %s', filename);
    end

    % Load MAT file using builtin load function
    S = builtin('load', filename, '-mat');
    
    % Determine what variable name was used
    if isfield(S, 'protocol_struct')
        struct_in = S.protocol_struct;
    elseif isfield(S, 'protocol')
        struct_in = S.protocol;
    else
        error('MAT file does not contain expected protocol data');
    end

    % Create new Protocol and populate from struct
    obj = epsych.Protocol();
    obj.fromStruct(struct_in);
    
    fprintf('[INFO] Protocol loaded from: %s\n', filename);
end
