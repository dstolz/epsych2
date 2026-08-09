function dst = planOutput(src, obj)
% dst = util.VideoConverter.planOutput(src, obj)
% Compute the planned output path for source file src given obj's naming
% properties (OutputFolder, MirrorTree, OutputExtension, NamePrefix,
% NameSuffix, NameReplace). Pure: does not touch the filesystem.
arguments
    src (1,1) string
    obj (1,1) util.VideoConverter
end

[srcDir, stem, ~] = fileparts(src);
srcDir = string(srcDir);
stem = string(stem);

if obj.NameReplace(1) ~= ""
    stem = regexprep(stem, obj.NameReplace(1), obj.NameReplace(2));
end
stem = obj.NamePrefix + stem + obj.NameSuffix;

ext = obj.OutputExtension;
if ~startsWith(ext, ".")
    ext = "." + ext;
end

if obj.OutputFolder == ""
    outDir = srcDir;
else
    outDir = obj.OutputFolder;
    if endsWith(outDir, filesep)
        outDir = extractBefore(outDir, strlength(outDir));
    end
    if obj.MirrorTree && obj.RootFolder ~= ""
        root = obj.RootFolder;
        if endsWith(root, filesep)
            root = extractBefore(root, strlength(root));
        end
        if startsWith(srcDir, root, 'IgnoreCase', ispc)
            relDir = extractAfter(srcDir, strlength(root));
            relDir = regexprep(relDir, '^[\\/]+', '');
            if relDir ~= ""
                outDir = fullfile(outDir, relDir);
            end
        end
    end
end

dst = string(fullfile(outDir, stem + ext));
end
