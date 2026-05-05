function onOpenDocumentation(obj, docType)
% onOpenDocumentation(obj, docType)
% Open the requested Protocol Designer documentation page in the default web browser.
%
% Parameters:
%	docType	- Documentation selector: "user" or "developer".
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

    docUrl = localBuildFileUrl_(docPath);
    try
        web(docUrl, '-browser');
    catch
        winopen(docPath);
    end

    switch docType
        case 'user'
            obj.setStatus('Opened Protocol Designer user guide', ...
                'Follow the guide in parallel with the designer as you build or edit a protocol.');
        otherwise
            obj.setStatus('Opened Protocol Designer developer documentation', ...
                'Use the doc as a reference, then return here to continue editing.');
    end
end

function fileUrl = localBuildFileUrl_(docPath)
% fileUrl = localBuildFileUrl_(docPath)
% Convert a local path to a browser-compatible file URL.
    normalized = strrep(char(docPath), '\', '/');
    if startsWith(normalized, '/')
        fileUrl = ['file://' normalized];
    else
        fileUrl = ['file:///' normalized];
    end
    fileUrl = strrep(fileUrl, ' ', '%20');
end

