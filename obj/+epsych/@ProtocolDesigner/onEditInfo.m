function onEditInfo(obj)
    currentInfo = obj.Protocol.Info;
    answer = inputdlg({'Protocol Info'}, 'Edit Protocol Info', [6 80], {currentInfo});
    if isempty(answer)
        return
    end

    obj.Protocol.Info = char(answer{1});
    obj.setStatus('Protocol info updated', 'Compile or save if the description change is final.');
end