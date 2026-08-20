function files = scan(obj)
% files = obj.scan()
% Recursively search RootFolder for files whose full path matches
% FilePattern (a regular expression), excluding any match for
% ExcludePattern and any file that is itself a planned conversion output
% (self-collision, independent of ExcludePattern -- catches user-
% customized suffixes/extensions).
%
% Populates Results with one row per matched source file. Status is
% pre-seeded against the current Overwrite policy when the planned output
% already exists on disk ('skipped' or 'failed'); everything else starts
% 'pending'.
%
% Returns string.empty(0,1) when RootFolder is unset, missing, or no
% files match, so callers can iterate the result without guarding.
arguments
    obj (1,1) util.VideoConverter
end

files = string.empty(0,1);
obj.Results = util.VideoConverter.emptyResults();

if obj.RootFolder == "" || ~isfolder(obj.RootFolder)
    vprintf(0, 1, 'util.VideoConverter: RootFolder "%s" does not exist.', obj.RootFolder);
    return
end

if obj.Recursive
    d = dir(fullfile(obj.RootFolder, "**", "*"));
else
    d = dir(fullfile(obj.RootFolder, "*"));
end
d = d(~[d.isdir]);
if isempty(d)
    return
end

allFiles = string({d.folder})' + filesep + string({d.name})';
allBytes = [d.bytes]';

keep = ~cellfun(@isempty, regexp(cellstr(allFiles), obj.FilePattern, 'once'));
allFiles = allFiles(keep);
allBytes = allBytes(keep);
if isempty(allFiles)
    return
end

if obj.ExcludePattern ~= ""
    drop = ~cellfun(@isempty, regexp(cellstr(allFiles), obj.ExcludePattern, 'once'));
    allFiles = allFiles(~drop);
    allBytes = allBytes(~drop);
end
if isempty(allFiles)
    return
end

[allFiles, idx] = sort(allFiles);
allBytes = allBytes(idx);

planned = strings(numel(allFiles), 1);
for k = 1:numel(allFiles)
    planned(k) = util.VideoConverter.planOutput(allFiles(k), obj);
end

selfCollision = ismember(lower(allFiles), lower(planned));
if any(selfCollision)
    vprintf(1, 'util.VideoConverter: excluding %d file(s) that are themselves planned conversion outputs.', nnz(selfCollision));
end
allFiles = allFiles(~selfCollision);
allBytes = allBytes(~selfCollision);
planned  = planned(~selfCollision);

n = numel(allFiles);
if n == 0
    return
end

status = repmat("pending", n, 1);
message = repmat("", n, 1);
for k = 1:n
    if isfile(planned(k))
        switch obj.Overwrite
            case "skip"
                status(k) = "skipped";
            case "error"
                status(k) = "failed";
                message(k) = "Output file already exists.";
            case "overwrite"
                % leave pending; commitOutput_ will overwrite at commit time
        end
    end
end

% Every match starts selected: a scan is a proposal to convert what it
% found, and deselecting is the operator narrowing it (see select).
T = table( ...
    (1:n)', true(n,1), allFiles, planned, categorical(status, util.VideoConverter.StatusCategories_), ...
    zeros(n,1), nan(n,1), zeros(n,1), nan(n,1), nan(n,1), ...
    allBytes, zeros(n,1), nan(n,1), message, repmat("",n,1), ...
    NaT(n,1), NaT(n,1), ...
    'VariableNames', {'Index','Selected','SourceFile','OutputFile','Status', ...
        'Percent','DurationSec','ElapsedSec','Fps','Speed', ...
        'BytesIn','BytesOut','ExitCode','Message','Args','StartTime','EndTime'});

obj.Results = T;
files = allFiles;
obj.emitProgress_('scanned', NaN);
end
