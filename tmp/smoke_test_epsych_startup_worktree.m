function smoke_test_epsych_startup_worktree()
% smoke_test_epsych_startup_worktree()
% Exercise epsych_startup's path bookkeeping: hidden-folder filtering relative
% to the checkout root, eviction of other checkouts, removal of stale entries,
% and root resolution from the file that was actually invoked.
%
%   matlab -batch "run('tmp/smoke_test_epsych_startup_worktree.m')"
%
% The dotted-root case uses a real "git worktree" under a dotted directory,
% which is the situation being guarded against. A junction will not do: pwd
% dereferences one, so the checkout under test would silently become the
% original.

here = fileparts(mfilename('fullpath'));
run(fullfile(here, '..', 'epsych_startup.m'));

REPO = fileparts(here);
failures = {};

scratch  = fullfile(tempdir,'epsych_startup_smoke');
worktree = fullfile(scratch,'.dotted','ep');
decoy    = fullfile(scratch,'decoy');

cleanupScratch_(REPO,scratch,worktree);

% ===== A. baseline: one root, nothing hidden ============================
try
    s = epsych_startup(REPO,false);
    entries = strsplit(s,pathsep);

    assert(~isempty(entries), 'no folders were added');
    assert(any(strcmpi(entries,REPO)), 'the root itself is not on the returned list');
    assert(~any(contains(entries,[filesep '.'])), ...
        'a hidden folder survived the filter');
    assert(countRoots_() == 1, 'expected exactly one EPsych root on the path');
    assert(strcmpi(EPsychInfo.root,REPO), ...
        'EPsychInfo.root is "%s", expected "%s"', EPsychInfo.root, REPO);

    fprintf('PASS: A. baseline path setup (%d folders)\n', numel(entries));
catch ME
    failures{end+1} = sprintf('A. baseline: %s', ME.message);
    fprintf('FAIL: A. %s\n', ME.message);
end

% ===== B. stale entries from folders that no longer exist ===============
try
    stale = fullfile(REPO,'zzz_stale_smoke');
    mkdir(stale);
    addpath(stale);
    % Deleted from outside Matlab: rmdir() would prune the path entry itself,
    % which is not what happens when a worktree is removed from a shell.
    system(sprintf('cmd /c rmdir "%s"',stale));
    assert(~isfolder(stale), 'setup: the folder should be gone from disk');
    assert(onPath_(stale), 'setup: the stale folder should be on the path');

    epsych_startup(REPO,false);
    assert(~onPath_(stale), 'a deleted folder was left on the path');

    fprintf('PASS: B. stale path entries are removed\n');
catch ME
    failures{end+1} = sprintf('B. stale entries: %s', ME.message);
    fprintf('FAIL: B. %s\n', ME.message);
end

% ===== C. another checkout is evicted, and does not hijack the root =====
try
    mkdir(decoy);
    mkdir(fullfile(decoy,'sub'));
    fid = fopen(fullfile(decoy,'epsych_startup.m'),'w');
    fprintf(fid,'function epsych_startup(varargin)\nerror(''decoy ran'');\n');
    fclose(fid);

    % Prepended, so which() answers with the decoy: running the real file by
    % its full path must still set up the real tree.
    addpath(decoy,fullfile(decoy,'sub'));
    assert(strcmpi(fileparts(which('epsych_startup')),decoy), ...
        'setup: the decoy should shadow epsych_startup');

    out = evalc(sprintf('run(''%s'')',fullfile(REPO,'epsych_startup.m')));

    assert(~onPath_(decoy), 'the decoy root was left on the path');
    assert(~onPath_(fullfile(decoy,'sub')), 'a decoy subfolder was left on the path');
    assert(countRoots_() == 1, 'expected exactly one EPsych root after eviction');
    assert(strcmpi(fileparts(which('epsych_startup')),REPO), ...
        'the real checkout did not win after eviction');
    assert(contains(out,'removed another checkout'), ...
        'the eviction was not reported to the user');

    fprintf('PASS: C. other checkouts are evicted and reported\n');
