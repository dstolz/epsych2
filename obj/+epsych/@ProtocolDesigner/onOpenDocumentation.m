function onOpenDocumentation(obj, docType)
    if nargin < 2 || strlength(string(docType)) == 0
        docType = 'developer';
    end

    docType = char(lower(string(docType)));
    docPath = obj.getDocumentationPath(docType);
    if ~isfile(docPath)
        obj.setStatus('Documentation file not found', 'Continue editing in the designer or check the documentation path.');
        uialert(obj.Figure, sprintf('Documentation file not found:\n%s', docPath), 'Missing Documentation');
        return
    end

    matlab.desktop.editor.openDocument(docPath);
    switch docType
        case 'user'
            obj.setStatus('Opened Protocol Designer user guide', ...
                'Follow the guide in parallel with the designer as you build or edit a protocol.');
        otherwise
            obj.setStatus('Opened Protocol Designer developer documentation', ...
                'Use the doc as a reference, then return here to continue editing.');
    end
end

