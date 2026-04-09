function docPath = getDocumentationPath(~)
    classFile = mfilename('fullpath');
    repoRoot = fileparts(fileparts(fileparts(classFile)));
    docPath = fullfile(repoRoot, 'documentation', 'design', 'ProtocolDesigner.md');
end

