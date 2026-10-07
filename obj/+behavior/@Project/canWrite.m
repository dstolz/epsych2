function tf = canWrite(P)
% tf = canWrite(P)
% Whether the project file can be saved where it is: the store folder is
% created if it does not exist yet, and a .probe file is written into it and
% deleted. False when the store path is a FILE, or the folder cannot be
% created or written (a read-only share, a synced folder without
% permission). The answer is kept for the object's life -- the store of an
% open project never changes -- so a refusal is probed and logged once.
%
% Unlike open, this does write: it is what save asks before writing.
%
% Returns:
%   tf - logical scalar
%
% See also: behavior.Project.save, behavior.Project.open

if ~isempty(P.CanWrite_) && P.CanWritePath_ == P.Store
    tf = P.CanWrite_;
    return
end

tf = false;
why = "";
if isfile(P.Store)
    why = "the store path is a file, not a folder";
elseif ~isfolder(P.Store)
    [made, msg] = mkdir(P.Store);
    if ~made
        why = "the folder cannot be created: " + string(msg);
    end
end
if why == ""
    probe = fullfile(P.Store, ".probe-" + feature('getpid'));
    fid = fopen(probe, 'w');
    if fid < 0
        why = "the folder cannot be written";
    else
        fwrite(fid, 'probe');
        fclose(fid);
        delete(probe);
        tf = true;
    end
end

if ~tf
    vprintf(1, 'behavior.Project: the store "%s" cannot be written (%s)', P.Store, why)
end
P.CanWrite_ = tf;
P.CanWritePath_ = P.Store;

end