catch ME
    failures{end+1} = sprintf('C. eviction: %s', ME.message);
    fprintf('FAIL: C. %s\n', ME.message);
end

% ===== D. a checkout living under a dotted directory ====================
% This is the worktree case: every folder inherits "\." from the parent, which
% used to empty the path list entirely.
try
    mkdir(fileparts(worktree));
    [st,msg] = system(sprintf('git -C "%s" worktree add --detach "%s" HEAD',REPO,worktree));
    assert(st == 0, 'could not create the worktree: %s', strtrim(msg));
    assert(contains(worktree,[filesep '.']), 'setup: the root is not under a dotted folder');

    s = epsych_startup(worktree,false);
    entries = strsplit(s,pathsep);
    rel = cellfun(@(e) e(numel(worktree)+1:end),entries,'UniformOutput',false);

    assert(numel(entries) > 1, 'the dotted root produced %d folders', numel(entries));
    assert(strcmpi(entries{1},worktree), ...
        'the returned root is "%s", expected "%s"', entries{1}, worktree);
    assert(~any(contains(rel,[filesep '.'])), ...
        'a hidden folder below the dotted root survived the filter');
    assert(~onPath_(REPO), 'the original checkout was not evicted');
    assert(countRoots_() == 1, 'expected exactly one EPsych root on the path');

    fprintf('PASS: D. dotted root adds %d folders\n', numel(entries));
catch ME
    failures{end+1} = sprintf('D. dotted root: %s', ME.message);
    fprintf('FAIL: D. %s\n', ME.message);
end

% ===== E. sibling roots sharing a name prefix are not confused ==========
try
    % By full path, not by name: only the worktree is on the path right now,
    % so calling epsych_startup by name would run the worktree's copy.
    run(fullfile(REPO,'epsych_startup.m'));
    assert(onPath_(REPO), 'the real checkout is not on the path');
    assert(strcmpi(fileparts(which('epsych_startup')),REPO), ...
        'epsych_startup still resolves to "%s"', fileparts(which('epsych_startup')));
    assert(countRoots_() == 1, 'expected exactly one EPsych root after restore');
    assert(~pathIsUnderTest_([REPO '-async'],REPO), ...
        '"%s-async" was treated as a subfolder of "%s"', REPO, REPO);

    fprintf('PASS: E. prefix-sharing siblings stay distinct\n');
catch ME
    failures{end+1} = sprintf('E. sibling prefixes: %s', ME.message);
    fprintf('FAIL: E. %s\n', ME.message);
end

cleanupScratch_(REPO,scratch,worktree);

fprintf('\n');
if isempty(failures)
    fprintf('ALL PASSED\n');
else
    fprintf('%d FAILURE(S):\n', numel(failures));
    fprintf('  %s\n', failures{:});
end


function cleanupScratch_(repo,scratch,worktree)
% Let git take the worktree down -- it owns the administrative files under
% .git/worktrees as well as the checkout -- then clear the scratch tree.
if isfolder(worktree)
    system(sprintf('git -C "%s" worktree remove --force "%s"',repo,worktree));
end
system(sprintf('git -C "%s" worktree prune',repo));
if isfolder(scratch) && ~isfolder(worktree)
    rmdir(scratch,'s');
end


function tf = onPath_(d)
entries = strsplit(path,pathsep);
tf = any(strcmpi(entries,d));


function n = countRoots_()
entries = strsplit(path,pathsep);
entries = entries(~cellfun(@isempty,entries));
n = sum(cellfun(@(e) isfile(fullfile(e,'epsych_startup.m')),entries));


function tf = pathIsUnderTest_(p,root)
% Mirrors epsych_startup's prefix rule so the sibling-name case is asserted
% here rather than only implied by the path contents.
tf = strncmpi([p filesep],[root filesep],numel(root)+1);
