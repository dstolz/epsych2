function onSave(obj)
    [fileName, folder] = uiputfile('*.eprot', 'Save Protocol');
    if isequal(fileName, 0)
        return
    end

    obj.Protocol.save(fullfile(folder, fileName));
    obj.setStatus(sprintf('Saved protocol to %s', fileName), ...
        'Compile again after further edits, or close the designer if you are finished.');
end

