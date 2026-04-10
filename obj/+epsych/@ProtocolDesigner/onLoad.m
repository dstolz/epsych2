function onLoad(obj)
    startPath = obj.getProtocolFileDialogStartPath('*.eprot');
    [fileName, folder] = uigetfile({'*.eprot;*.prot', 'Protocol Files (*.eprot, *.prot)'}, 'Load Protocol', startPath);
    if isequal(fileName, 0)
        return
    end

    obj.openProtocolFile(fullfile(folder, fileName));
    obj.setStatus(sprintf('Loaded protocol %s', fileName));
end

