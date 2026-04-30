function onLoad(obj)
% onLoad(obj)
% Open a protocol file after confirming any unsaved changes.
    if ~obj.confirmDiscardChanges()
        return
    end

    startPath = obj.getProtocolFileDialogStartPath('*.eprot');
    [fileName, folder] = uigetfile( ...
        {'*.eprot;*.prot;*.json', 'Protocol Files (*.eprot, *.prot, *.json)'; ...
         '*.eprot;*.prot', 'Protocol MAT Files (*.eprot, *.prot)'; ...
         '*.json', 'Protocol JSON Files (*.json)'}, ...
        'Load Protocol', startPath);
    if isequal(fileName, 0)
        return
    end

    obj.openProtocolFile(fullfile(folder, fileName));
    obj.setStatus(sprintf('Loaded protocol %s', fileName));
end

