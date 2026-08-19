function report = smoke_test_videoconverter()
% report = smoke_test_videoconverter()
% Lightweight smoke test for util.VideoConverter and gui.VideoConverterSetup.
%
% Verifies:
%   1)  Dependency bootstrap locates ffmpeg/ffprobe and degrades (does not
%       throw) on a bogus preferred path.
%   2)  buildArgs is a pure function producing correctly-ordered, correctly
%       quoted ffmpeg command lines, including the FastSearch double-seek
%       guard and even-dimension scale truncation.
%   3)  A synthetic fixture (ffmpeg lavfi testsrc/sine) can be generated
%       with no external test files required.
%   4)  Recursive regexp scanning finds the right files and excludes
%       non-matches, non-recursive scans, and self-collisions.
%   5)  DryRun previews Args/OutputFile without touching disk.
%   6)  A live, serial conversion reports genuine INTERMEDIATE progress
%       (0<Percent<100 while running) -- the core reason this class does
%       not use ffmpegtranscode's blocking system() call.
%   7)  Parallel conversion (MaxParallel>1) completes all jobs with no
%       leftover .part files or leaked timers.
%   8)  Cancelling mid-run leaves no output and no partial file on disk.
%   9)  Overwrite="skip" leaves a completed output untouched on rescan.
%   10) DeleteSource only deletes the source after a VERIFIED successful
%       conversion -- a forced failure must leave the source intact, and a
%       source whose planned output equals itself is excluded by scan()
%       before it can ever be touched.
%   11) (Gated) Cross-check against the FFmpeg Toolbox's ffmpegtranscode,
%       when installed, for semantic (not byte-for-byte) agreement.
%   12) gui.VideoConverterSetup: tagged controls exist, Scan/Convert wire
%       through correctly headlessly, and delete() leaves no leaks.
%   13) gui.VideoConverterSetup layout: every side panel is tall enough for
%       the rows it declares, and an owned window opens tall enough for the
%       whole panel stack even when a saved Position is too short. Needs no
%       ffmpeg.
%   14) gui.VideoConverterSetup settings: every form label carries a tooltip,
%       Reset restores the class defaults without clearing the folders,
%       settings are remembered between sessions but never override a value
%       the caller asked for, and unticking a file keeps it out of the batch
%       (and out of the progress accounting). Only the last part needs ffmpeg.
%
% Requires ffmpeg.exe with the lavfi testsrc/sine input demuxer (any
% standard full/shared ffmpeg build). Steps that need it are skipped
% (not failed) when ffmpeg cannot be located.

report = struct();
report.timestamp = datetime('now');
report.steps = struct();

% ---- prefs / path guard: ensureDependencies may setpref('ffmpeg','exepath',...)
% and addpath the FFmpeg Toolbox collection folder -- restore both. ----
hadPref = ispref('ffmpeg', 'exepath');
oldPref = getpref('ffmpeg', 'exepath', '');
oldPath = path();
prefsCleanup = onCleanup(@() localRestore_(hadPref, oldPref, oldPath)); %#ok<NASGU>

testDir = fullfile(tempdir, 'epsych_vc_smoke', char(java.util.UUID.randomUUID));
mkdir(fullfile(testDir, 'nested'));
dirCleanup = onCleanup(@() localRmdir_(testDir)); %#ok<NASGU>

% Step 1: dependency bootstrap
stepName = 'dependencyBootstrap';
try
    [ok1, exe1, probe1, msg1] = util.VideoConverter.ensureDependencies("");
    assert(ok1, 'SmokeTest:DependencyMissing', 'ensureDependencies failed: %s', msg1);
    assert(isfile(exe1), 'SmokeTest:DependencyMissing', 'resolved ffmpeg.exe does not exist: %s', exe1);

    [ok1b, exe1b] = util.VideoConverter.ensureDependencies("");
    assert(ok1b && exe1b == exe1, 'SmokeTest:DependencyNotIdempotent', 'second ensureDependencies call gave a different result.');

    [okBogus, exeBogus, ~, msgBogus] = util.VideoConverter.ensureDependencies("C:\does\not\exist\ffmpeg.exe");
    assert(okBogus, 'SmokeTest:DependencyNoDegrade', 'ensureDependencies did not degrade past a bogus preferred path.');
    assert(exeBogus ~= "", 'SmokeTest:DependencyNoDegrade', 'ensureDependencies returned empty exe after degrading.'); %#ok<BDSCA>

    report.steps.(stepName) = struct('passed', true, 'detail', sprintf('ffmpeg="%s" ffprobe="%s" (msg on bogus path: %s)', exe1, probe1, msgBogus));
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end
haveFfmpeg = isfield(report.steps.(stepName), 'passed') && report.steps.(stepName).passed;

