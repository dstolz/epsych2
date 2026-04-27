function docPath = getDocumentationPath(~)
    if exist('epsych_path', 'file') == 2
        repoRoot = epsych_path();
    else
        classFile = mfilename('fullpath');
        repoRoot = fileparts(fileparts(fileparts(fileparts(classFile))));
    end

    docPath = fullfile(repoRoot, 'documentation', 'design', 'ProtocolDesigner.md');
end

