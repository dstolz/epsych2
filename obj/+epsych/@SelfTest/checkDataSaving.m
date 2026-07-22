function results = checkDataSaving(self)
% results = checkDataSaving(self)
% Exercise the disk paths a session depends on: the data directory, the crash
% recovery directory the timer StartFcn asserts on, and the per-trial append
% pattern the trial loop uses on every completed trial.
%
% Files are written only to temporary names, which are removed again.
%
% Returns:
%	results	- Result struct array; see epsych.SelfTest.result.
%
% See also: epsych.SelfTest.run, ep_TimerFcn_RunTime, ep_TimerFcn_Start
arguments
    self
end

GROUP = "DataSaving";
results = epsych.SelfTest.result();

if isempty(self.RunExpt) || ~isvalid(self.RunExpt)
    results = epsych.SelfTest.result("H0_NoSession", GROUP, "Data saving", "skip", ...
        'No RunExpt session is open.');
    return
end

dataPath = char(self.RunExpt.dfltDataPath);

% --- H1: data directory writable ---------------------------------------
t = tic;
r = localCheckWritable("H1_DataPath", GROUP, "Data save path", dataPath, ...
    "Set a writable directory in Customize > Paths.");
results = [results epsych.SelfTest.withTime(r, toc(t))];

% --- H2: crash-recovery directory --------------------------------------
% ep_TimerFcn_Start asserts on this folder and aborts the run if it is
% missing, so it is worth proving before the operator presses Run.
t = tic;
tempDataDir = char(self.RunExpt.RUNTIME.TempDataDir);
if isempty(tempDataDir) || ~isfolder(tempDataDir)
    E = EPsychInfo;
    tempDataDir = fullfile(fileparts(E.root), 'DATA');
end
r = localCheckWritable("H2_TempDataDir", GROUP, "Crash-recovery path", tempDataDir, ...
    "The run-time data directory is created beside the repository; check permissions on its parent.");
results = [results epsych.SelfTest.withTime(r, toc(t))];

% --- H3: per-trial append round trip -----------------------------------
% Mirrors exactly what ep_TimerFcn_RunTime does after every trial. A slow or
% flaky drive here shows up as dropped trials at run time.
t = tic;
probeDir = tempDataDir;
if ~isfolder(probeDir)
    probeDir = tempdir;
end
probeFile = fullfile(probeDir, sprintf('epsych_selftest_%s.mat', ...
    char(datetime('now', Format='yyMMddHHmmssSSS'))));
cleanupProbe = onCleanup(@() localDeleteFile(probeFile));

nTrials = 3;
appendTimes = nan(1, nTrials);
try
    info = struct('Subject', 'SelfTest', 'CompStartTimestamp', datetime('now'), 'isTest', true);
    save(probeFile, 'info', '-v6');

    for k = 1:nTrials
        data = struct('TrialIndex', k, 'TrialID', k, ...
            'computerTimestamp', datetime('now'), 'isTest', true);
        varName = sprintf('data_%04d', k);
        eval([varName ' = data;']);
        tk = tic;
        save(probeFile, varName, '-append', '-v6');
        appendTimes(k) = toc(tk);
    end

    S = load(probeFile);
    missing = strings(1,0);
    for k = 1:nTrials
        varName = sprintf('data_%04d', k);
        if ~isfield(S, varName)
            missing(end+1) = string(varName);
        elseif S.(varName).TrialIndex ~= k
            missing(end+1) = string(varName) + " (wrong contents)";
        end
    end

    detail = [ ...
        sprintf("Probe file: %s", probeFile), ...
        sprintf("Mean append: %.1f ms", 1000*mean(appendTimes, 'omitnan')), ...
        sprintf("Max append:  %.1f ms", 1000*max(appendTimes, [], 'omitnan'))];

    if ~isempty(missing)
        r = epsych.SelfTest.result("H3_AppendRoundTrip", GROUP, "Per-trial save round trip", "fail", ...
            sprintf('%d of %d appended trial(s) did not read back correctly.', numel(missing), nTrials), ...
            Detail = [missing detail], ...
            Remedy = "Trial data would be lost at run time. Save to a local disk rather than a network share.");
    elseif max(appendTimes) > 0.25
        r = epsych.SelfTest.result("H3_AppendRoundTrip", GROUP, "Per-trial save round trip", "warn", ...
            sprintf('Trial appends round-trip correctly but take up to %.0f ms.', 1000*max(appendTimes)), ...
            Detail = detail, ...
            Remedy = "A slow drive stalls the trial loop; prefer a local disk for the run-time data directory.");
    else
        r = epsych.SelfTest.result("H3_AppendRoundTrip", GROUP, "Per-trial save round trip", "pass", ...
            sprintf('%d trial(s) appended and read back, mean %.1f ms.', nTrials, 1000*mean(appendTimes)), ...
            Detail = detail);
    end
