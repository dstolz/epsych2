function onLoad(obj)
    [fileName, folder] = uigetfile({'*.eprot;*.prot', 'Protocol Files (*.eprot, *.prot)'}, 'Load Protocol');
    if isequal(fileName, 0)
        return
    end

    obj.Protocol = epsych.Protocol.load(fullfile(folder, fileName));
    obj.refreshUI();
    obj.setStatus(sprintf('Loaded protocol %s', fileName));
end

