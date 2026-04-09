function onSave(obj)
    [fileName, folder] = uiputfile('*.eprot', 'Save Protocol');
    if isequal(fileName, 0)
        return
    end

    obj.Protocol.save(fullfile(folder, fileName));
    obj.LabelStatus.Text = 'Protocol saved';
end

