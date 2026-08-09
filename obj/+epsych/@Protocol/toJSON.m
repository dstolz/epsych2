function toJSON(obj, filename)
% toJSON(obj, filename)
% Serialize the protocol to a JSON file.
%
% Parameters:
%   filename (char) - Output file path (should end in .json)

arguments
    obj
    filename (1,:) char
end

obj.meta.lastModified = datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss');
s = obj.toStruct();
json_str = jsonencode(s, 'PrettyPrint', true);

fid = fopen(filename, 'w', 'n', 'UTF-8');
if fid == -1
    error('epsych:Protocol:CannotOpenFile', 'Cannot open file for writing: %s', filename);
end
fprintf(fid, '%s', json_str);
fclose(fid);

fprintf('[INFO] Protocol saved to JSON: %s\n', filename);
