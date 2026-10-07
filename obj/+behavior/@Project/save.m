function ok = save(P)
% ok = save(P)
% Write the project file, merging first with whatever another writer saved
% since this object last read it.
%
% Refused (ok false, the reason logged and added to Warnings) when the
% project is ReadOnly or its store cannot be written (canWrite). Otherwise:
%   1. When the file on disk is no longer the one last read (bytes and
%      modification time, LoadedStamp), it is read again and merged record
%      by record into this object (merge_). A file that has become
%      unreadable, or was rewritten by a newer EPsych, is not overwritten.
%   2. Revision goes up by one; Saved and Writer name this save.
%   3. The previous file is copied to <Store>/.history (newest three kept)
%      and the new text is written to a temp file and moved over the old one.
% A save with nothing to save (not Dirty, and the file still the one read)
% writes nothing and returns true. The first save creates the store folder.
%
% Returns:
%   ok - true when the file now holds this object's state
%
% See also: behavior.Project.open, behavior.Project.canWrite

ok = false;
if P.ReadOnly
    vprintf(1, 'behavior.Project: not saving %s, which is read-only (%s)', P.File, ...
        strjoin(P.Warnings, " "))
    return
end
if ~P.canWrite()
    msg = "The project cannot be saved: its store folder cannot be written (" + P.Store ...
        + "). Open it with another Store folder.";
    P.Warnings(end+1, 1) = msg;
    vprintf(1, 'behavior.Project: %s', msg)
    return
end

current = behavior.Project.stamp_(P.File);
if ~isequal(current, P.LoadedStamp)
    if current.Exists
        [s, why] = behavior.Project.readFile_(P.File);
        if why ~= ""
            msg = "The project file changed on disk and can no longer be read (" + why ...
                + "), so it is not overwritten: " + P.File;
            P.Warnings(end+1, 1) = msg;
            vprintf(0, 1, 'behavior.Project: %s', msg)
            return
        end
        D = behavior.Project.fromStruct_(s, P.Root, P.Store);
        if D.ReadOnly
            P.ReadOnly = true;
            P.Warnings = [P.Warnings; D.Warnings];
            vprintf(0, 1, 'behavior.Project: the project file was rewritten by a newer EPsych; not saving %s', P.File)
            return
        end
        P.merge_(D);
        P.Warnings = [P.Warnings; D.Warnings];
        P.Base_ = behavior.Project.baseOf_(D);
        vprintf(2, 'behavior.Project: merged revision %d from disk (%s) into this project', ...
            D.Revision, D.Writer)
    end
    P.LoadedStamp = current;
    if ~P.Dirty && current.Exists
        % Nothing of ours to add: the file already holds what was merged.
        P.Base_ = behavior.Project.baseOf_(P);
        ok = true;
        return
    end
elseif ~P.Dirty && current.Exists
    vprintf(3, 'behavior.Project: nothing to save in %s', P.File)
    ok = true;
    return
end

previous = struct('Revision', P.Revision, 'Saved', P.Saved, 'Writer', P.Writer);
P.Revision = P.Revision + 1;
P.Saved = behavior.Project.now_();
P.Writer = behavior.Project.writer_();
txt = jsonencode(P.toStruct(), PrettyPrint = true);

if ~P.atomicWrite_(txt)
    P.Revision = previous.Revision;
    P.Saved = previous.Saved;
    P.Writer = previous.Writer;
    P.Warnings(end+1, 1) = "The project file could not be written: " + P.File;
    return
end

P.Dirty = false;
P.LoadedStamp = behavior.Project.stamp_(P.File);
P.Base_ = behavior.Project.baseOf_(P);
ok = true;
vprintf(2, 'behavior.Project: saved %s', P.summary())

end
