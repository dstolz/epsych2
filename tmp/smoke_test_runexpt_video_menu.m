function report = smoke_test_runexpt_video_menu()
% report = smoke_test_runexpt_video_menu()
% Smoke test for the RunExpt "Utilities > Video" submenu and the Batch
% Video Converter entry point. No VLC, webcam, or ffmpeg is required: the
% converter is constructed and handed to its GUI, never scanned or run.
%
% Verifies:
%   1) Utilities has a Video submenu holding exactly the three video items,
%      in order, and none of them is still a direct child of Utilities.
%   2) UpdateGUIstate's recursive tag search still reaches the live-view
%      item now that it is nested one level deeper.
%   3) LaunchUtility("VideoConverter") opens gui.VideoConverterSetup on a
%      converter seeded with the recording-root preference and the .ts
%      pattern, and idle.
%   4) An unset recording root falls back to the Data Save Path.

report = struct();
report.timestamp = datetime('now');
report.steps = struct();

PREF_GROUP = 'ep_RunExpt_Video';
snap = snapshotPrefs_(PREF_GROUP, {'RecordingRootDir'});
c = onCleanup(@() restorePrefs_(PREF_GROUP, snap));

% The converter GUI persists its window position by default, and this test
% force-deletes its figure rather than closing it; restore whatever the user
% had so a test run never resizes their real window.
guiSnap = snapshotPrefs_('ep_VideoConverter', {'Position'});
cGui = onCleanup(@() restorePrefs_('ep_VideoConverter', guiSnap));

rootDir = fullfile(tempdir, 'ep_video_menu_smoke');
if ~isfolder(rootDir), mkdir(rootDir); end
setpref(PREF_GROUP, 'RecordingRootDir', rootDir);

rx = [];

% Step 1: submenu structure
stepName = 'videoSubmenuGrouping';
try
    rx = epsych.RunExpt('', ReuseExisting=false, CleanupStaleFigures=false);

    mVideo = rx.H.mnu_video;
    assert(isgraphics(mVideo) && strcmp(mVideo.Text,'Video'), ...
        'SmokeTest:NoVideoMenu', 'Utilities has no Video submenu.');
    assert(mVideo.Parent == rx.H.mnu_utilities, ...
        'SmokeTest:WrongParent', 'The Video submenu is not under Utilities.');

    kids = mVideo.Children(end:-1:1);   % Children is in reverse creation order
    got = string({kids.Text});
    expected = ["Webcam Recorder Setup...", ...
                "Live Webcam View (No Recording)", ...
                "Batch Video Converter..."];
    assert(isequal(got, expected), 'SmokeTest:WrongItems', ...
        'Video submenu holds [%s]; expected [%s].', ...
        strjoin(got,' | '), strjoin(expected,' | '));

    % ...and nothing video-related was left behind on Utilities itself.
    utilText = string({rx.H.mnu_utilities.Children.Text});
    stranded = utilText(ismember(utilText, expected));
    assert(isempty(stranded), 'SmokeTest:StrandedItem', ...
        'Still a direct child of Utilities: %s', strjoin(stranded,', '));

    report.steps.(stepName) = struct('passed', true, ...
        'detail', sprintf('Video submenu holds %d items in order.', numel(kids)));
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME,'basic','hyperlinks','off'));
end

% Step 2: the 'setup' tag lockout still reaches the nested item
stepName = 'nestedTagStillFound';
try
    hSetup = findobj(rx.H.figure1, '-regexp', 'tag', '^setup');
    assert(any(hSetup == rx.H.mnu_vlc_liveview), 'SmokeTest:TagUnreachable', ...
        'findobj no longer reaches setup_mnu_vlc_liveview inside the submenu.');
    report.steps.(stepName) = struct('passed', true, ...
        'detail', 'UpdateGUIstate''s findobj still reaches the nested live-view item.');
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME,'basic','hyperlinks','off'));
end

