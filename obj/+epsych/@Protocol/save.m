function save(obj, filename)
    % save(obj, filename)
    %
    % Serialize protocol to .eprot MAT file.
    %
    % Parameters:
    %   filename (char) - Output filename (should end in .eprot)
    %
    % The MAT file contains a single variable 'protocol_struct' for
    % deserialization.
    
    arguments
        obj
        filename (1,:) char
    end

    % Update modification time
    obj.meta.lastModified = datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss');

    % Convert to struct for MAT serialization
    protocol_struct = obj.toStruct();

    % Save to MAT file using builtin save function
    builtin('save', filename, 'protocol_struct', '-mat');
    fprintf('[INFO] Protocol saved to: %s\n', filename);
end
