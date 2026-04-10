function onOpenDocumentation(obj)
    docPath = obj.getDocumentationPath();
    if ~isfile(docPath)
        obj.setStatus('Documentation file not found', 'Continue editing in the designer or check the documentation path.');
        uialert(obj.Figure, sprintf('Documentation file not found:\n%s', docPath), 'Missing Documentation');
        return
    end

    matlab.desktop.editor.openDocument(docPath);
    obj.setStatus('Opened Protocol Designer documentation', ...
        'Use the doc as a reference, then return here to continue editing.');
end

