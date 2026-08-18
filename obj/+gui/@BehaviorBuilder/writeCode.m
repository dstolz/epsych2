function mFile = writeCode(spec, specFile, mFile)
% mFile = gui.BehaviorBuilder.writeCode(spec, specFile, mFile)
% Generate the gui.BehaviorGUI subclass for a layout spec and write it to
% mFile (path defaults to '<ClassName>.m' beside specFile). The file's base
% name must equal spec.ClassName — MATLAB requires it — so a mismatch is an
% error here; the builder's interactive export offers the rename instead.

arguments
    spec struct
    specFile (1,:) char
    mFile (1,:) char = ''
end

spec = gui.BehaviorBuilder.specValidate(spec);
if isempty(mFile)
    mFile = fullfile(fileparts(specFile), [spec.ClassName '.m']);
end
[~,base] = fileparts(mFile);
assert(strcmp(base, spec.ClassName), 'epsych:BehaviorBuilder:NameMismatch', ...
    'File name "%s" must match the class name "%s"', base, spec.ClassName)

code = gui.BehaviorBuilder.generateCode(spec, specFile);

fid = fopen(mFile, 'w');
assert(fid > 0, 'epsych:BehaviorBuilder:CannotWrite', ...
    'Could not open %s for writing', mFile)
cl = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', code{:});
vprintf(1, 'Generated behavior GUI class: %s', mFile)
end