% Step 3: launching the converter GUI
stepName = 'launchVideoConverter';
try
    before = findall(groot, 'Type', 'figure');
    rx.LaunchUtility("VideoConverter");
    after = findall(groot, 'Type', 'figure');
    newFigs = setdiff(after, before);
    assert(isscalar(newFigs), 'SmokeTest:NoConverterWindow', ...
        'Expected one new window from the Batch Video Converter; got %d.', numel(newFigs));
    cFig = onCleanup(@() localDeleteFigure_(newFigs));
    assert(strcmp(newFigs.Name, 'Video Converter'), 'SmokeTest:WrongWindow', ...
        'New window is "%s", not the Video Converter.', newFigs.Name);

    % The converter behind the window: seeded root and .ts-only pattern.
    conv = localFindConverter_(newFigs);
    assert(~isempty(conv), 'SmokeTest:NoConverter', ...
        'Could not recover the util.VideoConverter driving the window.');
    assert(strcmp(conv.RootFolder, rootDir), 'SmokeTest:RootNotSeeded', ...
        'RootFolder is "%s"; expected the recording root "%s".', conv.RootFolder, rootDir);
    assert(contains(conv.FilePattern, 'ts'), 'SmokeTest:PatternNotSeeded', ...
        'FilePattern "%s" is not the .ts pattern.', conv.FilePattern);
    assert(~conv.IsRunning, 'SmokeTest:Running', 'The converter started itself.');

    report.steps.(stepName) = struct('passed', true, ...
        'detail', sprintf('Converter GUI opened on "%s" with pattern %s.', ...
        conv.RootFolder, conv.FilePattern));
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME,'basic','hyperlinks','off'));
end

% Step 4: unset recording root falls back to the Data Save Path
stepName = 'rootFallback';
try
    rmpref(PREF_GROUP, 'RecordingRootDir');
    before = findall(groot, 'Type', 'figure');
    rx.LaunchUtility("VideoConverter");
    newFigs = setdiff(findall(groot,'Type','figure'), before);
    cFig2 = onCleanup(@() localDeleteFigure_(newFigs));
    conv = localFindConverter_(newFigs);
    expected = string(rx.DefaultDataPath);
    assert(strcmp(conv.RootFolder, expected) || strlength(conv.RootFolder) == 0, ...
        'SmokeTest:NoFallback', ...
        'With no recording root, RootFolder is "%s"; expected the data path "%s".', ...
        conv.RootFolder, expected);
    report.steps.(stepName) = struct('passed', true, ...
        'detail', sprintf('Unset recording root fell back to "%s".', conv.RootFolder));
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME,'basic','hyperlinks','off'));
end

localDeleteRunExpt_(rx);
if isfolder(rootDir), rmdir(rootDir); end   % created empty; never written to

% ---- summary ----
stepNames = fieldnames(report.steps);
passed = cellfun(@(s) report.steps.(s).passed, stepNames);
report.allPassed = all(passed);
fprintf('\nsmoke_test_runexpt_video_menu: %d/%d steps passed.\n', sum(passed), numel(passed));
marks = ["FAIL","pass"];
for i = 1:numel(stepNames)
    fprintf('  [%s] %s: %s\n', marks(passed(i)+1), stepNames{i}, ...
        report.steps.(stepNames{i}).detail);
end

end

function conv = localFindConverter_(fig)
% The GUI object is reachable only through the figure's close callback
% closure, so recover it from the object list instead.
conv = [];
objs = findobj(fig);
for i = 1:numel(objs)
    if isprop(objs(i),'Converter')
        conv = objs(i).Converter;
        return
    end
end
% Fall back to the CloseRequestFcn closure's workspace.
fh = fig.CloseRequestFcn;
if isa(fh,'function_handle')
    info = functions(fh);
    if isfield(info,'workspace') && ~isempty(info.workspace) && isfield(info.workspace{1},'obj')
        conv = info.workspace{1}.obj.Converter;
    end
end
end

function snap = snapshotPrefs_(group, keys)
snap = struct('group', group, 'keys', {keys}, 'existed', [], 'values', {{}});
for i = 1:numel(keys)
    snap.existed(i) = ispref(group, keys{i});
    if snap.existed(i)
        snap.values{i} = getpref(group, keys{i});
    end
end
end

function restorePrefs_(group, snap)
for i = 1:numel(snap.keys)
    if snap.existed(i)
        setpref(group, snap.keys{i}, snap.values{i});
    elseif ispref(group, snap.keys{i})
        rmpref(group, snap.keys{i});
    end
end
end

function localDeleteRunExpt_(rx)
% delete(RunExpt) closes figure1 asynchronously (pre-existing behavior), so
% take the figure handle first and delete it outright.
if isempty(rx) || ~isvalid(rx), return, end
fig = rx.H.figure1;
delete(rx);
drawnow;
localDeleteFigure_(fig);
end

function localDeleteFigure_(fig)
for i = 1:numel(fig)
    if isgraphics(fig(i))
        delete(fig(i));
    end
end
end