% Step 2: buildArgs unit tests (pure; no process spawned)
stepName = 'argBuilderUnit';
try
    base = struct('Range',[],'Units',"seconds",'FastSearch',"off",'InputFrameRate',[],'InputPixelFormat',"",'InputFrameSize',[], ...
        'AudioCodec',"aac",'AacBitRate',[],'Mp3Quality',[],'AudioSampleRate',[], ...
        'VideoCodec',"x264",'OutputFrameRate',[],'PixelFormat',"",'x264Preset',"medium",'x264Tune',"",'x264Crf',18,'Mpeg4Quality',1, ...
        'VideoScale',[],'VideoCrop',[],'VideoFlip',"",'VideoFillColor',"black",'ExtraArgs',string.empty(1,0));

    a1 = util.VideoConverter.buildArgs("C:\in.avi", "C:\out.mp4", base);
    assert(contains(a1,"-nostdin") && contains(a1,"-y") && contains(a1,"-hide_banner"), 'SmokeTest:ArgsMissingGlobals', 'missing required global flags.');
    assert(strfind(a1,"-hide_banner") < strfind(a1," -i "), 'SmokeTest:ArgOrder', 'global options must precede -i.'); %#ok<STRIFCND>
    ssIdx = strfind(a1," -i "); crfIdx = strfind(a1,"-crf");
    assert(ssIdx(1) < crfIdx(1), 'SmokeTest:ArgOrder', '-i must precede output options.');
    assert(endsWith(strtrim(a1), 'C:\out.mp4'), 'SmokeTest:ArgOrder', 'outfile must be the last token.');
    assert(contains(a1,"-c:v libx264") && contains(a1,"-crf 18") && contains(a1,"-preset medium") && contains(a1,"-pix_fmt yuv420p"), ...
        'SmokeTest:ArgsCodec', 'x264 codec mapping incorrect.');
    assert(contains(a1,"-c:a aac"), 'SmokeTest:ArgsCodec', 'aac codec mapping incorrect.');

    copyOpts = base; copyOpts.VideoCodec = "copy"; copyOpts.AudioCodec = "none";
    a2 = util.VideoConverter.buildArgs("C:\in.avi", "C:\out.mp4", copyOpts);
    assert(contains(a2,"-c:v copy") && contains(a2,"-an"), 'SmokeTest:ArgsCodec', 'copy/none mapping incorrect.');

    a3 = util.VideoConverter.buildArgs("C:\my dir\clip a.avi", "C:\out dir\o.mp4", base);
    assert(contains(a3,'"C:\my dir\clip a.avi"'), 'SmokeTest:ArgsQuoting', 'space-containing path was not quoted.');

    rangeOpts = base; rangeOpts.Range = [2 7]; rangeOpts.FastSearch = "on";
    a4 = util.VideoConverter.buildArgs("C:\in.avi", "C:\out.mp4", rangeOpts);
    assert(numel(strfind(a4, "-ss")) == 1, 'SmokeTest:DoubleSeek', 'expected exactly one -ss (FastSearch must not duplicate it on both sides).');
    assert(contains(a4,"-t 5.000000"), 'SmokeTest:ArgsRange', 'Range duration incorrect.');

    scaleOpts = base; scaleOpts.VideoScale = 0.33;
    a5 = util.VideoConverter.buildArgs("C:\in.avi", "C:\out.mp4", scaleOpts);
    assert(contains(a5,"trunc(iw*0.33/1/2)*2"), 'SmokeTest:ArgsScale', 'scale filter must truncate to even dimensions.');

    copyScaleOpts = base; copyScaleOpts.VideoScale = 0.5; copyScaleOpts.VideoCodec = "copy";
    threw = false;
    try
        util.VideoConverter.buildArgs("C:\in.avi", "C:\out.mp4", copyScaleOpts);
    catch ME2
        threw = strcmp(ME2.identifier, 'util:VideoConverter:FilterWithCopy');
    end
    assert(threw, 'SmokeTest:FilterWithCopy', 'VideoScale+VideoCodec=copy must throw util:VideoConverter:FilterWithCopy.');

    report.steps.(stepName) = struct('passed', true, 'detail', 'buildArgs flag order, quoting, codec mapping, and guards all correct.');
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% Step 3: synthetic fixture (no external test files required)
stepName = 'syntheticFixture';
haveFixture = false;
try
    if ~haveFfmpeg
        report.steps.(stepName) = struct('passed', true, 'detail', 'skipped: ffmpeg not available');
    else
        mkClip_(exe1, fullfile(testDir, 'clip_a.avi'), 5);
        mkClip_(exe1, fullfile(testDir, 'clip with space.avi'), 5);
        mkClip_(exe1, fullfile(testDir, 'nested', 'clip_b.avi'), 5);
        mkClip_(exe1, fullfile(testDir, 'odd.avi'), 2);
        fid = fopen(fullfile(testDir, 'notes.txt'), 'w'); fclose(fid);

        videoNeeded = {'clip_a.avi', 'clip with space.avi', fullfile('nested','clip_b.avi'), 'odd.avi'};
        for k = 1:numel(videoNeeded)
            assert(isfile(fullfile(testDir, videoNeeded{k})) && dir(fullfile(testDir, videoNeeded{k})).bytes > 0, ...
                'SmokeTest:FixtureMissing', 'fixture file missing or empty: %s', videoNeeded{k});
        end
        assert(isfile(fullfile(testDir, 'notes.txt')), 'SmokeTest:FixtureMissing', 'fixture file missing: notes.txt');
        haveFixture = true;
        report.steps.(stepName) = struct('passed', true, 'detail', 'Synthetic lavfi fixtures generated.');
    end
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% Step 4: recursive regexp scan
stepName = 'scanRegexp';
try
    if ~haveFixture
        report.steps.(stepName) = struct('passed', true, 'detail', 'skipped: no fixture');
    else
        c = util.VideoConverter(RootFolder=testDir, Recursive=true);
        files = c.scan();
        assert(numel(files) == 4, 'SmokeTest:ScanCount', 'expected 4 video files, got %d.', numel(files));
        assert(~any(endsWith(files,'.txt')), 'SmokeTest:ScanFilter', 'notes.txt matched the video FilePattern.');
        assert(issorted(files), 'SmokeTest:ScanSort', 'scan results must be sorted.');

        c.Recursive = false;
        filesFlat = c.scan();
        assert(numel(filesFlat) == 3, 'SmokeTest:ScanRecursive', 'non-recursive scan should exclude nested/clip_b.avi.');

        cEmpty = util.VideoConverter(RootFolder=fullfile(testDir,'nested','does_not_exist'));
        filesEmpty = cEmpty.scan();
        assert(isequal(filesEmpty, string.empty(0,1)), 'SmokeTest:ScanEmptyContract', 'empty scan must return string.empty(0,1).');
        delete(cEmpty);
        delete(c);
        report.steps.(stepName) = struct('passed', true, 'detail', 'Recursive/non-recursive scan and empty-root contract all correct.');
    end
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% Step 5: DryRun
stepName = 'dryRun';
try
    if ~haveFixture
        report.steps.(stepName) = struct('passed', true, 'detail', 'skipped: no fixture');
    else
        c = util.VideoConverter(RootFolder=testDir, DryRun=true, x264Preset="ultrafast");
        c.scan();
        c.convert();
        ok = c.waitUntilDone(15);
        assert(ok, 'SmokeTest:DryRunTimeout', 'dry run did not finish.');
        assert(all(c.Results.Status == 'dryrun'), 'SmokeTest:DryRunStatus', 'all rows should be dryrun.');
        assert(all(strlength(c.Results.Args) > 0), 'SmokeTest:DryRunArgs', 'Args must be populated.');
        for k = 1:height(c.Results)
            assert(~isfile(c.Results.OutputFile(k)), 'SmokeTest:DryRunCreatedFile', 'dry run must not create output files.');
            assert(isfile(c.Results.SourceFile(k)), 'SmokeTest:DryRunTouchedSource', 'dry run must not touch source files.');
        end
        delete(c);
        report.steps.(stepName) = struct('passed', true, 'detail', 'DryRun previewed Args/OutputFile with no filesystem side effects.');
    end
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% Step 6: serial conversion must show genuine intermediate progress.
% Uses its own dedicated, larger/slower clip (like step 8) rather than the
% small fixtures above -- a tiny 320x240/5s clip can finish inside a single
% poll tick on a fast machine, which would make this assertion flaky.
stepName = 'convertSerialProgress';
try
    if ~haveFfmpeg
        report.steps.(stepName) = struct('passed', true, 'detail', 'skipped: ffmpeg not available');
    else
        progDir = fullfile(testDir, 'prog');
        mkdir(progDir);
        mkClip_(exe1, fullfile(progDir, 'slow.avi'), 8, "640x480");

        c = util.VideoConverter(RootFolder=progDir, MaxParallel=1, x264Preset="veryslow", x264Crf=18);
        c.scan();
        assert(height(c.Results) == 1, 'SmokeTest:PrereqFailed', 'expected exactly one file.');

        evts = runWithProgressCapture_(c, 60);
        assert(c.Results.Status(1) == 'done', 'SmokeTest:ConvertFailed', 'conversion did not succeed: %s', c.Results.Message(1));

        progEvts = evts(cellfun(@(e) e.Stage == "progress", evts));
        pcts = cellfun(@(e) e.OverallPercent, progEvts);
        midPcts = pcts(pcts > 0 & pcts < 100 & ~isnan(pcts));
        % This assertion is the entire point of the class: it is IMPOSSIBLE
        % under ffmpegtranscode's blocking system() call, whose Period=1
        % progress timer cannot fire while the main thread is blocked.
        assert(~isempty(midPcts), 'SmokeTest:NoIntermediateProgress', ...
            'never observed an intermediate progress percentage -- the async engine may have regressed to blocking behavior.');

        assert(isfile(c.Results.OutputFile(1)), 'SmokeTest:OutputMissing', 'output file missing.');
        delete(c);
        report.steps.(stepName) = struct('passed', true, 'detail', sprintf('Observed %d intermediate progress tick(s): %s', numel(midPcts), mat2str(round(midPcts,1))));
    end
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% Step 7: parallel conversion. Uses its own dedicated subfolder so it is
% never affected by outputs earlier steps left behind in testDir.
stepName = 'convertParallel';
try
    if ~haveFfmpeg
        report.steps.(stepName) = struct('passed', true, 'detail', 'skipped: ffmpeg not available');
    else
        parDir = fullfile(testDir, 'parallel');
        mkdir(parDir);
        mkClip_(exe1, fullfile(parDir, 'p1.avi'), 4);
        mkClip_(exe1, fullfile(parDir, 'p2.avi'), 4);
        mkClip_(exe1, fullfile(parDir, 'p3.avi'), 4);

        c = util.VideoConverter(RootFolder=parDir, MaxParallel=3, x264Preset="ultrafast", x264Crf=30);
        c.scan();
        n = height(c.Results);
        assert(n == 3, 'SmokeTest:PrereqFailed', 'expected 3 files for parallel test, got %d.', n);

        evts = runWithProgressCapture_(c, 60);
        peakRunning = max(cellfun(@(e) e.NumRunning, evts));
        assert(all(c.Results.Status == 'done'), 'SmokeTest:ConvertFailed', 'not all parallel jobs succeeded.');

        partFiles = dir(fullfile(parDir, '**', '*.part*'));
        assert(isempty(partFiles), 'SmokeTest:LeftoverPart', 'leftover .part file(s) after parallel batch.');
        leaked = timerfind('Tag','util_VideoConverter');
        assert(isempty(leaked), 'SmokeTest:TimerLeak', 'scheduler timer leaked after parallel batch.');
        delete(c);
        report.steps.(stepName) = struct('passed', true, 'detail', sprintf('%d jobs done, peak concurrent running=%d, no leftovers.', n, peakRunning));
    end
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% Step 8: cancel mid-run
stepName = 'cancelMidRun';
try
    if ~haveFfmpeg
        report.steps.(stepName) = struct('passed', true, 'detail', 'skipped: ffmpeg not available');
    else
        longDir = fullfile(testDir, 'long');
        mkdir(longDir);
        mkClip_(exe1, fullfile(longDir, 'longclip.avi'), 30, "640x480");

        c = util.VideoConverter(RootFolder=longDir, MaxParallel=1, x264Preset="veryslow", x264Crf=18);
        c.scan();
        c.convert();
        pause(1.5);
        assert(c.IsRunning, 'SmokeTest:PrereqFailed', 'expected batch still running before cancel.');
        c.cancel();
        ok = c.waitUntilDone(15);
        assert(ok, 'SmokeTest:CancelTimeout', 'cancel did not settle.');
        assert(all(c.Results.Status == 'cancelled'), 'SmokeTest:CancelStatus', 'expected cancelled status.');
        assert(~isfile(c.Results.OutputFile(1)), 'SmokeTest:CancelLeftOutput', 'output must not exist after cancel.');
        partFiles = dir(fullfile(longDir, '**', '*.part*'));
        assert(isempty(partFiles), 'SmokeTest:CancelLeftPart', 'leftover .part file after cancel.');
        leaked = timerfind('Tag','util_VideoConverter');
        assert(isempty(leaked), 'SmokeTest:TimerLeak', 'scheduler timer leaked after cancel.');
        delete(c);
        report.steps.(stepName) = struct('passed', true, 'detail', 'Cancel mid-run left no output/partial file and no leaked timer.');
    end
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% Step 9: Overwrite="skip" on rescan
stepName = 'overwriteSkip';
try
    if ~haveFfmpeg
        report.steps.(stepName) = struct('passed', true, 'detail', 'skipped: ffmpeg not available');
    else
        skipDir = fullfile(testDir, 'skip');
        mkdir(skipDir);
        mkClip_(exe1, fullfile(skipDir, 'a.avi'), 2);

        c = util.VideoConverter(RootFolder=skipDir, x264Preset="ultrafast", x264Crf=30);
        c.scan();
        c.convert();
        assert(c.waitUntilDone(20), 'SmokeTest:ConvertTimeout', 'first pass did not finish.');
        assert(c.Results.Status(1) == 'done', 'SmokeTest:ConvertFailed', 'first pass did not succeed.');
        outFile = c.Results.OutputFile(1);
        info1 = dir(char(outFile));

        c.scan();
        assert(height(c.Results) == 1 && c.Results.Status(1) == 'skipped', ...
            'SmokeTest:SkipRescan', 'rescan should have pre-seeded Status=skipped for an existing output.');
        c.convert();
        assert(c.waitUntilDone(10), 'SmokeTest:ConvertTimeout', 'skip pass did not finish.');
        info2 = dir(char(outFile));
        assert(info1.datenum == info2.datenum, 'SmokeTest:SkipOverwrote', 'skip policy must not modify the existing output.');

        c.Overwrite = "overwrite";
        c.scan();
        assert(c.Results.Status(1) == 'pending', 'SmokeTest:OverwritePolicy', 'Overwrite=overwrite should leave the row pending, not skipped.');
        c.convert();
        assert(c.waitUntilDone(20), 'SmokeTest:ConvertTimeout', 'overwrite pass did not finish.');
        assert(c.Results.Status(1) == 'done', 'SmokeTest:OverwriteFailed', 'overwrite pass did not succeed.');

        delete(c);
        report.steps.(stepName) = struct('passed', true, 'detail', 'skip left output untouched; overwrite policy re-converted on request.');
    end
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% Step 10: DeleteSource gated on verified success
stepName = 'deleteSourceGated';
try
    if ~haveFfmpeg
        report.steps.(stepName) = struct('passed', true, 'detail', 'skipped: ffmpeg not available');
    else
        delDir = fullfile(testDir, 'del');
        mkdir(delDir);
        mkClip_(exe1, fullfile(delDir, 'src.avi'), 2);

        % forced failure: source must survive even with DeleteSource=true
        cBad = util.VideoConverter(RootFolder=delDir, DeleteSource=true, PixelFormat="bogus_fmt_xyz");
        cBad.scan();
        cBad.convert();
        assert(cBad.waitUntilDone(20), 'SmokeTest:ConvertTimeout', 'forced-failure pass did not finish.');
        assert(cBad.Results.Status(1) == 'failed', 'SmokeTest:ExpectedFailure', 'bogus pixel format should have failed.');
        assert(isfile(fullfile(delDir,'src.avi')), 'SmokeTest:SourceDeletedOnFailure', 'source must survive a failed conversion.');
        delete(cBad);

        % same-path case: naming settings that make the planned output equal
        % the source (NameSuffix="" + same extension) are caught earliest,
        % by scan()'s self-collision filter -- the file never becomes a row
        % at all, so it can never be launched, let alone clobbered. (The
        % canonical-path guard inside launchJob_ is a second, deeper layer
        % for paths that are byte-different but resolve to the same file,
        % e.g. via redundant path segments -- not exercised here.)
        cSame = util.VideoConverter(RootFolder=delDir, NameSuffix="", OutputExtension=".avi", DeleteSource=false);
        filesSame = cSame.scan();
        assert(isequal(filesSame, string.empty(0,1)), 'SmokeTest:SamePathNotCaught', ...
            'a source whose planned output equals itself must be excluded by scan(), not left pending.');
        assert(isfile(fullfile(delDir,'src.avi')) && dir(fullfile(delDir,'src.avi')).bytes > 0, ...
            'SmokeTest:SamePathClobbered', 'source was touched despite never being scanned as a job.');
        delete(cSame);

        % real success: source must be deleted only now
        cGood = util.VideoConverter(RootFolder=delDir, DeleteSource=true, x264Preset="ultrafast", x264Crf=30);
        cGood.scan();
        cGood.convert();
        assert(cGood.waitUntilDone(20), 'SmokeTest:ConvertTimeout', 'success pass did not finish.');
        assert(cGood.Results.Status(1) == 'done', 'SmokeTest:ConvertFailed', 'expected success.');
        assert(~isfile(fullfile(delDir,'src.avi')), 'SmokeTest:SourceNotDeleted', 'source should be deleted after verified success.');
        assert(isfile(cGood.Results.OutputFile(1)), 'SmokeTest:OutputMissing', 'output should exist.');
        delete(cGood);

        report.steps.(stepName) = struct('passed', true, 'detail', 'DeleteSource fires only after verified success; same-path and forced-failure cases leave the source intact.');
    end
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% Step 11: cross-check against the FFmpeg Toolbox (gated). Only the
% ffmpegtranscode call itself is wrapped: this is a THIRD-PARTY tool used
% purely as a reference oracle, and it has its own bugs (see the "toolbox
% bugs" note in util.VideoConverter's header) that are independent of our
% own code's correctness -- an internal toolbox error here is a skip, not
% a failure of this class.
stepName = 'crossCheckToolbox';
try
    if ~haveFixture || exist('ffmpegtranscode', 'file') ~= 2
        report.steps.(stepName) = struct('passed', true, 'detail', 'skipped: FFmpeg Toolbox (ffmpegtranscode) not on path');
    else
        refFile = fullfile(testDir, 'xcheck_ref.mp4');
        ourFile = fullfile(testDir, 'xcheck_ours.mp4');
        src = fullfile(testDir, 'clip_a.avi');

        % Do not pass AudioSampleRate (toolbox bug: mismatched param names)
        % and do not combine FastSearch=on with Range(1)>0 (toolbox bug:
        % double-seeks both sides) -- see util.VideoConverter doc header.
        toolboxOk = true;
        toolboxErr = "";
        try
            ffmpegtranscode(char(src), char(refFile), 'VideoCodec','x264', 'x264Crf',23, ...
                'x264Preset','ultrafast', 'AudioCodec','none', 'ProgressFcn','none');
        catch MEtb
            toolboxOk = false;
            toolboxErr = string(MEtb.message);
        end

        if ~toolboxOk
            report.steps.(stepName) = struct('passed', true, ...
                'detail', sprintf('skipped: ffmpegtranscode itself errored (toolbox-internal issue, not ours): %s', toolboxErr));
        else
            opts = struct('Range',[],'Units',"seconds",'FastSearch',"off",'InputFrameRate',[],'InputPixelFormat',"",'InputFrameSize',[], ...
                'AudioCodec',"none",'AacBitRate',[],'Mp3Quality',[],'AudioSampleRate',[], ...
                'VideoCodec',"x264",'OutputFrameRate',[],'PixelFormat',"",'x264Preset',"ultrafast",'x264Tune',"",'x264Crf',23,'Mpeg4Quality',1, ...
                'VideoScale',[],'VideoCrop',[],'VideoFlip',"",'VideoFillColor',"black",'ExtraArgs',string.empty(1,0));
            args = util.VideoConverter.buildArgs(string(src), string(ourFile), opts);
            [st, out] = system(sprintf('"%s" %s', exe1, args));
            assert(st == 0, 'SmokeTest:XCheckExecFailed', 'our ffmpeg invocation failed: %s', out);

            infoRef = ffmpeginfo(char(refFile));
            infoOurs = ffmpeginfo(char(ourFile));
            vRef = infoRef.streams(strcmp({infoRef.streams.type},'video'));
            vOurs = infoOurs.streams(strcmp({infoOurs.streams.type},'video'));
            assert(strcmpi(vRef(1).codec.name, vOurs(1).codec.name), 'SmokeTest:XCheckCodec', 'video codec differs from toolbox reference.');
            assert(abs(infoRef.duration - infoOurs.duration) < 0.15, 'SmokeTest:XCheckDuration', 'duration differs from toolbox reference by more than 0.15s.');

            report.steps.(stepName) = struct('passed', true, 'detail', 'Semantic agreement with ffmpegtranscode reference (codec + duration).');
        end
    end
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% Step 12: GUI smoke
stepName = 'guiSmoke';
try
    if ~haveFixture
        report.steps.(stepName) = struct('passed', true, 'detail', 'skipped: no fixture');
    else
        guiDir = fullfile(testDir, 'gui');
        mkdir(guiDir);
        mkClip_(exe1, fullfile(guiDir, 'g1.avi'), 2);
        mkClip_(exe1, fullfile(guiDir, 'g2.avi'), 2);

        c = util.VideoConverter(x264Preset="ultrafast", x264Crf=30);
        g = gui.VideoConverterSetup(c, PersistPrefs=false);
        cGuiCleanup = onCleanup(@() localDeleteGui_(g, c)); %#ok<NASGU>

        fig = g.Parent;
        tags = {'RootFolderField','ScanButton','ConvertButton','CancelButton', ...
            'DryRunCheckBox','FileTable','OverallLabel','PresetDropDown', ...
            'VideoCodecDropDown','CrfSpinner','AudioCodecDropDown','OverwriteDropDown'};
        for k = 1:numel(tags)
            h = findall(fig, 'Tag', ['VideoConverterSetup_' tags{k}]);
            assert(~isempty(h), 'SmokeTest:MissingControl', 'missing tagged control: %s', tags{k});
        end

        rootField = findall(fig, 'Tag', 'VideoConverterSetup_RootFolderField');
        scanBtn = findall(fig, 'Tag', 'VideoConverterSetup_ScanButton');
        convertBtn = findall(fig, 'Tag', 'VideoConverterSetup_ConvertButton');
        fileTable = findall(fig, 'Tag', 'VideoConverterSetup_FileTable');
        dryRunCb = findall(fig, 'Tag', 'VideoConverterSetup_DryRunCheckBox');

        rootField.Value = char(guiDir);
        rootField.ValueChangedFcn(rootField, []);
        scanBtn.ButtonPushedFcn(scanBtn, []);
        drawnow;
        assert(height(fileTable.Data) == 2, 'SmokeTest:GuiScanMismatch', 'expected 2 rows after Scan.');

        dryRunCb.Value = true;
        dryRunCb.ValueChangedFcn(dryRunCb, []);
        convertBtn.ButtonPushedFcn(convertBtn, []);
        t0 = tic;
        while c.IsRunning && toc(t0) < 15
            pause(0.1); drawnow;
        end
        assert(~c.IsRunning, 'SmokeTest:GuiConvertTimeout', 'dry-run convert via GUI did not finish.');
        assert(all(c.Results.Status == 'dryrun'), 'SmokeTest:GuiDryRunStatus', 'expected dryrun status.');

        clear cGuiCleanup
        delete(g);
        drawnow;
        assert(~isgraphics(fig), 'SmokeTest:FigureLeak', 'owned figure was not deleted.');
        leaked = timerfind('Tag','util_VideoConverter');
        assert(isempty(leaked), 'SmokeTest:TimerLeak', 'scheduler timer leaked after GUI delete.');
        delete(c);

        report.steps.(stepName) = struct('passed', true, 'detail', 'Tagged controls present; Scan/Convert wired correctly; clean teardown.');
    end
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% Step 13: GUI layout -- no fixture needed, so this runs even without ffmpeg.
% Opened with a deliberately too-short saved Position: the window must grow
% rather than leave the lower panels unreachable.
stepName = 'guiLayout';
try
    hadPos = ispref('ep_VideoConverter', 'Position');
    if hadPos, oldPos = getpref('ep_VideoConverter', 'Position'); end
    setpref('ep_VideoConverter', 'Position', [200 200 1000 420]);

    c = util.VideoConverter();
    g = gui.VideoConverterSetup(c);
    fig = g.Parent;
    drawnow;
    % A uifigure applies a Position written during construction on its own
    % schedule, and the panels reflow a beat after that, so measure in a
    % retry loop -- otherwise this step races the window it is measuring.
    panels = findobj(fig, 'Type', 'uipanel');
    tSettle = tic;
    while true
        tight = strings(numel(panels), 1);
        for k = 1:numel(panels)
            grid = panels(k).Children(1);
            rows = [grid.RowHeight{:}];
            need = sum(rows) + (numel(rows)-1)*grid.RowSpacing ...
                + grid.Padding(2) + grid.Padding(4);
            if panels(k).InnerPosition(4) + 0.5 < need
                tight(k) = sprintf('%s: %g available, %g needed', ...
                    panels(k).Title, panels(k).InnerPosition(4), need);
            end
        end
        tight(tight == "") = [];
        if isempty(tight) && fig.Position(4) > 420
            break
        end
        if toc(tSettle) > 10
            break
        end
        pause(0.2); drawnow;
    end

    % Each panel must be able to show every row its grid declares.
    assert(isempty(tight), 'SmokeTest:PanelClipped', ...
        'panel too short for its rows -- %s', strjoin(tight, '; '));

    % ...and the window must be tall enough for the stack of panels.
    assert(fig.Position(4) > 420, 'SmokeTest:WindowNotGrown', ...
        'window kept the too-short saved height (%g).', fig.Position(4));

    delete(g);
    drawnow;
    delete(c);
    if hadPos
        setpref('ep_VideoConverter', 'Position', oldPos);
    elseif ispref('ep_VideoConverter', 'Position')
        rmpref('ep_VideoConverter', 'Position');
    end

    report.steps.(stepName) = struct('passed', true, ...
        'detail', 'All side panels fit their rows; short saved Position was grown to fit.');
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% Step 14: per-file selection, Reset, remembered settings, and tooltips.
% Only the selection half needs real files.
stepName = 'guiSelectionResetPrefs';
try
    hadSettings = ispref('ep_VideoConverter', 'Settings');
    oldSettings = getpref('ep_VideoConverter', 'Settings', struct());

    % --- tooltips: every label that names a control must explain it ---
    c = util.VideoConverter();
    g = gui.VideoConverterSetup(c, PersistPrefs=false);
    fig = g.Parent;
    % Only the labels inside the setting panels: the status line and the
    % overall-progress readout are output, and explain nothing.
    labels = findobj(findobj(fig, 'Type', 'uipanel'), 'Type', 'uilabel');
    assert(numel(labels) > 10, 'SmokeTest:NoLabels', 'found only %d panel labels.', numel(labels));
    nakedMask = false(numel(labels), 1);
    labelText = strings(numel(labels), 1);
    for k = 1:numel(labels)
        % Blank labels are spacers for a self-labelling checkbox; the status
        % and overall-progress labels are output, not settings.
        labelText(k) = string(labels(k).Text);
        if strlength(strtrim(labelText(k))) == 0, continue; end
        nakedMask(k) = isempty(labels(k).Tooltip) || strlength(string(labels(k).Tooltip)) == 0;
    end
    naked = labelText(nakedMask);
    assert(isempty(naked), 'SmokeTest:MissingTooltip', ...
        'form label(s) with no tooltip: %s', strjoin(naked, ', '));
    for cb = [findall(fig,'Tag','VideoConverterSetup_RecursiveCheckBox'), ...
              findall(fig,'Tag','VideoConverterSetup_DeleteSourceCheckBox'), ...
              findall(fig,'Tag','VideoConverterSetup_DryRunCheckBox'), ...
              findall(fig,'Tag','VideoConverterSetup_AlongsideCheckBox'), ...
              findall(fig,'Tag','VideoConverterSetup_MirrorTreeCheckBox')]
        assert(~isempty(cb.Tooltip), 'SmokeTest:MissingTooltip', ...
            'self-labelling control with no tooltip: %s', cb.Text);
    end

    % --- Reset restores class defaults but keeps the folders ---
    resetBtn = findall(fig, 'Tag', 'VideoConverterSetup_ResetButton');
    assert(~isempty(resetBtn), 'SmokeTest:MissingControl', 'missing Reset button.');
    crfSpinner = findall(fig, 'Tag', 'VideoConverterSetup_CrfSpinner');
    rootField = findall(fig, 'Tag', 'VideoConverterSetup_RootFolderField');
    rootField.Value = char(testDir);
    rootField.ValueChangedFcn(rootField, []);
    crfSpinner.Value = 31;
    crfSpinner.ValueChangedFcn(crfSpinner, []);
    dfltCrf = util.VideoConverter().x264Crf;
    assert(c.x264Crf == 31, 'SmokeTest:GuiNotApplied', 'CRF edit did not reach the converter.');
    resetBtn.ButtonPushedFcn(resetBtn, []);
    assert(c.x264Crf == dfltCrf, 'SmokeTest:ResetIncomplete', ...
        'Reset left x264Crf at %d (expected the class default %d).', c.x264Crf, dfltCrf);
    assert(c.RootFolder == string(testDir), 'SmokeTest:ResetClearedFolder', ...
        'Reset must not clear the root folder.');
    assert(crfSpinner.Value == dfltCrf, ...
        'SmokeTest:ResetWidgetStale', 'Reset did not refresh the CRF widget.');
    delete(g); delete(c); drawnow;

    % --- remembered settings, and the caller's own values winning ---
    setpref('ep_VideoConverter', 'Settings', struct());
    c = util.VideoConverter();
    g = gui.VideoConverterSetup(c, PersistPrefs=true);
    fig = g.Parent;
    crfSpinner = findall(fig, 'Tag', 'VideoConverterSetup_CrfSpinner');
    crfSpinner.Value = 29;
    crfSpinner.ValueChangedFcn(crfSpinner, []);
    delete(g); delete(c); drawnow;

    c = util.VideoConverter();
    g = gui.VideoConverterSetup(c, PersistPrefs=true);
    assert(c.x264Crf == 29, 'SmokeTest:PrefsNotRestored', ...
        'remembered CRF was not applied (got %d).', c.x264Crf);
    delete(g); delete(c); drawnow;

    c = util.VideoConverter(x264Crf=21);
    g = gui.VideoConverterSetup(c, PersistPrefs=true);
    assert(c.x264Crf == 21, 'SmokeTest:PrefsOverrodeCaller', ...
        'a remembered setting overrode a value the caller asked for (got %d).', c.x264Crf);
    delete(g); delete(c); drawnow;

    % Opening with PersistPrefs=false must not touch what is remembered.
    c = util.VideoConverter();
    g = gui.VideoConverterSetup(c, PersistPrefs=false);
    fig = g.Parent;
    crfSpinner = findall(fig, 'Tag', 'VideoConverterSetup_CrfSpinner');
    crfSpinner.Value = 44;
    crfSpinner.ValueChangedFcn(crfSpinner, []);
    delete(g); delete(c); drawnow;
    keptCrf = getpref('ep_VideoConverter', 'Settings').x264Crf;
    assert(keptCrf == 29, 'SmokeTest:PrefsWrittenWhenOff', ...
        'PersistPrefs=false wrote to the saved settings (now %d).', keptCrf);

    % --- per-file selection decides what a batch converts ---
    if ~haveFixture
        selDetail = 'selection half skipped: no fixture';
    else
        selDir = fullfile(testDir, 'sel');
        mkdir(selDir);
        mkClip_(exe1, fullfile(selDir, 's1.avi'), 2);
        mkClip_(exe1, fullfile(selDir, 's2.avi'), 2);

        c = util.VideoConverter(RootFolder=selDir, DryRun=true, x264Preset="ultrafast");
        g = gui.VideoConverterSetup(c, PersistPrefs=false);
        fig = g.Parent;
        fileTable = findall(fig, 'Tag', 'VideoConverterSetup_FileTable');
        scanBtn = findall(fig, 'Tag', 'VideoConverterSetup_ScanButton');
        convertBtn = findall(fig, 'Tag', 'VideoConverterSetup_ConvertButton');
        scanBtn.ButtonPushedFcn(scanBtn, []);
        drawnow;
        assert(height(fileTable.Data) == 2, 'SmokeTest:SelScanMismatch', 'expected 2 rows.');
        assert(all(fileTable.Data.Do), 'SmokeTest:SelDefault', 'a fresh scan must tick every row.');

        % Untick row 1 exactly as a click on the checkbox would.
        fileTable.CellEditCallback(fileTable, struct('Indices',[1 1],'NewData',false,'PreviousData',true));
        assert(~c.Results.Selected(1) && c.Results.Selected(2), ...
            'SmokeTest:SelNotApplied', 'unticking row 1 did not reach the Converter.');
        assert(~fileTable.Data.Do(1), 'SmokeTest:SelNotShown', 'table did not show the untick.');

        convertBtn.ButtonPushedFcn(convertBtn, []);
        t0 = tic;
        while c.IsRunning && toc(t0) < 15
            pause(0.1); drawnow;
        end
        assert(~c.IsRunning, 'SmokeTest:SelConvertTimeout', 'batch did not finish.');
        assert(c.Results.Status(1) == 'pending', 'SmokeTest:SelConverted', ...
            'a deselected file was processed (status %s).', string(c.Results.Status(1)));
        assert(c.Results.Status(2) == 'dryrun', 'SmokeTest:SelSkipped', ...
            'the selected file was not processed (status %s).', string(c.Results.Status(2)));

        % ...and it must count as a finished batch, not a stuck 50%.
        c2 = util.VideoConverter(RootFolder=selDir, DryRun=true);
        c2.scan();
        c2.select(1, false);
        evts = runWithProgressCapture_(c2, 20);
        lastEvt = evts{end};
        assert(lastEvt.NumJobs == 1, 'SmokeTest:SelJobCount', ...
            'deselected rows must not be counted as jobs (NumJobs=%d).', lastEvt.NumJobs);
        assert(abs(lastEvt.OverallPercent - 100) < 1e-6, 'SmokeTest:SelOverall', ...
            'a finished batch with a deselected row reported %.1f%%.', lastEvt.OverallPercent);
        delete(c2);

        delete(g); delete(c); drawnow;
        selDetail = 'deselected file left pending; selected file converted; progress counted only the batch';
    end

    localRestoreSettings_(hadSettings, oldSettings);
    report.steps.(stepName) = struct('passed', true, 'detail', ...
        sprintf('Tooltips on every form label; Reset restores defaults and keeps folders; settings remembered without overriding caller values; %s.', selDetail));
catch ME
    localRestoreSettings_(hadSettings, oldSettings);
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

stepNames = fieldnames(report.steps);
stepPassed = false(size(stepNames));
for i = 1:numel(stepNames)
    stepPassed(i) = logical(report.steps.(stepNames{i}).passed);
end
report.allPassed = all(stepPassed);

if report.allPassed
    fprintf('VideoConverter smoke test PASSED (%d/%d steps).\n', nnz(stepPassed), numel(stepPassed));
else
    fprintf('VideoConverter smoke test FAILED (%d/%d steps).\n', nnz(stepPassed), numel(stepPassed));
    for i = 1:numel(stepNames)
        if ~report.steps.(stepNames{i}).passed
            fprintf('  - %s failed:\n%s\n', stepNames{i}, report.steps.(stepNames{i}).detail);
        end
    end
end

end

function evts = runWithProgressCapture_(c, timeoutSec)
% Start c.convert(), collecting every Progress event, and block until the
% batch finishes. Errors (rather than returning a status) on timeout, so
% callers can rely on a plain assert-free happy path.
evts = {};
c.ProgressFcn = @(~,e) collect_(e);
c.convert();
ok = c.waitUntilDone(timeoutSec);
if ~ok
    error('SmokeTest:ConvertTimeout', 'conversion did not finish within %g s.', timeoutSec);
end
    function collect_(e)
        evts{end+1} = e; %#ok<AGROW>
    end
end

function mkClip_(exe, outFile, durationSec, sizeStr)
if nargin < 4
    sizeStr = "320x240";
end
cmd = sprintf(['"%s" -hide_banner -loglevel error -nostdin -y ' ...
    '-f lavfi -i "testsrc=size=%s:rate=30:duration=%g" ' ...
    '-f lavfi -i "sine=frequency=440:duration=%g" ' ...
    '-c:v libx264 -crf 30 -preset ultrafast -pix_fmt yuv420p -c:a aac -shortest "%s"'], ...
    exe, sizeStr, durationSec, durationSec, outFile);
[st, out] = system(cmd);
assert(st == 0, 'SmokeTest:FixtureGenFailed', 'ffmpeg fixture generation failed: %s', out);
end

function localRestore_(hadPref, oldPref, oldPath)
if hadPref
    setpref('ffmpeg', 'exepath', oldPref);
elseif ispref('ffmpeg', 'exepath')
    rmpref('ffmpeg', 'exepath');
end
path(oldPath);
end

function localRestoreSettings_(hadSettings, oldSettings)
% Put the operator's own remembered VideoConverter settings back: this test
% opens GUIs with PersistPrefs=true, which writes them.
if hadSettings
    setpref('ep_VideoConverter', 'Settings', oldSettings);
elseif ispref('ep_VideoConverter', 'Settings')
    rmpref('ep_VideoConverter', 'Settings');
end
end

function localRmdir_(d)
if isfolder(d)
    try
        rmdir(d, 's');
    catch
    end
end
end

function localDeleteGui_(g, c)
if ~isempty(g) && isvalid(g)
    delete(g);
end
if ~isempty(c) && isvalid(c)
    delete(c);
end
end
