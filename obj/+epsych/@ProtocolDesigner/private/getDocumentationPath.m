function docPath = getDocumentationPath(~, docType)
    if nargin < 2 || strlength(string(docType)) == 0
        docType = 'developer';
    end

    if exist('epsych_path', 'file') == 2
        repoRoot = epsych_path();
    else
        classFile = mfilename('fullpath');
        repoRoot = fileparts(fileparts(fileparts(fileparts(classFile))));
    end

    switch lower(char(string(docType)))
        case 'user'
            fileName = 'ProtocolDesigner_UserGuide.md';
        otherwise
            fileName = 'ProtocolDesigner.md';
    end

    docPath = fullfile(repoRoot, 'documentation', 'design', fileName);
end

