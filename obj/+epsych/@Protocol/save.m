function save(obj, filename)
    % save(obj, filename)
    %
    % Serialize protocol to an .eprot MAT file or a .json file.
    %
    % Parameters:
    %   filename (char) - Output filename (.eprot or .json)
    %
    % For .json files, delegates to toJSON(). For all other extensions,
    % saves a MAT file containing a single 'protocol' variable.

    arguments
        obj
        filename (1,:) char
    end

    [~, ~, ext] = fileparts(filename);
    if strcmpi(ext, '.json')
        obj.toJSON(filename);
        return
    end

    % Update modification time
    obj.meta.lastModified = datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss');

    % Save the Protocol object directly
    protocol = obj;
    builtin('save', filename, 'protocol', '-mat');
    fprintf('[INFO] Protocol saved to: %s\n', filename);
end
