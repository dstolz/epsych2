function file = write(file, code)
% file = behavior.ScriptWriter.write(file, code)
% Write a generated script to disk as UTF-8, one line per cell.
%
% The file is meant to be run by name, so its base name must be a valid
% MATLAB identifier ("replicate_PrePost.m", not "replicate-PrePost.m"); ".m"
% is appended when missing. A relative name is taken from the current folder,
% and a missing folder is created.
%
% Parameters:
%   file - the file to write
%   code - cellstr (or string array) from behavior.ScriptWriter.session or .compare
%
% Returns:
%   file - the absolute path written (string)
%
% See also: behavior.ScriptWriter.session, behavior.ScriptWriter.compare

arguments
    file (1,1) string
    code {mustBeText}
end

code = cellstr(code);

[folder, base, ext] = fileparts(file);
if ~strcmpi(ext, ".m")
    base = base + ext;      % "replicate.v2" is a name, not an extension
end
if ~isvarname(char(base))
    error('behavior:ScriptWriter:InvalidName', ...
        '"%s" cannot be run as a script: a script name must be a valid MATLAB identifier.', base);
end

if folder == ""
    folder = string(pwd);
elseif isempty(regexp(folder, '^([A-Za-z]:[\\/]|[\\/])', 'once'))
    folder = fullfile(string(pwd), folder);
end
if ~isfolder(folder)
    [ok, msg] = mkdir(folder);
    if ~ok
        error('behavior:ScriptWriter:CannotWrite', 'Cannot create "%s": %s', folder, msg);
    end
end
file = fullfile(folder, base + ".m");

fid = fopen(file, 'w', 'n', 'UTF-8');
if fid < 0
    error('behavior:ScriptWriter:CannotWrite', 'Cannot open "%s" for writing.', file);
end
closer = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', code{:});
clear closer

vprintf(2, 'behavior.ScriptWriter: wrote %d lines to "%s"', numel(code), file)

end