catch ME
    r = epsych.SelfTest.result("H3_AppendRoundTrip", GROUP, "Per-trial save round trip", "fail", ...
        sprintf('Writing trial data failed: %s', ME.message), ...
        Detail = string(probeFile), ...
        Remedy = "The run would lose data. Check free space and write permission on the run-time data directory.");
end
results = [results epsych.SelfTest.withTime(r, toc(t))];

% --- H4: reserved session filenames ------------------------------------
t = tic;
CONFIG = self.RunExpt.CONFIG;
if isempty(CONFIG) || ~isfield(CONFIG,'SUBJECT') || ~isa(CONFIG(1).SUBJECT,'epsych.Subject')
    r = epsych.SelfTest.result("H4_Filenames", GROUP, "Session filenames", "skip", ...
        'No subjects are configured.');
else
    names = strings(1, numel(CONFIG));
    problems = strings(1,0);
    for i = 1:numel(CONFIG)
        S = CONFIG(i).SUBJECT;
        try
            names(i) = string(epsych.RunExpt.defaultFilename( ...
                fullfile(dataPath, char(string(S.Name))), char(string(S.Name))));
        catch ME
            problems(end+1) = sprintf("%s: %s", string(S.Name), ME.message);
        end
    end

    if numel(unique(names)) ~= numel(names)
        problems(end+1) = "Two subjects would be given the same data filename.";
    end

    if isempty(problems)
        r = epsych.SelfTest.result("H4_Filenames", GROUP, "Session filenames", "pass", ...
            sprintf('%d unique data filename(s) reserved.', numel(names)), ...
            Detail = names);
    else
        r = epsych.SelfTest.result("H4_Filenames", GROUP, "Session filenames", "fail", ...
            sprintf('%d problem(s) building session filenames.', numel(problems)), ...
            Detail = [problems names], ...
            Remedy = "Give each subject a distinct, filename-safe name.");
    end
end
results = [results epsych.SelfTest.withTime(r, toc(t))];

% --- H5: saving function reachability ----------------------------------
% ep_SaveDataFcn is interactive (msgbox and uiputfile), so invoking it here
% would hijack the UI. H3 covers the disk path it eventually uses; this only
% confirms the callback and the field it is gated on.
t = tic;
savingFcn = string(self.RunExpt.FUNCS.SavingFcn);
detail = [ ...
    "SaveDataCallback only calls the saving function when RUNTIME.TRIALS has a DATA field,", ...
    "which is populated by the first completed trial.", ...
    "This check does not invoke the saving function: the default is interactive."];

if isempty(which(savingFcn))
    r = epsych.SelfTest.result("H5_SavingFcn", GROUP, "Saving function reachable", "fail", ...
        sprintf('Saving function "%s" does not resolve; data could not be saved.', savingFcn), ...
        Detail = detail, ...
        Remedy = "Set a valid saving function in Customize > Functions.");
else
    hasData = isstruct(self.RunExpt.RUNTIME.TRIALS) && isfield(self.RunExpt.RUNTIME.TRIALS, 'DATA');
    r = epsych.SelfTest.result("H5_SavingFcn", GROUP, "Saving function reachable", "pass", ...
        sprintf('"%s" resolves; RUNTIME currently %s trial data to save.', ...
        savingFcn, string(missingOrHas(hasData))), ...
        Detail = detail);
end
results = [results epsych.SelfTest.withTime(r, toc(t))];

% --- H6: video recording pairing ---------------------------------------
t = tic;
if ~getpref('ep_RunExpt_Video','EnableRecording',false)
    r = epsych.SelfTest.result("H6_Video", GROUP, "Video recording paths", "skip", ...
        'Video recording is disabled.');
elseif isempty(CONFIG) || ~isfield(CONFIG,'SUBJECT') || ~isa(CONFIG(1).SUBJECT,'epsych.Subject')
    r = epsych.SelfTest.result("H6_Video", GROUP, "Video recording paths", "skip", ...
        'Video recording is enabled but no subject is configured.');
