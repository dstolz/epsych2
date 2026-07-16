function ffn = videoRecordingFilename(rootDir, subjectName)
% ffn = videoRecordingFilename(rootDir, subjectName)
% Build a per-subject, timestamped .ts recording path under rootDir:
%   <rootDir>\<subjectName>\<subjectName>_<yyMMddTHHmmss>.ts
% subjectName is sanitized against the same invalid-character set as
% gui.FilenameValidator; colons are excluded from the timestamp itself
% because Windows forbids them in filenames.
arguments
    rootDir (1,1) string
    subjectName (1,1) string
end

name = char(subjectName);
name(ismember(name, '<>:"/\|?*&$%@=')) = '_';   % gui.FilenameValidator invalid set
name(name < ' ' | name > '~') = '_';            % non-printable / non-ASCII
name = strtrim(name);
if isempty(name)
    name = 'UnknownSubject';
end

td = datetime('now');
td.Format = "yyMMdd'T'HHmmss";

ffn = fullfile(char(rootDir), name, sprintf('%s_%s.ts', name, char(td)));
