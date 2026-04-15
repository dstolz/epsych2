function onOpenAsJSON(obj)
% onOpenAsJSON(obj)
% Serialize the current protocol to a temporary JSON file and open it in
% the default OS editor for .json files.

tmpFile = fullfile(tempdir, sprintf('protocol_%s.json', ...
    matlab.lang.makeValidName(obj.Protocol.Info, 'ReplacementStyle', 'delete')));
if isempty(tmpFile) || strcmp(tmpFile, fullfile(tempdir, 'protocol_.json'))
    tmpFile = fullfile(tempdir, 'protocol_preview.json');
end

obj.Protocol.toJSON(tmpFile);

if ispc
    winopen(tmpFile);
elseif ismac
    system(sprintf('open "%s"', tmpFile));
else
    system(sprintf('xdg-open "%s" &', tmpFile));
end
