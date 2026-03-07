function ffn = defaultFilename(pth,name)
% defaultFilename — Create a timestamped filename and avoid overwrites.
arguments
    pth {mustBeTextScalar}
    name {mustBeTextScalar}
end
pth = char(pth);
name = char(name);

td = datetime('now');
td.Format = "yyMMdd'T'HHmmss";
fn = sprintf('%s_%s.mat',name,char(td));

ffn = fullfile(pth,fn);

letters = char(65:90);
k = 1;
while isfile(ffn)
    fn = sprintf('%s_%s_%s.mat',name,char(td),letters(k));
    ffn = fullfile(pth,fn);
    k = k + 1;
end
