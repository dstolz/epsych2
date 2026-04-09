function onOpenDocumentation(obj)
    docPath = obj.getDocumentationPath();
    if ~isfile(docPath)
        obj.LabelStatus.Text = 'Documentation file not found';
        uialert(obj.Figure, sprintf('Documentation file not found:\n%s', docPath), 'Missing Documentation');
        return
    end

    matlab.desktop.editor.openDocument(docPath);
    obj.LabelStatus.Text = 'Opened Protocol Designer documentation';
end

