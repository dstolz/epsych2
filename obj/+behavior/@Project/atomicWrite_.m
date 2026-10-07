function ok = atomicWrite_(P, txt)
% ok = atomicWrite_(P, txt)
% Write the project file so no reader ever sees half of it: the text goes to
% project.json.tmp-<pid> in the store folder (the same volume, so the move is
% a rename) and is moved over the file, up to three tries -- a file another
% program is reading can refuse a rename for a moment on Windows. The file
% being replaced is copied to <Store>/.history first, the newest
% HistoryKeep copies kept; a history that cannot be written is logged and
% does not stop the save.
%
% Returns:
%   ok - true when the file holds txt. On failure the old file is untouched
%        and no temp file is left behind.

ok = false;
if ~isfolder(P.Store)
    [made, msg] = mkdir(P.Store);
    if ~made
        vprintf(0, 1, 'behavior.Project: the store folder "%s" could not be created: %s', P.Store, msg)
        return
    end
end

tmp = P.File + ".tmp-" + feature('getpid');
fid = fopen(tmp, 'w');
if fid < 0
    vprintf(0, 1, 'behavior.Project: cannot write "%s"', tmp)
    return
end
closer = onCleanup(@() fclose(fid));
fwrite(fid, unicode2native(char(txt), 'UTF-8'), 'uint8');
clear closer

if isfile(P.File)
    localArchive(P);
end

why = "";
for attempt = 1:3
    [moved, msg] = movefile(tmp, P.File, 'f');
    if moved
        ok = true;
        break
    end
    why = string(msg);
    pause(0.05 * attempt);
end
if ~ok
    if isfile(tmp)
        delete(tmp);
    end
    vprintf(0, 1, 'behavior.Project: "%s" could not be replaced: %s', P.File, why)
end

end


function localArchive(P)
% Copy the file about to be replaced into .history, named by when it was
% written, and keep the newest HistoryKeep copies.
folder = fullfile(P.Store, behavior.Project.HistoryFolder);
try
    if ~isfolder(folder)
        mkdir(folder);
    end
    d = dir(P.File);
    stamp = string(char(datetime(d.datenum, 'ConvertFrom', 'datenum'), 'yyMMdd''T''HHmmss'));
    target = fullfile(folder, "project_" + stamp + ".json");
    n = 1;
    while isfile(target)
        n = n + 1;
        target = fullfile(folder, "project_" + stamp + "_" + n + ".json");
    end
    [copied, msg] = copyfile(P.File, target);
    if ~copied
        error('behavior:Project:History', '%s', msg);
    end

    h = dir(fullfile(folder, 'project_*.json'));
    h = h(~[h.isdir]);
    [~, order] = sortrows([[h.datenum]' (1:numel(h))'], [-1 -2]);
    h = h(order);
    for k = behavior.Project.HistoryKeep + 1:numel(h)
        delete(fullfile(h(k).folder, h(k).name));
    end
catch ME
    vprintf(1, 'behavior.Project: the previous project file could not be kept in %s: %s', folder, ME.message)
end
end
