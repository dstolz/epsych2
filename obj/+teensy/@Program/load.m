function obj = load(filename)
% obj = teensy.Program.load(filename)
% Read a program from a .etsm MAT-file or a .json file.
%
% Parameters
%   filename - Path to a .etsm or .json file.
%
% Returns:
%   obj - The loaded teensy.Program.
%
% Throws:
%   teensy:Program:FileNotFound  - The path does not exist.
%   teensy:Program:InvalidFile   - The file is not a Teensy program.
%
% See also: teensy.Program.save, teensy.Program.fromStruct

arguments
    filename (1,:) char
end

if ~isfile(filename)
    error('teensy:Program:FileNotFound', 'No such file: %s', filename);
end

[~, ~, ext] = fileparts(filename);

if strcmpi(ext, '.json')
    text = fileread(filename);
    S = jsondecode(text);
else
    raw = builtin('load', filename, '-mat');
    if ~isfield(raw, 'Program')
        error('teensy:Program:InvalidFile', ...
            '"%s" does not contain a Teensy program.', filename);
    end
    S = raw.Program;
end

if ~isstruct(S) || ~isscalar(S)
    error('teensy:Program:InvalidFile', ...
        '"%s" does not contain a Teensy program.', filename);
end

version = teensy.getFieldOr(S, 'FormatVersion', teensy.Program.FORMAT_VERSION);
if version > teensy.Program.FORMAT_VERSION
    vprintf(0, 1, ['teensy.Program: "%s" was written in format %g but this version ' ...
        'reads %g. Unrecognized fields will be dropped.'], ...
        filename, version, teensy.Program.FORMAT_VERSION);
end

obj = teensy.Program.fromStruct(S);
vprintf(1, 'teensy.Program: loaded "%s" (%d states)', filename, numel(obj.States));
end
