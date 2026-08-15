function prepareRecording(obj, runtime)
% prepareRecording(obj, runtime)
% Point RHX at this run's data filename just before the session enters Record
% mode. Called by epsych.RunExpt on every interface immediately before the
% mode write (see ExptDispatch), while the hardware is still stopped.
%
% The recording is named after subject 1's reserved data file
% (runtime.SessionDataFilename(1)), mirroring the webcam recorder, so the .rhd
% pairs by prefix with the .mat and the .ts. RHX ignores filename.* while the
% board is running, so the board is forced to Stop first — which also prevents
% an operator-started recording from being silently adopted by the mode
% property's AbortSet.
%
% Parameters
%   obj     - hw.Intan_RHX instance.
%   runtime - epsych.Runtime for the run (provides SessionDataFilename,
%             DefaultDataPath, isTest).
arguments
    obj
    runtime (1,1) epsych.Runtime
end

if ~obj.IsConnected
    return
end

% Reload the settings file only if the machine pref changed since connect.
obj.applySettingsFile_();

root = obj.RecordingRootDir;
if isempty(root)
    root = char(runtime.DefaultDataPath);
end

fn = runtime.SessionDataFilename;
if isempty(fn) || strlength(fn(1)) == 0
    vprintf(0, 1, 'Intan_RHX: no session data filename reserved; recording target not set.');
    return
end

[path, base] = obj.deriveRecordingTarget_(root, fn(1));

% A space anywhere in the target cannot be sent to RHX. Unlike the webcam
% (a peripheral, which never aborts a run), Intan is the primary acquisition:
% a silently unrecorded session looks normal and the loss surfaces only in
% analysis. Abort a Record run; a Preview never touches disk, so warn instead.
if any(isspace(path)) || any(isspace(base))
    msg = sprintf(['Intan recording target contains spaces, which RHX''s command ' ...
        'grammar cannot express (path="%s", basefilename="%s").'], path, base);
    if runtime.isTest
        vprintf(0, 1, '%s Preview does not record; continuing.', msg);
        return
    end
    error('hw:Intan_RHX:UnrepresentableFilename', ...
        ['%s Set a space-free Intan Recording Path (Customize > Paths) or rename ' ...
         'the subject.'], msg);
end

% filename.* has no effect while the board is running.
obj.ensureStopped_();

% Create the target directory when the server is on this machine (RHX may not
% create it itself). For a remote Host we cannot check, so just push the path.
if obj.isLocalHost_() && ~isfolder(path)
    [ok, emsg] = mkdir(path);
    if ~ok
        vprintf(0, 1, 'Intan_RHX: could not create recording directory "%s": %s', path, emsg);
    end
end

obj.setRecordingTarget_(path, base);
vprintf(1, 'Intan_RHX: recording target %s/%s_<timestamp>%s', path, base, obj.fileExt_());