else
    root = strtrim(char(getpref('ep_RunExpt_Video','RecordingRootDir','')));
    usedFallback = isempty(root);
    if usedFallback
        root = dataPath;
    end

    try
        subjectName = string(CONFIG(1).SUBJECT.Name);
        dataFile = epsych.RunExpt.defaultFilename(fullfile(dataPath, char(subjectName)), char(subjectName));
        videoFile = epsych.RunExpt.videoRecordingFilename(root, dataFile);
        videoDir = fileparts(videoFile);

        detail = [ ...
            sprintf("Recording root: %s%s", root, localFallbackNote(usedFallback)), ...
            sprintf("Video file:     %s", videoFile), ...
            sprintf("Paired with:    %s", dataFile)];

        if isfolder(videoDir) || localCanCreate(videoDir)
            r = epsych.SelfTest.result("H6_Video", GROUP, "Video recording paths", "pass", ...
                'Recording path resolves and pairs with the data filename.', ...
                Detail = detail);
        else
            r = epsych.SelfTest.result("H6_Video", GROUP, "Video recording paths", "fail", ...
                sprintf('The recording directory cannot be created: %s', videoDir), ...
                Detail = detail, ...
                Remedy = "Set a writable Video Recording Path in Customize > Paths.");
        end
    catch ME
        r = epsych.SelfTest.result("H6_Video", GROUP, "Video recording paths", "fail", ...
            sprintf('Could not resolve the recording path: %s', ME.message), ...
            Remedy = "Set a valid Video Recording Path in Customize > Paths.");
    end
end
results = [results epsych.SelfTest.withTime(r, toc(t))];

end

% -----------------------------------------------------------------------
function r = localCheckWritable(id, group, name, pth, remedy)
% Prove a directory is usable by creating it if needed and writing, reading,
% and deleting a probe file. Existence alone says nothing about permission.
if isempty(pth)
    r = epsych.SelfTest.result(id, group, name, "fail", 'No path is set.', Remedy = remedy);
    return
end

created = false;
if ~isfolder(pth)
    [ok, msg] = mkdir(pth);
    if ~ok
        r = epsych.SelfTest.result(id, group, name, "fail", ...
            sprintf('Directory does not exist and cannot be created: %s', pth), ...
            Detail = string(msg), Remedy = remedy);
        return
    end
    created = true;
end

probe = fullfile(pth, sprintf('.epsych_selftest_%s.tmp', ...
    char(datetime('now', Format='yyMMddHHmmssSSS'))));
try
    fid = fopen(probe, 'wt');
    if fid < 0
        error('epsych:SelfTest:ProbeOpenFailed', 'fopen returned %d', fid);
    end
    fprintf(fid, 'epsych self-test probe');
    fclose(fid);

    txt = fileread(probe);
    delete(probe);

    if ~contains(txt, 'epsych self-test probe')
        r = epsych.SelfTest.result(id, group, name, "fail", ...
            sprintf('A probe file written to %s did not read back correctly.', pth), ...
            Remedy = remedy);
        return
    end
catch ME
    r = epsych.SelfTest.result(id, group, name, "fail", ...
        sprintf('Directory is not writable: %s', pth), ...
        Detail = string(ME.message), Remedy = remedy);
    return
end

detail = "Path: " + string(pth);
if created
    detail(end+1) = "Directory was created by this check.";
end
detail(end+1) = localFreeSpace(pth);

r = epsych.SelfTest.result(id, group, name, "pass", ...
    sprintf('Writable: %s', pth), Detail = detail);
end

% -----------------------------------------------------------------------
function s = localFreeSpace(pth)
% Free space on the volume holding pth, reported best-effort.
s = "Free space: unavailable";
try
    f = java.io.File(pth);
    bytes = f.getFreeSpace();
    if bytes > 0
        s = sprintf("Free space: %.1f GB", double(bytes) / 2^30);
    end
catch
    % Java is unavailable in some MATLAB configurations; not a finding.
end
end

% -----------------------------------------------------------------------
function tf = localCanCreate(pth)
% True when pth can be created (and is removed again if it did not exist).
tf = false;
if isfolder(pth)
    tf = true;
    return
end
[ok, ~] = mkdir(pth);
if ok
    tf = true;
    rmdir(pth);
end
end

% -----------------------------------------------------------------------
function localDeleteFile(ffn)
% Remove a probe file if it was created.
if isfile(ffn)
    delete(ffn);
end
end

% -----------------------------------------------------------------------
function s = missingOrHas(tf)
if tf
    s = "has";
else
    s = "has no";
end
end

% -----------------------------------------------------------------------
function s = localFallbackNote(usedFallback)
if usedFallback
    s = '  (unset; falling back to the Data Save Path)';
else
    s = '';
end
end
