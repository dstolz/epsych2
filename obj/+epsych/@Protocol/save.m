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
    % saves a MAT file containing a single 'protocol' variable.

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

    % Increment protocol version: vN.YYMMDD
    if options.IncrementVersion
        dateTag = char(datetime('now', 'Format', 'yyMMdd'));
        tok = regexp(obj.meta.protocolVersion, '^v(\d+)\.', 'tokens', 'once');
        if isempty(tok)
            n = 0;
        else
            n = str2double(tok{1});
        end
        obj.meta.protocolVersion = sprintf('v%d.%s', n + 1, dateTag);
    end

    % Serialize to a version-stable struct and save
    protocol = obj.toStruct();
    builtin('save', filename, 'protocol', '-mat');
    fprintf('[INFO] Protocol saved to: %s\n', filename);
end
