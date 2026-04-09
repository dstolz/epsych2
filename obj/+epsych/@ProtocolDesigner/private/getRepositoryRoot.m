function rootPath = getRepositoryRoot(~)
    classFile = mfilename('fullpath');
    rootPath = fileparts(fileparts(fileparts(classFile)));
end

