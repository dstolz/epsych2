function ffn = videoRecordingFilename(rootDir, dataFilename)
% ffn = videoRecordingFilename(rootDir, dataFilename)
% Build the recording path that pairs with a behavioral data file, mirroring
% that file's layout under rootDir:
%   <rootDir>\<subjectFolder>\<dataFileName>.ts
% The name is taken verbatim from dataFilename so a recording and the .mat it
% accompanies are matched by name; only the root and the extension differ.
% The extension is .ts because VLC's mp4 muxer writes broken timestamps for
% camera captures; hw.VlcRecorder handles VLC-specific path escaping.
arguments
    rootDir (1,1) string
    dataFilename (1,1) string
end

[dataDir, name] = fileparts(dataFilename);
[~, subjectFolder] = fileparts(dataDir);

if strlength(name) == 0
    error('epsych:RunExpt:InvalidDataFilename', ...
        'Cannot derive a recording name from data filename "%s".', dataFilename);
end

ffn = char(fullfile(rootDir, subjectFolder, name + ".ts"));
